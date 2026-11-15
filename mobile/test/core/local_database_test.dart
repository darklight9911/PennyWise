import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/database_key.dart';
import 'package:pennywise/core/database/encryption.dart';
import 'package:pennywise/core/database/local_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late File file;
  late InMemoryDatabaseKeyStore keys;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pennywise_db_test');
    file = File('${dir.path}/pennywise.db');
    keys = InMemoryDatabaseKeyStore();
  });
  tearDown(() => dir.delete(recursive: true));

  LocalDatabase local() => LocalDatabase(file: () async => file, keys: keys);

  const secret = 'salary-4250-BDT-very-private';

  test('data survives closing and reopening with the same key', () async {
    final a = local();
    await (await a.database).writeMeta('note', secret);
    await a.close();

    final b = local();
    expect(await (await b.database).readMeta('note'), secret);
    await b.close();
  });

  test('the file on disk is encrypted', () async {
    final a = local();
    await (await a.database).writeMeta('note', secret);
    await a.close();

    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(0));
    // A plain SQLite file always starts with this header.
    expect(latin1.decode(bytes.sublist(0, 15)), isNot('SQLite format 3'));
    // The stored text appears nowhere in the file.
    expect(latin1.decode(bytes).contains(secret), isFalse);
    // And plain SQLite cannot read it.
    final raw = sqlite3.open(file.path);
    expect(
      () => raw.select('SELECT * FROM local_meta'),
      throwsA(isA<SqliteException>()),
    );
    raw.close();
  });

  test('a wrong key cannot open the file', () async {
    final a = local();
    await (await a.database).writeMeta('note', secret);
    await a.close();

    final raw = sqlite3.open(file.path);
    expect(
      () => unlockDatabase(raw, generateHexKey()),
      throwsA(isA<WrongDatabaseKeyError>()),
    );
    raw.close();
  });

  test('a lost key means a fresh empty database (old file deleted)', () async {
    final a = local();
    await (await a.database).writeMeta('note', secret);
    await a.close();
    final oldKey = keys.key;

    keys.key = null; // e.g. app data restored onto a new phone
    final b = local();
    expect(await (await b.database).readMeta('note'), isNull);
    expect(keys.key, isNot(oldKey));
    await b.close();
  });

  test('a mismatched key also starts fresh instead of crashing', () async {
    final a = local();
    await (await a.database).writeMeta('note', secret);
    await a.close();

    keys.key = generateHexKey(); // key exists but belongs to nothing
    final b = local();
    expect(await (await b.database).readMeta('note'), isNull);
    await b.close();
  });

  test('wipe deletes the data files and the key', () async {
    final a = local();
    await (await a.database).writeMeta('note', secret);
    await a.wipe();

    expect(keys.key, isNull);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(
        File('${file.path}$suffix').existsSync(),
        isFalse,
        reason: 'file$suffix',
      );
    }
    // The manager can open again afterwards (next login).
    expect(await (await a.database).readMeta('note'), isNull);
    await a.close();
  });

  test(
    'claimFor keeps data for the same user and wipes it for another',
    () async {
      final a = local();
      await (await a.claimFor('user-1')).writeMeta('note', secret);
      final firstKey = keys.key;

      expect(await (await a.claimFor('user-1')).readMeta('note'), secret);
      expect(keys.key, firstKey, reason: 'same user: same key, same data');

      final db = await a.claimFor('user-2');
      expect(await db.readMeta('note'), isNull);
      expect(await db.readMeta('owner_user_id'), 'user-2');
      expect(keys.key, isNot(firstKey), reason: 'new user: new key');
      await a.close();
    },
  );

  test('keys are 256-bit random hex', () {
    final k1 = generateHexKey();
    final k2 = generateHexKey();
    expect(k1, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(k1, isNot(k2));
  });

  test('a malformed key is rejected before touching the database', () {
    final raw = sqlite3.openInMemory();
    expect(
      () => unlockDatabase(raw, "x'; DROP TABLE a; --"),
      throwsArgumentError,
    );
    raw.close();
  });

  test('close hooks run (and finish) before the database is wiped', () async {
    final a = local();
    final db = await a.database;
    final events = <String>[];
    final remove = a.addCloseHook(() async {
      // The database is still open here: a running sync can finish its write.
      await db.writeMeta('last', 'write');
      events.add('hook');
    });
    await a.wipe();
    events.add('wiped');
    expect(events, ['hook', 'wiped']);

    remove();
    await (await a.database).writeMeta('x', 'y');
    await a.wipe();
    expect(events, ['hook', 'wiped'], reason: 'removed hooks do not run');
  });
}
