import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pennywise/core/config/app_config.dart';
import 'package:pennywise/features/app_lock/application/app_lock.dart';
import 'package:pennywise/features/app_lock/application/biometrics.dart';
import 'package:pennywise/core/storage/device_prefs.dart';
import 'package:pennywise/features/receipts/data/receipt_files.dart';
import 'package:pennywise/features/receipts/data/receipt_picker.dart';
import 'package:pennywise/features/receipts/data/receipt_sync.dart';
import 'package:pennywise/core/platform/link_opener.dart';
import 'package:pennywise/features/export/data/local_export.dart';
import 'package:pennywise/features/currency/presentation/recalculating_banner.dart';
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
  String? get countryCode => 'US';
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

  /// Fingerprint / face on the "phone".
  final biometrics = FakeBiometrics();

  /// Time for the app lock rules; tests move it forward.
  DateTime clock = DateTime(2026, 11, 19, 12);

  /// Settings of the "phone" (theme, app lock).
  final prefs = MemoryDevicePrefs();

  /// Receipt photos on the "phone".
  final receiptFiles = MemoryReceiptFiles();

  /// What the photo picker returns next (null: the user cancelled).
  PickedPhoto? nextPhoto;
  final pickedFrom = <PhotoSource>[];

  /// Links the app asked the phone to open (e.g. export downloads).
  final opened = <Uri>[];

  /// Files handed to the share sheet.
  final shared = <({List<int> bytes, String name, String mime})>[];

  List<Override> get overrides => [
    appConfigProvider.overrideWithValue(config),
    tokenStoreProvider.overrideWithValue(store),
    deviceProfileProvider.overrideWithValue(device),
    googleAuthProvider.overrideWithValue(FakeGoogleAuth()),
    incomingLinksProvider.overrideWithValue(links.stream),
    localDatabaseProvider.overrideWithValue(local),
    syncDebounceProvider.overrideWithValue(Duration.zero),
    recalcPollProvider.overrideWithValue(const Duration(milliseconds: 200)),
    fileSharerProvider.overrideWithValue((bytes, name, mime) async {
      shared.add((bytes: bytes, name: name, mime: mime));
    }),
    receiptFilesProvider.overrideWithValue(receiptFiles),
    devicePrefsProvider.overrideWithValue(prefs),
    biometricsProvider.overrideWithValue(biometrics),
    lockClockProvider.overrideWithValue(() => clock),
    uploadDioProvider.overrideWithValue(Dio()..httpClientAdapter = backend),
    photoPickerProvider.overrideWithValue((source) async {
      pickedFrom.add(source);
      return nextPhoto;
    }),
    linkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
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

class FakeBiometrics implements Biometrics {
  bool hasBiometrics = true;
  bool willSucceed = true;
  int prompts = 0;

  @override
  Future<bool> available() async => hasBiometrics;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return willSucceed;
  }
}
