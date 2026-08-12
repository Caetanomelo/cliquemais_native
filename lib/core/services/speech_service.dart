import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Wraps speech_to_text. `partialResults` maps to Drive Mode's
/// `interimResults=false` (only [onFinalResult] fires) vs VPC's
/// `interimResults=true` (both [onPartialResult] and [onFinalResult] fire).
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool get isListening => _speech.isListening;

  Future<bool> init() async {
    try {
      _available = await _speech.initialize();
    } catch (e, st) {
      _available = false;
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'SpeechService.init failed', fatal: false));
    }
    return _available;
  }

  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required bool partialResults,
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 3),
    String localeId = 'en_US',
  }) async {
    if (!_available) {
      final ok = await init();
      if (!ok) return;
    }
    try {
      await _speech.listen(
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
        listenOptions: stt.SpeechListenOptions(
          partialResults: partialResults,
          cancelOnError: true,
          listenFor: listenFor,
          pauseFor: pauseFor,
          localeId: localeId,
        ),
      );
    } catch (e, st) {
      // Device has no usable speech recognizer (or it dropped mid-session) —
      // fail silently rather than crash; callers already handle empty
      // results. Still recorded as a non-fatal to spot devices/OEMs where
      // this fails often.
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'SpeechService.listen failed', fatal: false));
    }
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() => _speech.cancel();
}
