import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Urdu read-aloud using the phone's own voice (free, offline if installed).
/// If no Urdu voice exists, [urduAvailable] is false and the UI should rely on
/// the on-screen text (always shown anyway).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool urduAvailable = false;
  bool enabled = true;

  Future<void> init() async {
    try {
      final ok = await _tts.isLanguageAvailable('ur-PK');
      urduAvailable = ok == true || ok == 1;
      await _tts.setLanguage(urduAvailable ? 'ur-PK' : 'en-US');
      await _tts.setSpeechRate(0.42); // slower = easier for older listeners
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (e) {
      debugPrint('TTS init failed: $e');
    }
  }

  /// Speaks Urdu text; if Urdu voice is missing, speaks the English fallback.
  Future<void> say(String ur, {String? en}) async {
    if (!enabled) return;
    try {
      await _tts.stop();
      if (urduAvailable) {
        await _tts.speak(ur);
      } else if (en != null && en.isNotEmpty) {
        await _tts.speak(en);
      }
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> stop() => _tts.stop();
}
