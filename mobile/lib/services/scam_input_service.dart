import 'dart:async';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Inputs for the scam check (F6): clipboard paste, Android share sheet, screenshot OCR (on device).
/// Note: ML Kit on-device OCR reads Latin script (English / Roman Urdu). Urdu-script messages should be
/// pasted or shared as text - the UI says so.
class ScamInputService {
  final _picker = ImagePicker();
  StreamSubscription? _shareSub;

  Future<String?> paste() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  Future<String?> pickScreenshotText() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return result.text; // the image never leaves the phone
    } finally {
      await recognizer.close();
    }
  }

  /// Text shared into Companion from another app ("Share" -> Companion).
  void listenForShares(void Function(String text) onText) {
    void handle(List<SharedMediaFile> files) {
      for (final f in files) {
        if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
          onText(f.path);
          break;
        }
      }
    }

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      handle(files);
      ReceiveSharingIntent.instance.reset();
    });
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(handle, onError: (_) {});
  }

  void dispose() => _shareSub?.cancel();
}
