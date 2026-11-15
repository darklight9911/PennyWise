import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pennywise/core/config/app_config.dart';
import 'package:pennywise/core/database/local_database.dart';
import 'package:pennywise/core/device/device_profile.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/core/network/token_store.dart';
import 'package:pennywise/core/router/deep_links.dart';
import 'package:pennywise/features/auth/data/google_auth.dart';
import 'package:pennywise/features/sync/sync_controller.dart';

import 'fake_backend.dart';
import 'fake_local_database.dart';

/// Device facts without platform plugins.
class FakeDeviceProfile extends DeviceProfile {
  const FakeDeviceProfile();
  @override
  String get deviceName => 'test-phone';
  @override
  String get locale => 'en-US';
  @override
  Future<String> timezone() async => 'Asia/Dhaka';
  @override
  String get defaultCurrency => 'USD';
}

/// A device whose platform calls fail, to test error handling.
class BrokenDeviceProfile extends FakeDeviceProfile {
  const BrokenDeviceProfile();
  @override
  String get deviceName => throw StateError('platform call failed');
}

class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.enabled = false});
  @override
  final bool enabled;
  @override
  Future<String?> signIn() async => null;
  @override
  Future<void> signOut() async {}
}

/// Everything a test needs to run the app against [FakeBackend].
class TestHarness {
  TestHarness({
    FakeBackend? backend,
    InMemoryTokenStore? store,
    this.device = const FakeDeviceProfile(),
  }) : backend = backend ?? FakeBackend(),
       store = store ?? InMemoryTokenStore();

  final DeviceProfile device;

  final FakeBackend backend;
  final InMemoryTokenStore store;
  final local = FakeLocalDatabase();
  final links = StreamController<Uri>.broadcast();

  static const config = AppConfig(apiBaseUrl: 'http://fake.test');

  List<Override> get overrides => [
    appConfigProvider.overrideWithValue(config),
    tokenStoreProvider.overrideWithValue(store),
    deviceProfileProvider.overrideWithValue(device),
    googleAuthProvider.overrideWithValue(FakeGoogleAuth()),
    incomingLinksProvider.overrideWithValue(links.stream),
    localDatabaseProvider.overrideWithValue(local),
    syncDebounceProvider.overrideWithValue(Duration.zero),
    sessionManagerProvider.overrideWith((ref) {
      final s = SessionManager(
        refreshDio: _dio(),
        store: store,
        now: () => backend.now(),
      );
      ref.onDispose(s.dispose);
      return s;
    }),
    dioProvider.overrideWith((ref) {
      final dio = _dio();
      dio.interceptors.add(
        AuthInterceptor(ref.watch(sessionManagerProvider), dio),
      );
      return dio;
    }),
  ];

  Dio _dio() =>
      Dio(BaseOptions(baseUrl: config.apiBaseUrl))..httpClientAdapter = backend;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides);
    return c;
  }
}
