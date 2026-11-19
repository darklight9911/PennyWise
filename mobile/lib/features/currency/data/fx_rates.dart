import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// The latest daily rates: 1 [base] buys rates[quote] of each currency.
class FxRates {
  const FxRates({required this.base, required this.date, required this.rates});

  final String base;
  final String date;
  final Map<String, String> rates;
}

/// Reads GET /v1/fx/rates.
class FxApi {
  FxApi(this._dio);

  final Dio _dio;

  Future<FxRates> latest(String base) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/fx/rates',
        queryParameters: {'base': base},
        // Public: works without an account.
        options: Options(extra: {'auth': false}),
      );
      final d = res.data!;
      return FxRates(
        base: d['base'] as String,
        date: d['date'] as String,
        rates: (d['rates'] as Map).cast<String, String>(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final fxApiProvider = Provider<FxApi>((ref) => FxApi(ref.watch(dioProvider)));

/// Today's rates for [base], or null when offline or the currency has no
/// daily rate. Only used to show converted balances; stored amounts use
/// the rate of each transaction's own date (worked out by the server).
final fxRatesProvider = FutureProvider.family<FxRates?, String>((
  ref,
  base,
) async {
  try {
    return await ref.watch(fxApiProvider).latest(base);
  } on ApiException {
    return null;
  }
});
