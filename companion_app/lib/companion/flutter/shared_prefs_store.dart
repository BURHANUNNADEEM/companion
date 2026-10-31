import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage.dart';

/// Saves Companion data on the phone (no server).
class SharedPrefsStore implements KeyValueStore {
  final SharedPreferences _p;
  SharedPrefsStore(this._p);

  static Future<SharedPrefsStore> create() async =>
      SharedPrefsStore(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => _p.getString(key);
  @override
  Future<void> setString(String key, String value) => _p.setString(key, value);
  @override
  Future<void> remove(String key) => _p.remove(key);
  @override
  Iterable<String> get keys => _p.getKeys();
}
