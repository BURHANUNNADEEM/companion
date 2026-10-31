// Android emulator reaches your PC's localhost via 10.0.2.2.
// On a real phone use your PC's LAN IP and run uvicorn with --host 0.0.0.0
const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://192.168.1.2:8000',
);