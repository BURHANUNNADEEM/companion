import 'dart:async';

import 'package:flutter/services.dart';

/// Platform-channel bridge to the Kotlin Accessibility module (F10 Tier 2, sideloaded demo build only).
///
/// Flutter only asks the native side to run a *bundled* skill id; the Kotlin SkillRunner re-validates
/// the id, applies the denylist on every screen, limits runs to 10 steps / 30 s and shows Stop.
class Tier2Bridge {
  static const _methods = MethodChannel('companion/tier2');
  static const _events = EventChannel('companion/tier2/events');

  Stream<Map<String, dynamic>>? _stream;

  Stream<Map<String, dynamic>> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .handleError((_) {});

  Future<bool> isAvailable() => _bool('isAvailable');
  Future<bool> isEnabled() => _bool('isEnabled');

  Future<void> openAccessibilitySettings() async {
    try {
      await _methods.invokeMethod('openSettings');
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  /// [mode] is `guide` (highlight only) or `assist` (perform taps after explicit confirmation).
  Future<String?> startSkill(String skillId, {required String mode, required String lang}) async {
    assert(mode == 'guide' || mode == 'assist');
    try {
      await _methods.invokeMethod('startSkill', {'skillId': skillId, 'mode': mode, 'lang': lang});
      return null;
    } on PlatformException catch (e) {
      return e.code;
    } on MissingPluginException catch (_) {
      return 'unavailable';
    }
  }

  Future<void> stop() async {
    try {
      await _methods.invokeMethod('stop');
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  Future<bool> _bool(String method) async {
    try {
      return (await _methods.invokeMethod<bool>(method)) ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}
