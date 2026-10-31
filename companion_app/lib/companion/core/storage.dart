/// Minimal key-value storage so the core stays pure Dart.
/// On the phone use SharedPrefsStore (lib/companion/flutter/shared_prefs_store.dart).
abstract class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
  Iterable<String> get keys;
}

class InMemoryStore implements KeyValueStore {
  final Map<String, String> _m = {};
  @override
  String? getString(String key) => _m[key];
  @override
  Future<void> setString(String key, String value) async => _m[key] = value;
  @override
  Future<void> remove(String key) async => _m.remove(key);
  @override
  Iterable<String> get keys => _m.keys;
}

typedef Clock = DateTime Function();
DateTime systemClock() => DateTime.now();

/// All keys Companion writes start with this prefix (used by Delete my data).
const storePrefix = 'companion.';
