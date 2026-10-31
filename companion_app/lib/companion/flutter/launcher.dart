import 'package:flutter/foundation.dart';
import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';

/// PRD F10 Tier 1: opens the real app at the last step. Never taps for the user.
class CompanionLauncher {
  Future<bool> run(LaunchAction a) async {
    if (a.kind == LaunchKind.settings) return _openSettings(a.settingsType);
    final Uri? uri = switch (a.kind) {
      LaunchKind.dial => Uri.parse('tel:+${a.phone}'),
      LaunchKind.whatsappChat => Uri.parse('https://wa.me/${a.phone}'),
      LaunchKind.sms => Uri.parse('sms:+${a.phone}'),
      LaunchKind.settings => null,
      LaunchKind.none => null,
    };
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Launch failed for $uri: $e');
      return false;
    }
  }

  Future<bool> _openSettings(String? type) async {
    final t = switch (type) {
      'wifi' => AppSettingsType.wifi,
      'hotspot' => AppSettingsType.hotspot,
      'sound' => AppSettingsType.sound,
      'display' => AppSettingsType.display,
      'bluetooth' => AppSettingsType.bluetooth,
      _ => AppSettingsType.settings,
    };
    try {
      await AppSettings.openAppSettings(type: t);
      return true;
    } catch (e) {
      debugPrint('Open settings failed ($type): $e');
      try {
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}
