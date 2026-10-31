/// Build-time configuration via --dart-define.
///
///   flutter run --flavor demo \
///     --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
///     --dart-define=AUTH_MODE=dev
class AppConfig {
  /// 10.0.2.2 is the host machine from the Android emulator.
  static const apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// `firebase` (default, real login) or `dev` (no Firebase; backend must run with AUTH_MODE=dev).
  static const authMode = String.fromEnvironment('AUTH_MODE', defaultValue: 'firebase');

  static bool get isDevAuth => authMode == 'dev';
}
