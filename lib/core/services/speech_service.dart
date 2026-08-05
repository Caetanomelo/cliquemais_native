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
    } catch (_) {
      _available = false;
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
    } catch (_) {
      // Device has no usable speech recognizer (or it dropped mid-session) —
      // fail silently rather than crash; callers already handle empty results.
    }
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() => _speech.cancel();
}
