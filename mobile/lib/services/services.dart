import 'api_client.dart';
import 'auth_service.dart';
import 'navigation_service.dart';
import 'scam_input_service.dart';
import 'tier2_bridge.dart';
import 'voice_service.dart';

/// Bundle of long-lived services, provided once at the top of the widget tree.
class AppServices {
  AppServices({
    required this.api,
    required this.auth,
    required this.nav,
    required this.tier2,
    required this.voice,
    required this.scamInput,
  });

  final ApiClient api;
  final AuthService auth;
  final NavigationService nav;
  final Tier2Bridge tier2;
  final VoiceService voice;
  final ScamInputService scamInput;
}
