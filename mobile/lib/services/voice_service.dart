import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Push-to-talk speech-to-text and text-to-speech (F7).
/// Uses the free on-device Android recognizer / TTS engine. Urdu first (ur-PK), English fallback.
/// Text is ALWAYS shown alongside audio (Urdu voices vary by device; the Urdu voice pack may need installing).
class VoiceService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttReady = false;
  List<String> _locales = [];

  Future<bool> init() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize();
      if (_sttReady) _locales = (await _stt.locales()).map((l) => l.localeId).toList();
    } catch (_) {
      _sttReady = false;
    }
    await _tts.setSpeechRate(0.42); // slower, calmer speech
    return _sttReady;
  }

  /// Picks ur_PK when the device supports it, otherwise English.
  String sttLocale(String lang) {
    if (lang == 'ur') {
      for (final id in ['ur_PK', 'ur-PK', 'ur_IN', 'ur']) {
        if (_locales.contains(id)) return id;
      }
      final any = _locales.where((l) => l.startsWith('ur')).toList();
      if (any.isNotEmpty) return any.first;
    }
    for (final id in ['en_US', 'en-US', 'en_GB', 'en_IN']) {
      if (_locales.contains(id)) return id;
    }
    return _locales.isNotEmpty ? _locales.first : 'en_US';
  }

  /// Listens once. [onPartial] gets live text so the UI can show it. Completes with the final transcript.
  Future<String> listen(String lang, {void Function(String)? onPartial}) async {
    if (!await init()) return '';
    final done = Completer<String>();
    var last = '';
    await _stt.listen(
      localeId: sttLocale(lang),
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
      onResult: (r) {
        last = r.recognizedWords;
        onPartial?.call(last);
        if (r.finalResult && !done.isCompleted) done.complete(last);
      },
    );
    return done.future.timeout(const Duration(seconds: 16), onTimeout: () {
      _stt.stop();
      return last;
    });
  }

  Future<void> stopListening() => _stt.stop();

  Future<void> speak(String text, String lang) async {
    if (text.isEmpty) return;
    await _tts.stop();
    var language = lang == 'ur' ? 'ur-PK' : 'en-US';
    try {
      final ok = await _tts.isLanguageAvailable(language);
      if (ok != true && lang == 'ur') {
        final alt = await _tts.isLanguageAvailable('ur-IN');
        language = alt == true ? 'ur-IN' : 'en-US';
      }
      await _tts.setLanguage(language);
      await _tts.speak(text);
    } catch (_) {
      // TTS missing: text is already on screen.
    }
  }

  Future<void> stopSpeaking() => _tts.stop();
}
