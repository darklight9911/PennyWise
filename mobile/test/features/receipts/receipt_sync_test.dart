import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/core/network/api_exception.dart';
import 'package:pennywise/features/auth/data/auth_api.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/receipts/data/receipt_files.dart';
import 'package:pennywise/features/receipts/data/receipt_store.dart';
import 'package:pennywise/features/receipts/data/receipt_sync.dart';
import 'package:pennywise/features/sync/sync_engine.dart';

import '../../support/test_app.dart';

const email = 'ann@example.com';

void main() {
  late TestHarness h;
  late AppDatabase db;
  late LedgerStore ledger;
  late ReceiptStore receipts;
  late MemoryReceiptFiles files;
  late SyncEngine engine;
  late ReceiptSync uploader;
  late MoneyTransaction tx;

  setUp(() async {
    h = TestHarness();
    h.backend.seedUser(email, 'ann-password-1');
    final c = h.container();
    addTearDown(c.dispose);
    final login = await c
        .read(authApiProvider)
        .login(email: email, password: 'ann-password-1', deviceName: 't');
    await c.read(sessionManagerProvider).save(login.tokens);

    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    files = MemoryReceiptFiles();
    ledger = LedgerStore(db);
    receipts = ReceiptStore(db, files);
    engine = SyncEngine(db: db, dio: c.read(dioProvider), receiptFiles: files);
    uploader = ReceiptSync(
      db: db,
      api: c.read(dioProvider),
      upload: Dio()..httpClientAdapter = h.backend,
      files: files,
    );
    final cash = await ledger.createAccount(
      name: 'Cash',
      type: 'cash',
      currency: 'USD',
    );
    final food = await ledger.createCategory(name: 'Food', kind: 'expense');
    tx = await ledger.createTransaction(
      kind: TxKind.expense,
      accountId: cash.id,
      amountMinor: 500,
      currency: 'USD',
      occurredAt: DateTime.utc(2026, 11, 15, 12),
      categoryId: food.id,
    );
  });

  final photo = Uint8List.fromList(List.generate(300, (i) => i % 256));

  Future<Receipt> only() async => (await db.select(db.receipts).get()).single;

  test(
    'a photo is kept offline, then uploaded after its transaction',
    () async {
      final r = await receipts.add(tx.id, photo, 'image/jpeg');
      expect(r.status, 'local');
      expect(files.files, hasLength(1));

      // Before the transaction is on the server: nothing is lost, it waits.
      expect(await uploader.run(), 0);
      expect((await only()).status, 'local');

      await engine.sync();
      expect(await uploader.run(), 1);
      expect((await only()).status, 'uploaded');
      expect(h.backend.bucket[r.id], photo);
      expect(
        h.backend.uploadSawToken,
        isFalse,
        reason: 'the upload must not carry the login token',
      );

      // The confirm made it part of sync; pulling it again changes nothing.
      await engine.sync();
      expect((await only()).localPath, isNotNull);
    },
  );

  test('limits are checked on the phone', () async {
    for (var i = 0; i < maxReceiptsPerTransaction; i++) {
      await receipts.add(tx.id, photo, 'image/png');
    }
    expect(
      () => receipts.add(tx.id, photo, 'image/png'),
      throwsA(isA<ReceiptException>()),
    );
    expect(
      () => receipts.add(tx.id, Uint8List(maxReceiptBytes + 1), 'image/jpeg'),
      throwsA(isA<ReceiptException>()),
    );
    expect(
      () => receipts.add(tx.id, photo, 'image/gif'),
      throwsA(isA<ReceiptException>()),
    );
  });

  test(
    'deleting: a local photo goes at once, an uploaded one on the server too',
    () async {
      final local = await receipts.add(tx.id, photo, 'image/jpeg');
      await receipts.delete(local);
      expect(await db.select(db.receipts).get(), isEmpty);
      expect(files.files, isEmpty);

      final up = await receipts.add(tx.id, photo, 'image/jpeg');
      await engine.sync();
      await uploader.run();
      await receipts.delete(await only());
      expect(
        await receipts.watch(tx.id).first,
        isEmpty,
        reason: 'hidden at once',
      );
      await uploader.run();
      expect(await db.select(db.receipts).get(), isEmpty);
      expect(h.backend.bucket.containsKey(up.id), isFalse);
    },
  );

  test('a server without storage leaves photos on the phone', () async {
    h.backend.receiptsError = 'receipts_unavailable';
    await receipts.add(tx.id, photo, 'image/jpeg');
    await engine.sync();
    expect(await uploader.run(), 0);
    expect((await only()).status, 'local');
  });

  test('offline upload fails like a sync (and is tried again)', () async {
    await receipts.add(tx.id, photo, 'image/jpeg');
    await engine.sync();
    h.backend.offline = true;
    await expectLater(uploader.run(), throwsA(isA<ApiException>()));
    h.backend.offline = false;
    expect(await uploader.run(), 1);
  });

  test(
    "another phone's receipts arrive by pull and leave with their tombstone",
    () async {
      await engine.sync();
      final id = '0193c0de-0000-4000-8000-000000000001';
      h.backend.serverWrite(email, Entity.receipt, id, {
        'transaction_id': tx.id,
        'content_type': 'image/jpeg',
        'size_bytes': 1234,
      }, updatedAt: DateTime.utc(2026, 11, 16));
      await engine.sync();
      final r = await only();
      expect((r.id, r.status, r.localPath), (id, 'uploaded', null));

      h.backend.serverWrite(
        email,
        Entity.receipt,
        id,
        {
          'transaction_id': tx.id,
          'content_type': 'image/jpeg',
          'size_bytes': 1234,
        },
        updatedAt: DateTime.utc(2026, 11, 17),
        deletedAt: DateTime.utc(2026, 11, 17),
      );
      await engine.sync();
      expect(await db.select(db.receipts).get(), isEmpty);
    },
  );
}
