import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'contacts_store.dart';
import 'event_tracker.dart';
import 'struggle_detector.dart';

/// App-wide state: language (Urdu first), bigger text, current user, consent, remote config.
class AppState extends ChangeNotifier {
  AppState({this.api, StruggleDetector? detector, ContactsStore? contacts})
      : detector = detector ?? StruggleDetector(),
        contacts = contacts ?? ContactsStore() {
    if (api != null) tracker = EventTracker(api!, this.detector);
  }

  final ApiClient? api;
  final StruggleDetector detector;
  final ContactsStore contacts;
  EventTracker? tracker;

  String lang = 'ur';
  bool bigText = false;
  Map<String, dynamic>? me;
  bool loadingMe = false;
  String? error;

  String? get role => me?['role'] as String?;
  Map<String, dynamic> get consent => Map<String, dynamic>.from(me?['consent'] as Map? ?? {});
  bool get consentDone => consent['completed'] == true;
  bool get isUrdu => lang == 'ur';

  Future<void> loadLocal() async {
    final p = await SharedPreferences.getInstance();
    lang = p.getString('lang') ?? 'ur';
    bigText = p.getBool('big_text') ?? false;
    await contacts.load();
    notifyListeners();
  }

  Future<void> setLang(String value) async {
    lang = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', value);
    if (me != null) {
      try {
        await api?.put('/me/language', {'language': value});
      } on ApiException catch (_) {}
    }
  }

  Future<void> setBigText(bool value) async {
    bigText = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('big_text', value);
  }

  Future<void> refreshMe() async {
    if (api == null) return;
    loadingMe = true;
    error = null;
    notifyListeners();
    try {
      me = await api!.me();
      // keep the server and the device language in sync (device choice wins on first login)
      if (me!['language'] != lang) {
        await api!.put('/me/language', {'language': lang});
        me!['language'] = lang;
      }
      tracker?.enabled = consent['activity_tracking'] == true;
      try {
        final cfg = await api!.config();
        detector.config = StruggleConfig.fromJson(Map<String, dynamic>.from(cfg['struggle'] as Map));
      } on ApiException catch (_) {}
    } on ApiException catch (e) {
      error = e.isOffline ? 'offline' : e.detail;
    } finally {
      loadingMe = false;
      notifyListeners();
    }
  }

  Future<void> setRole(String role) async {
    me = Map<String, dynamic>.from(await api!.put('/me/role', {'role': role}));
    notifyListeners();
  }

  Future<void> saveConsent(Map<String, bool> values) async {
    final r = await api!.put('/consent', values);
    me ??= {};
    me!['consent'] = r['consent'];
    tracker?.enabled = r['consent']['activity_tracking'] == true;
    notifyListeners();
  }

  Future<void> deleteMyData() async {
    await api!.delete('/me/data');
    tracker?.enabled = false;
    me = null;
    notifyListeners();
  }

  void clearUser() {
    me = null;
    tracker?.enabled = false;
    notifyListeners();
  }
}
