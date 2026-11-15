import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time settings, passed with --dart-define, for example:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
///               --dart-define=GOOGLE_SERVER_CLIENT_ID=123-abc.apps.googleusercontent.com
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.googleServerClientId = ''});

  /// Base URL of the Go API, without a trailing slash.
  /// Default: the host machine as seen from the Android emulator.
  final String apiBaseUrl;

  /// OAuth "web" client ID of the backend. Google puts it in the ID token's
  /// audience. Empty means Google sign-in is hidden.
  final String googleServerClientId;

  bool get googleEnabled => googleServerClientId.isNotEmpty;

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8080',
    ),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
  );
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment,
);
