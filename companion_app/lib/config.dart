// Android emulator reaches your PC's localhost via 10.0.2.2.
// On a real phone use your PC's LAN IP and run uvicorn with --host 0.0.0.0
const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://192.168.1.2:8000',
);

// The family member the demo calls ("Ask my family" + Call task).
// Override at build time: flutter run --dart-define=HELPER_PHONE=923001234567
const helperPhone = String.fromEnvironment('HELPER_PHONE', defaultValue: '923001234567');
const helperNameUr = String.fromEnvironment('HELPER_NAME_UR', defaultValue: 'علی (بیٹا)');
const helperNameEn = String.fromEnvironment('HELPER_NAME_EN', defaultValue: 'Ali (son)');
