import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import 'receipt_files.dart';

/// Receipt limits, as on the server.
const maxReceiptsPerTransaction = 3;
const maxReceiptBytes = 2 * 1024 * 1024;

/// Why a photo could not be added.
class ReceiptException implements Exception {
  const ReceiptException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Receipt photos on the phone: added at once (offline too), uploaded by
/// [ReceiptSync] at the next sync.
class ReceiptStore {
  ReceiptStore(this.db, this.files, {this.onChange});

  final AppDatabase db;
  final ReceiptFiles files;

  /// Called after a change that the server should hear about.
  final void Function()? onChange;

  Stream<List<Receipt>> watch(String transactionId) =>
      (db.select(db.receipts)
            ..where(
              (r) =>
                  r.transactionId.equals(transactionId) & r.deletedAt.isNull(),
            )
            ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
          .watch();

  Future<Receipt> add(
    String transactionId,
    Uint8List bytes,
    String contentType,
  ) async {
    if (bytes.length > maxReceiptBytes) {
      throw const ReceiptException('This photo is too large (over 2 MB).');
    }
    if (contentType != 'image/jpeg' && contentType != 'image/png') {
      throw const ReceiptException('Only JPEG and PNG photos can be attached.');
    }
    final count =
        await (db.select(db.receipts)..where(
              (r) =>
                  r.transactionId.equals(transactionId) & r.deletedAt.isNull(),
            ))
            .get();
    if (count.length >= maxReceiptsPerTransaction) {
      throw const ReceiptException(
        'A transaction can have up to 3 receipt photos.',
      );
    }
    final id = const Uuid().v4();
    final path = await files.write(
      id,
      contentType == 'image/png' ? 'png' : 'jpg',
      bytes,
    );
    final row = await db
        .into(db.receipts)
        .insertReturning(
          ReceiptsCompanion.insert(
            id: id,
            transactionId: transactionId,
            contentType: contentType,
            sizeBytes: bytes.length,
            localPath: Value(path),
            status: 'local',
            createdAt: DateTime.now().toUtc(),
          ),
        );
    onChange?.call();
    return row;
  }

  /// Removes a receipt. One the server never got is simply dropped; an
  /// uploaded one is hidden now and deleted on the server at the next sync.
  Future<void> delete(Receipt r) async {
    if (r.localPath != null) await files.delete(r.localPath!);
    if (r.status == 'local') {
      await (db.delete(db.receipts)..where((x) => x.id.equals(r.id))).go();
      return;
    }
    await (db.update(db.receipts)..where((x) => x.id.equals(r.id))).write(
      ReceiptsCompanion(
        localPath: const Value(null),
        deletedAt: Value(DateTime.now().toUtc()),
      ),
    );
    onChange?.call();
  }

  /// Removes every photo of a transaction (when it is deleted).
  Future<void> deleteAllOf(String transactionId) async {
    final list =
        await (db.select(db.receipts)..where(
              (r) =>
                  r.transactionId.equals(transactionId) & r.deletedAt.isNull(),
            ))
            .get();
    for (final r in list) {
      await delete(r);
    }
  }

  /// The photo's bytes if it is on this phone.
  Future<Uint8List?> localBytes(Receipt r) async =>
      r.localPath == null ? null : files.read(r.localPath!);
}
