import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'receipt_files.dart';

/// A plain HTTP client for uploads straight to storage (R2). It must not
/// add the API's login token: the signed URL is the only permission.
final uploadDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(seconds: 30),
    ),
  ),
);

/// Uploads new receipt photos and carries out deletions on the server.
/// Runs after each sync, so the transaction is already on the server.
class ReceiptSync {
  ReceiptSync({
    required this.db,
    required this.api,
    required this.upload,
    required this.files,
  });

  final AppDatabase db;
  final Dio api; // with login token
  final Dio upload; // without
  final ReceiptFiles files;

  /// Returns how many receipts were uploaded. Network errors are thrown
  /// (the caller treats them like an offline sync); a server without R2
  /// ("receipts_unavailable") just leaves the photos on the phone.
  Future<int> run() async {
    final gone =
        await (db.select(db.receipts)..where(
              (r) => r.deletedAt.isNotNull() & r.status.equals('uploaded'),
            ))
            .get();
    for (final r in gone) {
      try {
        await api.delete<void>('/v1/receipts/${r.id}');
      } on DioException catch (e) {
        final err = ApiException.fromDio(e);
        if (err.statusCode != 404) {
          if (err.code == 'receipts_unavailable') return 0;
          throw err;
        }
      }
      await (db.delete(db.receipts)..where((x) => x.id.equals(r.id))).go();
    }

    final waiting = await (db.select(
      db.receipts,
    )..where((r) => r.deletedAt.isNull() & r.status.equals('local'))).get();
    var uploaded = 0;
    for (final r in waiting) {
      final bytes = r.localPath == null ? null : await files.read(r.localPath!);
      if (bytes == null) {
        await (db.delete(db.receipts)..where((x) => x.id.equals(r.id))).go();
        continue;
      }
      try {
        final res = await api.post<Map<String, dynamic>>(
          '/v1/receipts/upload-url',
          data: {
            'id': r.id,
            'transaction_id': r.transactionId,
            'content_type': r.contentType,
            'size_bytes': bytes.length,
          },
        );
        final d = res.data!;
        await upload.put<void>(
          d['url'] as String,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: (d['headers'] as Map).cast<String, dynamic>(),
          ),
        );
        await api.post<void>('/v1/receipts/${r.id}/confirm');
      } on DioException catch (e) {
        final err = ApiException.fromDio(e);
        switch (err.code) {
          case 'receipts_unavailable':
            return uploaded; // the server keeps no photos (yet)
          case 'transaction_not_synced':
            continue; // next time
          case 'too_many' || 'bad_type' || 'too_big' || 'id_conflict':
            // The server will never take it: keep it on the phone only.
            continue;
        }
        throw err;
      }
      await (db.update(db.receipts)..where((x) => x.id.equals(r.id))).write(
        const ReceiptsCompanion(status: Value('uploaded')),
      );
      uploaded++;
    }
    return uploaded;
  }

  /// A short-lived link to view a receipt that is only on the server.
  static Future<String> viewUrl(Dio api, String id) async {
    try {
      final res = await api.get<Map<String, dynamic>>('/v1/receipts/$id/url');
      return res.data!['url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// The app's [ReceiptSync] for the current database.
ReceiptSync receiptSyncFor(Ref ref, AppDatabase db) => ReceiptSync(
  db: db,
  api: ref.read(dioProvider),
  upload: ref.read(uploadDioProvider),
  files: ref.read(receiptFilesProvider),
);
