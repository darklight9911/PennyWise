import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A message safe to show for ANY error. Unexpected errors (bugs, plugin
/// failures) get a calm generic text and are logged, so a screen never
/// fails silently.
String userMessage(Object error, [StackTrace? stack]) {
  if (error is ApiException) return error.message;
  FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'pennyWise'),
  );
  return 'Something went wrong. Please try again.';
}

/// An error from the API, or a network failure, in one shape the UI can show.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.field,
  });

  /// Stable code from the server (e.g. "invalid_credentials"), or
  /// "network_error" / "unknown" for client-side failures.
  final String code;

  /// Human-readable message, safe to show.
  final String message;

  final int? statusCode;

  /// Set for "validation_failed": the request field that was wrong.
  final String? field;

  bool get isNetworkError => code == 'network_error';

  /// Converts any Dio error into an ApiException.
  factory ApiException.fromDio(DioException e) {
    final inner = e.error;
    if (inner is ApiException) return inner;

    final response = e.response;
    if (response == null) {
      return const ApiException(
        code: 'network_error',
        message: 'Cannot reach the server. Check your internet connection.',
      );
    }
    final data = response.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        code: err['code'] as String? ?? 'unknown',
        message: err['message'] as String? ?? 'Something went wrong.',
        statusCode: response.statusCode,
        field: err['field'] as String?,
      );
    }
    return ApiException(
      code: 'unknown',
      message: 'Something went wrong (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
