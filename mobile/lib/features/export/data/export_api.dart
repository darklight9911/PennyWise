import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// An export file the server builds in the background.
class ExportJob {
  const ExportJob({
    required this.id,
    required this.format,
    required this.status,
    required this.fileName,
    this.error = '',
    this.downloadUrl,
  });

  final String id;
  final String format; // csv or pdf
  final String status; // pending, ready, failed or expired
  final String fileName;
  final String error;
  final String? downloadUrl;

  bool get pending => status == 'pending';

  factory ExportJob.fromJson(Map<String, dynamic> j) => ExportJob(
    id: j['id'] as String,
    format: j['format'] as String,
    status: j['status'] as String,
    fileName: j['file_name'] as String? ?? 'pennywise.${j['format']}',
    error: j['error'] as String? ?? '',
    downloadUrl: j['download_url'] as String?,
  );
}

/// POST /v1/exports and GET /v1/exports/{id}.
class ExportApi {
  ExportApi(this._dio);

  final Dio _dio;

  Future<ExportJob> create({
    required String format,
    required String from,
    required String to,
  }) => _call(
    () => _dio.post<Map<String, dynamic>>(
      '/v1/exports',
      data: {'format': format, 'from': from, 'to': to},
    ),
  );

  Future<ExportJob> get(String id) =>
      _call(() => _dio.get<Map<String, dynamic>>('/v1/exports/$id'));

  Future<ExportJob> _call(
    Future<Response<Map<String, dynamic>>> Function() fn,
  ) async {
    try {
      final res = await fn();
      return ExportJob.fromJson(res.data!['export'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final exportApiProvider = Provider<ExportApi>(
  (ref) => ExportApi(ref.watch(dioProvider)),
);

/// How often to ask whether a file is ready. Tests shorten it.
final exportPollProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);
