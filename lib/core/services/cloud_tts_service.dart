import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:http/http.dart' as http;

import 'netlify_post_json.dart';
import 'tts_service.dart';

/// Cloud TTS through the shared `/.netlify/functions/tts` Google proxy (the
/// same backend the web app uses), falling back to the on-device
/// [TtsService] on any network/API failure. No user-supplied key involved.
class CloudTtsService {
  final TtsService _fallback;
  final AudioPlayer _player = AudioPlayer();
  final http.Client _client;
  Completer<void>? _pendingCompletion;

  // In-memory cache + in-flight dedup for Speechify fetches, keyed by the
  // params that actually affect the synthesized bytes (speed isn't one of
  // them -- Speechify ignores it server-side, see speakSpeechify's doc
  // comment). Mirrors web's AudioCache + TTS._fetch's `_pending` map
  // (src/main.js), which is what makes TTS.preload() actually useful there.
  // Native never had an equivalent cache before this, so speakSpeechify now
  // always goes through it instead of calling the network helper directly.
  final Map<String, Future<Uint8List>> _speechifyCache = {};

  String _speechifyCacheKey(String text, String langCode, String voiceGender) => '$langCode|$voiceGender|$text';

  Future<Uint8List> _fetchSpeechifyCached(String text, String voiceGender, String langCode) {
    final key = _speechifyCacheKey(text, langCode, voiceGender);
    final cached = _speechifyCache[key];
    if (cached != null) return cached;
    final future = _speakSpeechifyViaNetlify(text, voiceGender, langCode);
    _speechifyCache[key] = future;
    // Don't let a failed fetch poison the cache forever -- a later real
    // playback attempt for the same text should retry, not replay the error.
    unawaited(future.catchError((Object _) {
      if (identical(_speechifyCache[key], future)) _speechifyCache.remove(key);
      return Uint8List(0);
    }));
    return future;
  }

  /// Kicks off the Speechify fetch for [text] in the background so it's
  /// already in cache (or in flight) by the time [speakSpeechify] wants it --
  /// without this, playback only starts fetching once it's that segment's
  /// turn to play, adding a full network round-trip of silence before every
  /// segment. Mirrors web's TTS.preload() (src/main.js). Errors are swallowed
  /// here; a real playback attempt will surface and handle them normally.
  void preloadSpeechify(String text, {required String langCode, String voiceGender = 'female'}) {
    if (text.trim().isEmpty) return;
    unawaited(_fetchSpeechifyCached(text, voiceGender, langCode).catchError((Object _) => Uint8List(0)));
  }

  CloudTtsService({
    required TtsService fallback,
    http.Client? client,
  })  : _fallback = fallback,
        _client = client ?? http.Client();

  /// [language] defaults to English; pass 'pt-BR' to use the Portuguese
  /// voice pair (matches the web app's GOOGLE_TTS_VOICES in tts-shared.js).
  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceGender = 'female',
    String language = 'en-US',
  }) async {
    try {
      final bytes = await _speakGoogleViaNetlify(text, voiceGender, language);
      await _player.stop();
      await _playAndAwaitCompletion(bytes);
    } catch (e, st) {
      // Any network/API failure falls back to on-device speech rather than
      // leaving the user with silence, but still gets recorded so a spike
      // in Netlify/Google TTS failures shows up in Crashlytics.
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'CloudTtsService.speak failed', fatal: false));
      await _stopPlayerSilently();
      await _fallback.speak(text, rate: rate, voiceGender: voiceGender, language: language);
    }
  }

  // Voice names per locale, matching WEB_BASE's tts-shared.js GOOGLE_TTS_VOICES.
  // Adding a new course language's TTS voice is only adding an entry here.
  static const Map<String, ({String male, String female})> _voices = {
    'en-US': (male: 'en-US-Neural2-D', female: 'en-US-Neural2-F'),
    'pt-BR': (male: 'pt-BR-Neural2-B', female: 'pt-BR-Wavenet-A'),
    'es-US': (male: 'es-US-Neural2-B', female: 'es-US-Neural2-A'),
  };

  Future<Uint8List> _speakGoogleViaNetlify(String text, String voiceGender, String language) async {
    final isFemale = voiceGender == 'female';
    final pair = _voices[language] ?? _voices['en-US']!;
    final voiceName = isFemale ? pair.female : pair.male;
    final json = await postJson(
      _client,
      'tts',
      {
        'input': {'text': text},
        'voice': {
          'languageCode': language,
          'name': voiceName,
          'ssmlGender': isFemale ? 'FEMALE' : 'MALE',
        },
        'audioConfig': {'audioEncoding': 'MP3'},
      },
      errorLabel: 'Netlify TTS',
    );
    return base64Decode(json['audioContent'] as String);
  }

  /// AI Tutor voice call — always Speechify, independent of any Google
  /// toggle, mirroring web's `_route()` (TTSType.AI_TUTOR always ->
  /// 'speechify', src/main.js). [langCode] is the 2-letter course code
  /// ('en'/'es'/'pt'), not a locale — `tts-speechify.js` picks the voice_id
  /// itself from {lang, gender}, same contract as web's fetchSpeechifyTTS.
  Future<void> speakSpeechify(
    String text, {
    required String langCode,
    String voiceGender = 'female',
    String fallbackLanguage = 'en-US',
    // Extra client-side playback-rate multiplier layered on top of the
    // synthesized audio (Speechify itself ignores any speed param server-side
    // — see tts-speechify.js — so this is the only reliable slowdown knob).
    // 1.0 = no change; e.g. 0.7 = 30% slower. Used by the call screen to
    // slow down the target-language segments relative to the student's CEFR
    // level, mirroring web's TTS.speakWithRate.
    double playbackRate = 1.0,
  }) async {
    try {
      final bytes = await _fetchSpeechifyCached(text, voiceGender, langCode);
      await _player.stop();
      await _playAndAwaitCompletion(bytes, playbackRate: playbackRate);
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'CloudTtsService.speakSpeechify failed', fatal: false));
      await _stopPlayerSilently();
      await _fallback.speak(text, voiceGender: voiceGender, language: fallbackLanguage);
    }
  }

  Future<Uint8List> _speakSpeechifyViaNetlify(String text, String voiceGender, String langCode) async {
    final json = await postJson(
      _client,
      'tts-speechify',
      {
        'text': text,
        'lang': langCode,
        'gender': voiceGender,
      },
      errorLabel: 'Netlify Speechify TTS',
    );
    return base64Decode(json['audioContent'] as String);
  }

  /// `player.play()` only awaits playback *starting*, not finishing — a caller
  /// that speaks several segments back-to-back (the AI Tutor call screen's
  /// bilingual `{{...}}` split) would fire the next segment's audio before
  /// the previous one finished, cutting words off and audibly overlapping
  /// different languages. This waits for the real completion event instead,
  /// with a safety timeout in case a platform audio stack never fires it and
  /// an early-out if [stop] is called mid-playback (lifecycle pause/dispose).
  Future<void> _playAndAwaitCompletion(Uint8List bytes, {double playbackRate = 1.0}) async {
    final completer = Completer<void>();
    _pendingCompletion = completer;
    // `onPlayerComplete` is a separate event-channel stream from the
    // method-channel calls (play/stop) — its delivery isn't guaranteed to be
    // ordered against a just-`await`ed `stop()`. A stale event from the
    // *previous* segment's stop can land on this fresh subscription and
    // resolve it before this segment's audio has actually started, letting
    // the next segment start on top of it. TTS clips are never genuinely
    // this short, so anything inside the guard window is treated as stale.
    var playbackStarted = false;
    final guard = Stopwatch();
    final sub = _player.onPlayerComplete.listen((_) {
      if (!playbackStarted || guard.elapsedMilliseconds < 200) return;
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _player.play(BytesSource(bytes));
      // Always set explicitly (never conditionally on != 1.0): _player is one
      // shared AudioPlayer reused across every segment, so skipping the call
      // when this segment wants 1.0 would leave a *previous* segment's slower
      // rate stuck on the player instead of resetting it back to normal.
      await _player.setPlaybackRate(playbackRate);
      playbackStarted = true;
      guard.start();
      await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    } finally {
      await sub.cancel();
      if (identical(_pendingCompletion, completer)) _pendingCompletion = null;
    }
  }

  Future<void> stop() async {
    _pendingCompletion?.complete();
    await _player.stop();
    await _fallback.stop();
  }

  /// Used before falling back to on-device speech: if the cloud path threw
  /// *after* `_player.play()` had already started native playback (a plugin
  /// channel hiccup mid-`_playAndAwaitCompletion`, not just a network
  /// failure before any audio started), the catch block used to jump
  /// straight to `_fallback.speak()` while `_player`'s audio kept playing in
  /// the background — two different engines/languages audible at once. This
  /// guarantees the cloud player is silent first.
  Future<void> _stopPlayerSilently() async {
    try {
      await _player.stop();
    } catch (_) {
      // Already stopped/no active source — nothing to clean up.
    }
  }

  void dispose() {
    _player.dispose();
    _client.close();
  }
}
