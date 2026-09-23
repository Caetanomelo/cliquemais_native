import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/services/ai_tutor_service.dart';
import '../../core/services/netlify_post_json.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/course_language.dart';
import '../../data/repositories/ai_content_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import 'call_turn_assessor.dart';

enum _CallState { idle, listening, thinking, speaking }

class _CallSegment {
  final String text;
  final String langCode;
  const _CallSegment(this.text, this.langCode);
}

/// Pull-queue TTS player for the streaming AI-reply path (mirrors web's
/// `_callStreamTTSQueue`, src/main.js): [pushSegment] enqueues a segment and
/// starts playback immediately if nothing else is playing, so segment 1 can
/// speak while segment 3 is still arriving over the network; [finish] marks
/// that no more segments are coming and its returned future resolves once
/// the queue drains. Kept separate from `_speak`'s array-based loop, which
/// stays on the static welcome-message call site -- that text is fully
/// known upfront, so there's no streaming benefit there.
class _StreamTtsQueue {
  final Future<void> Function(_CallSegment seg) _play;
  final void Function(_CallSegment seg)? _prefetch;
  _StreamTtsQueue(this._play, [this._prefetch]);

  final List<_CallSegment> _pending = [];
  bool _draining = false;
  bool _finished = false;
  final Completer<void> _doneCompleter = Completer<void>();

  void pushSegment(_CallSegment seg) {
    if (seg.text.trim().isEmpty) return;
    // Kick off this segment's audio fetch the moment it's queued, not when
    // its turn to play arrives -- mirrors web's _callStreamTTSQueue.pushSegment
    // (src/main.js). Without this, each segment boundary added a full TTS
    // round-trip of silence, sounding like the tutor pausing word by word.
    _prefetch?.call(seg);
    _pending.add(seg);
    if (!_draining) unawaited(_drainLoop());
  }

  Future<void> _drainLoop() async {
    _draining = true;
    while (_pending.isNotEmpty) {
      final seg = _pending.removeAt(0);
      await _play(seg);
    }
    _draining = false;
    if (_finished && !_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  Future<void> finish() {
    _finished = true;
    if (!_draining && _pending.isEmpty && !_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    return _doneCompleter.future;
  }
}

/// Live voice call with the AI Tutor — continuous listening (no push-to-talk):
/// the mic stays armed and a lightweight VAD (voice activity detection) both
/// starts a turn when the student begins speaking and ends it after a
/// sustained silence, mirroring the web app's `AiTutor.openCall()` flow. The
/// mic button is a mute toggle, not a record trigger. No barge-in in this
/// phase — VAD only starts turns, it never interrupts the tutor's own
/// playback (the recorder used for VAD sampling is simply not running while
/// `thinking`/`speaking`).
///
/// Deliberate divergence from the web app: `speech_to_text` + a raw-audio
/// recorder can't run at once on Android (both claim the mic's exclusive
/// `AudioRecord` session), so this screen uses only `record` for capture and
/// has no live captions — the transcript only appears after the turn ends.
/// That also shapes the VAD itself: the web app reads amplitude straight off
/// a live `MediaStream` via `AnalyserNode` without recording anything, but
/// `record`'s `onAmplitudeChanged` only emits while a recording is actually
/// active (confirmed against record 6.2.1's source — `isRecording()` gates
/// every tick). So instead, ONE recording runs continuously for the whole
/// idle-then-turn span whenever the call is armed (idle, unmuted): the
/// instant amplitude crosses the calibrated threshold, [_beginTurnFromVad]
/// only flips state (no recorder stop/start), tracking the elapsed-ms
/// timestamp of that crossing. Only when the turn later ends does the
/// recorder actually stop, and [_trimWavLeadIn] cuts the idle lead-in off
/// the front of the resulting WAV (keeping a small pre-roll before the
/// detected onset) before the bytes are sent to Azure. This replaced an
/// earlier stop/discard/restart-at-onset design that lost the ~100-150ms of
/// audio right at the moment the student started speaking — enough to
/// regularly clip the first word of a turn.
///
/// Since the call is mostly in the student's native language (the tutor
/// corrects the target language only when attempted), a single WAV is
/// assessed first against the target-language locale (`primaryLang`,
/// resolved from `courseLanguage`); if that pass isn't confidently the
/// target language, the same bytes are re-sent to Azure as a plain
/// transcription in the student's native locale (`nativeLang`, resolved
/// from `nativeLanguage`) so ordinary native-language turns still work —
/// see [assessCallTurn]. `SpeechService` is untouched and keeps being used
/// everywhere else (Vocab Lab, Drive Mode).
class AiTutorCallScreen extends StatefulWidget {
  const AiTutorCallScreen({super.key});

  @override
  State<AiTutorCallScreen> createState() => _AiTutorCallScreenState();
}

class _AiTutorCallScreenState extends State<AiTutorCallScreen> with WidgetsBindingObserver {
  // VAD tuning — mirrors the web app's AnalyserNode-based constants
  // (VAD_MIN_THRESHOLD/VAD_NOISE_MARGIN/VAD_SILENCE_MS/VAD_CALIBRATION_MS in
  // src/main.js), adapted from linear RMS to `record`'s dBFS amplitude scale.
  static const double _kVadMarginDb = 12.0;
  static const double _kVadMinThresholdDb = -45.0;
  static const int _kVadSilenceMs = 900;
  static const int _kVadCalibrationMs = 400;
  // How much audio to keep before the detected speech-onset timestamp when
  // trimming the continuous recording's idle lead-in -- covers the up-to-
  // ~100ms amplitude-polling granularity (onAmplitudeChanged tick every
  // 100ms) plus margin, without keeping so much silence it risks confusing
  // Azure's recognizer.
  static const int _kVadPreRollMs = 300;

  // Item 3 do pedido: quando o tutor fala no idioma-alvo (trechos {{...}}),
  // a fala deve ser 0-20% mais lenta conforme o nível do aluno -- quanto
  // mais iniciante, mais devagar. Fração de redução aplicada como
  // multiplicador de playbackRate (1 - redução) só nesses trechos; trechos
  // no idioma nativo tocam em velocidade normal.
  static const Map<String, double> _kCallTargetSlowdownByLevel = {
    'A1': 0.20,
    'A2': 0.15,
    'B1': 0.10,
    'B2': 0.05,
    'C1': 0.00,
    'C2': 0.00,
  };

  late final AppStateProvider _app;
  final AudioRecorder _recorder = AudioRecorder();
  final http.Client _httpClient = http.Client();
  final List<AiChatMessage> _history = [];
  _CallState _state = _CallState.idle;
  String _transcript = '';
  String? _errorText;
  // Picked fresh every time this screen opens (every call is its own
  // AiTutorCallScreen instance), independently from whatever persona is
  // currently active in AiTutorScreen's chat.
  late final AiPersona _persona;

  bool _muted = false;
  bool _turnActive = false;
  bool _calibrating = false;
  double _vadCalFloorDb = -100.0;
  double _vadThresholdDb = _kVadMinThresholdDb;
  DateTime? _vadSilenceSince;
  Stopwatch? _calibrationStopwatch;
  // Tracks elapsed time since the current continuous recording started
  // (armed in _armVad), so _beginTurnFromVad can stamp the speech-onset
  // moment without stopping/restarting the recorder -- see class doc comment.
  Stopwatch? _recordingStopwatch;
  int? _turnOnsetElapsedMs;
  StreamSubscription<Amplitude>? _ampSub;
  String? _monitorPath;
  int _fillerToken = 0;
  // Última frase no idioma-alvo que o tutor pediu explicitamente pro aluno
  // repetir (marcador {{...}} final da resposta, ver migration 069) -- só
  // enquanto setada o próximo turno roda com scoring de pronúncia real
  // (referenceText = essa frase); caso contrário o pass do idioma-alvo é só
  // transcrição, sem custo/score de pronúncia sobre conversa livre. Consumida
  // (voltando a null) assim que usada no turno seguinte, com sucesso ou não.
  String? _expectedPhrase;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _persona = _app.aiContent.pickPersona();
    WidgetsBinding.instance.addObserver(this);
    // Item 1 do pedido: mantém a tela acesa durante toda a chamada, senão o
    // sistema entra em modo de descanso no meio de uma conversa por voz.
    unawaited(WakelockPlus.enable());
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWelcome());
  }

  // Continuous listening leaves a raw AudioRecord session open (monitor or
  // real turn recording) if the user backgrounds the app — without this, the
  // recorder keeps the mic reserved and TTS keeps playing while the app
  // isn't in front of the user.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(WakelockPlus.enable());
      if (!_muted && _state == _CallState.idle) unawaited(_armVad());
      return;
    }
    _ampSub?.cancel();
    _ampSub = null;
    if (_turnActive) {
      unawaited(_cancelRecording());
    } else {
      unawaited(_stopMonitorIfRecording());
    }
    unawaited(_app.cloudTts.stop());
    _app.tts.stop();
  }

  Future<void> _speakWelcome() async {
    final welcome = _persona.welcome.isNotEmpty ? _persona.welcome : _app.aiContent.welcomeMessageForKey('call');
    if (welcome.isNotEmpty) await _speak(welcome);
    if (!mounted || _muted) return;
    await _armVad();
  }

  // ---- VAD (continuous listening) ----------------------------------------

  Future<void> _armVad() async {
    if (!mounted || _muted || _state != _CallState.idle || _turnActive) return;
    _ampSub?.cancel();
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _errorText = AppLocalizations.of(context)!.aiTutorCallAudioError);
      return;
    }
    _monitorPath = '${Directory.systemTemp.path}/call_monitor_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: _monitorPath!,
      );
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._armVad: recorder.start failed', fatal: false));
      return;
    }
    _calibrating = true;
    _vadCalFloorDb = -100.0;
    _calibrationStopwatch = Stopwatch()..start();
    _recordingStopwatch = Stopwatch()..start();
    _turnOnsetElapsedMs = null;
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(_onVadAmplitude);
  }

  Future<void> _stopMonitorIfRecording() async {
    try {
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        if (path != null) unawaited(_safeDelete(path));
      }
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._stopMonitorIfRecording failed', fatal: false));
    }
  }

  void _onVadAmplitude(Amplitude a) {
    if (_calibrating) {
      _vadCalFloorDb = max(_vadCalFloorDb, a.current);
      if ((_calibrationStopwatch?.elapsedMilliseconds ?? 0) >= _kVadCalibrationMs) {
        _calibrating = false;
        _vadThresholdDb = max(_vadCalFloorDb + _kVadMarginDb, _kVadMinThresholdDb);
      }
      return;
    }

    if (_turnActive) {
      if (a.current < _vadThresholdDb) {
        _vadSilenceSince ??= DateTime.now();
        if (DateTime.now().difference(_vadSilenceSince!).inMilliseconds >= _kVadSilenceMs) {
          _vadSilenceSince = null;
          unawaited(_stopRecordingAndSend());
        }
      } else {
        _vadSilenceSince = null;
      }
      return;
    }

    if (_muted || _state != _CallState.idle) return;
    if (a.current >= _vadThresholdDb) {
      _beginTurnFromVad();
    }
  }

  // No recorder I/O here on purpose -- the same continuous recording that's
  // been running since _armVad just keeps going, so there's no stop/restart
  // gap to lose the first word of the turn to. This only flips state and
  // stamps the onset timestamp; _stopRecordingAndSend trims the idle lead-in
  // back out of the WAV once the turn actually ends.
  void _beginTurnFromVad() {
    if (_turnActive || _state != _CallState.idle || _muted) return;
    _turnActive = true;
    _vadSilenceSince = null;
    _turnOnsetElapsedMs = _recordingStopwatch?.elapsedMilliseconds ?? 0;
    if (!mounted) return;
    setState(() {
      _state = _CallState.listening;
      _transcript = '';
      _errorText = null;
    });
  }

  // ---- Mute toggle --------------------------------------------------------

  Future<void> _toggleMute() async {
    final wasMuted = _muted;
    setState(() => _muted = !wasMuted);
    if (!wasMuted) {
      // Just muted.
      _ampSub?.cancel();
      _ampSub = null;
      _calibrating = false;
      if (_turnActive) {
        _turnActive = false;
        _vadSilenceSince = null;
        await _cancelRecording();
      } else {
        await _stopMonitorIfRecording();
      }
    } else {
      // Just unmuted.
      await _armVad();
    }
  }

  // ---- Turn lifecycle (mostly unchanged from the hold-to-talk version) ---

  Future<void> _cancelRecording() async {
    try {
      final path = await _recorder.stop();
      if (path != null) await _safeDelete(path);
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._cancelRecording failed', fatal: false));
    }
    if (mounted) setState(() => _state = _CallState.idle);
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_turnActive) return;
    _turnActive = false;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._stopRecordingAndSend: recorder.stop failed', fatal: false));
    }
    setState(() => _state = _CallState.thinking);

    if (path == null) {
      unawaited(_goIdleAndRearm());
      return;
    }
    try {
      final rawBytes = await File(path).readAsBytes();
      unawaited(_safeDelete(path));
      final onsetMs = _turnOnsetElapsedMs;
      _turnOnsetElapsedMs = null;
      final skipMs = onsetMs != null ? max(0, onsetMs - _kVadPreRollMs) : 0;
      final bytes = _trimWavLeadIn(rawBytes, skipMs);
      // ~0.25s of 16kHz/16-bit/mono PCM — filters out VAD false-triggers
      // (a cough, a door) without spending an Azure call on them.
      if (bytes.length < 8000) {
        unawaited(_goIdleAndRearm());
        return;
      }
      await _assessAndSend(bytes);
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._stopRecordingAndSend failed', fatal: false));
      unawaited(_goIdleAndRearm());
    }
  }

  Future<void> _safeDelete(String path) async {
    try {
      await File(path).delete();
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._safeDelete failed', fatal: false));
    }
  }

  /// Drops `skipMs` of audio off the front of a WAV recording's `data`
  /// chunk, patching the RIFF/data chunk sizes so the result stays a valid
  /// WAV -- used to cut the idle-listening lead-in now that the recorder
  /// runs continuously through the VAD onset instead of restarting there
  /// (see class doc comment). Walks chunks generically (not a fixed 44-byte
  /// header) since `record`'s encoder may emit extra chunks before `data`.
  /// Returns the input unchanged if `skipMs <= 0` or the WAV can't be
  /// parsed, rather than risk sending a corrupt file to Azure.
  static Uint8List _trimWavLeadIn(Uint8List wavBytes, int skipMs) {
    if (skipMs <= 0 || wavBytes.length < 44) return wavBytes;
    if (wavBytes[0] != 0x52 || wavBytes[1] != 0x49 || wavBytes[2] != 0x46 || wavBytes[3] != 0x46) {
      return wavBytes; // not "RIFF" -- unexpected format, leave untouched
    }
    final byteData = ByteData.sublistView(wavBytes);
    var offset = 12; // past "RIFF" + size(4) + "WAVE"
    int? sampleRate;
    int? numChannels;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;
    while (offset + 8 <= wavBytes.length) {
      final id = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final size = byteData.getUint32(offset + 4, Endian.little);
      final bodyOffset = offset + 8;
      if (id == 'fmt ' && bodyOffset + 16 <= wavBytes.length) {
        numChannels = byteData.getUint16(bodyOffset + 2, Endian.little);
        sampleRate = byteData.getUint32(bodyOffset + 4, Endian.little);
        bitsPerSample = byteData.getUint16(bodyOffset + 14, Endian.little);
      } else if (id == 'data') {
        dataOffset = bodyOffset;
        dataSize = min(size, wavBytes.length - bodyOffset);
        break;
      }
      offset = bodyOffset + size + (size.isOdd ? 1 : 0); // chunks are word-aligned
    }
    if (sampleRate == null || numChannels == null || bitsPerSample == null || dataOffset == null || dataSize == null) {
      return wavBytes; // couldn't parse -- leave untouched rather than risk corrupting it
    }

    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    if (blockAlign <= 0) return wavBytes;
    var skipBytes = ((skipMs / 1000) * sampleRate * blockAlign).round();
    skipBytes -= skipBytes % blockAlign; // keep sample framing intact
    if (skipBytes <= 0) return wavBytes;
    if (skipBytes >= dataSize) return wavBytes; // safety: never drop the whole turn

    final trimmedData = wavBytes.sublist(dataOffset + skipBytes, dataOffset + dataSize);
    final out = Uint8List(dataOffset + trimmedData.length);
    out.setRange(0, dataOffset, wavBytes.sublist(0, dataOffset));
    out.setRange(dataOffset, out.length, trimmedData);
    final outView = ByteData.sublistView(out);
    outView.setUint32(4, out.length - 8, Endian.little); // RIFF chunk size
    outView.setUint32(dataOffset - 4, trimmedData.length, Endian.little); // "data" subchunk size
    return out;
  }

  Future<void> _assessAndSend(List<int> wavBytes) async {
    // Filler DESATIVADO temporariamente (teste de diagnóstico -- mirrors web
    // commit 8e75689, WEB_BASE/src/main.js _callEndTurn). Era a única fala
    // tocada em TODO turno logo após capturar o áudio do aluno; suspeita
    // (confirmada no web) de estar contribuindo pro efeito "palavra por
    // palavra" relatado -- o _playFiller() é cortado no meio assim que a
    // resposta real chega. Ver comentário original em _playFiller() acima.
    // TODO: remover de vez (ver pendência espelhada do lado web).
    // unawaited(_playFiller());

    final expectedPhrase = _expectedPhrase;
    final result = await assessCallTurn(
      _app.pronunciation,
      wavBytes,
      primaryLang: resolveLocale(_app.courseLanguage),
      nativeLang: resolveLocale(_app.nativeLanguage),
      assessPrimaryPronunciation: expectedPhrase != null,
      referenceText: expectedPhrase,
      onError: (e, st, {required reason}) =>
          unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._assessAndSend: $reason', fatal: false)),
    );
    // Consumida neste turno, com sucesso ou não -- quem decide pedir de novo
    // é o próprio tutor via prompt (migration 069).
    _expectedPhrase = null;

    if (result.transcript.trim().isEmpty) {
      unawaited(_app.cloudTts.stop());
      if (mounted) {
        setState(() {
          _errorText = result.failed ? AppLocalizations.of(context)!.aiTutorCallAudioError : null;
        });
      }
      unawaited(_goIdleAndRearm());
      return;
    }
    if (mounted) setState(() { _transcript = result.transcript; _errorText = null; });
    await _sendToAI(result.transcript, result.feedback);
  }

  Future<void> _sendToAI(String userText, String feedback) async {
    setState(() => _state = _CallState.thinking);
    try {
      final priorHistory = List<AiChatMessage>.from(_history);
      _history.add(AiChatMessage(role: 'user', content: userText));
      final outgoing = feedback.isEmpty ? userText : '$userText\n\n$feedback';
      final basePrompt = _app.aiContent.systemPromptForKey('call');
      final systemPrompt = _persona.prompt.isEmpty ? basePrompt : '${_persona.prompt}\n\n$basePrompt';

      if (mounted) setState(() => _state = _CallState.speaking);

      final nativeLang = _app.nativeLanguage;
      final targetLang = _app.courseLanguage;
      final reduction = _kCallTargetSlowdownByLevel[_app.journeyProgress.cefr] ?? 0.30;
      final targetExtraRate = 1.0 - reduction;

      final ttsQueue = _StreamTtsQueue(
        (seg) => _app.cloudTts.speakSpeechify(
          seg.text,
          langCode: seg.langCode,
          voiceGender: _app.voiceGender,
          fallbackLanguage: resolveLocale(seg.langCode),
          playbackRate: seg.langCode == targetLang ? targetExtraRate : 1.0,
        ),
        (seg) => _app.cloudTts.preloadSpeechify(seg.text, langCode: seg.langCode, voiceGender: _app.voiceGender),
      );

      // Incremental {{...}}-boundary-safe segment extractor -- flushes plain
      // text as it arrives so TTS can start on segment 1 while the network
      // stream is still delivering the rest. Mirrors web's `onDelta` in
      // `_callSendToAI` (src/main.js) line for line. A trailing lone '{' is
      // always held back (it might be the start of '{{'); once '{{' opens,
      // text is held until the matching '}}' closes it. `_parseBilingualSegments`
      // (the full-text-safe, non-incremental version) is reused as a
      // fallback for whatever is left over once the stream ends, and for
      // the final `_expectedPhrase` computation below.
      var buf = '';
      var inMarker = false;
      String sanitize(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('**', '');

      void onDelta(String delta) {
        buf += delta;
        while (true) {
          if (!inMarker) {
            final idx = buf.indexOf('{{');
            if (idx == -1) {
              // Hold everything back until a marker opens or the stream
              // ends, instead of flushing at each sentence boundary --
              // splitting native-language text into one TTS call per
              // sentence made the reply sound disjointed/robotic (each
              // clip synthesized independently, no shared prosody). This
              // matches the pre-streaming behaviour of speaking a whole
              // passage in one render.
              break;
            }
            if (idx > 0) {
              ttsQueue.pushSegment(_CallSegment(sanitize(buf.substring(0, idx)), nativeLang));
            }
            buf = buf.substring(idx + 2);
            inMarker = true;
          } else {
            final idx2 = buf.indexOf('}}');
            if (idx2 == -1) break;
            final segText = buf.substring(0, idx2);
            if (segText.trim().isNotEmpty) {
              ttsQueue.pushSegment(_CallSegment(sanitize(segText), targetLang));
            }
            buf = buf.substring(idx2 + 2);
            inMarker = false;
          }
        }
      }

      final reply = await _app.aiTutor.sendStream(
        systemPrompt: systemPrompt,
        history: priorHistory,
        userMessage: outgoing,
        onDelta: onDelta,
      );
      _history.add(AiChatMessage(role: 'assistant', content: reply));
      if (!mounted) return;

      if (reply.isEmpty) {
        ttsQueue.pushSegment(_CallSegment(AppLocalizations.of(context)!.aiTutorCallRepeatFallback, nativeLang));
      } else if (inMarker) {
        // Marker never closed (stream ended mid-{{...}}, e.g. cut off by
        // max_tokens or a malformed reply) -- we know this buffered text
        // was meant to be target-language, so speak it as such instead of
        // falling through `_parseBilingualSegments` (which requires a
        // closing `}}` to recognize a marker at all) and mislabeling real
        // target-language content as native language -- that produced the
        // "mixed pt/es" sound, on top of leaking literal `{{` characters
        // into the TTS text.
        final segText = buf.trim();
        if (segText.isNotEmpty) {
          ttsQueue.pushSegment(_CallSegment(sanitize(segText), targetLang));
        }
      } else {
        final leftoverRaw = buf;
        if (leftoverRaw.trim().isNotEmpty) {
          for (final seg in _parseBilingualSegments(sanitize(leftoverRaw))) {
            ttsQueue.pushSegment(seg);
          }
        }
      }

      // `_expectedPhrase` (migration 069) is still computed from the full
      // accumulated reply text via the unmodified full-text parser, exactly
      // as before -- only the TTS flushing above is incremental.
      final clean = (reply.isNotEmpty ? reply : AppLocalizations.of(context)!.aiTutorCallRepeatFallback)
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('**', '');
      final fullSegs = _parseBilingualSegments(clean);
      final targetSegs = fullSegs.where((s) => s.langCode == targetLang).toList();
      _expectedPhrase = targetSegs.isNotEmpty ? targetSegs.last.text.trim() : null;

      await ttsQueue.finish();
      if (!mounted) return;
      setState(() => _state = _CallState.idle);
      if (_muted) return;
      await _armVad();
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._sendToAI failed', fatal: false));
      unawaited(_app.cloudTts.stop());
      if (mounted) {
        setState(() {
          _errorText = AppLocalizations.of(context)!.aiTutorCallReplyError;
        });
      }
      unawaited(_goIdleAndRearm());
    }
  }

  Future<void> _goIdleAndRearm() async {
    if (mounted) setState(() => _state = _CallState.idle);
    if (!mounted || _muted) return;
    await _armVad();
  }

  // ---- Filler audio (fire-and-forget, cut off automatically once the real
  // reply's playback calls CloudTtsService's `_player.stop()`) -------------
  //
  // Item 2 do pedido: nenhuma frase fixa em código/banco -- uma única frase
  // curta é gerada em tempo real (Claude Haiku via a Netlify function
  // `ai-filler`, mesma usada pelo web) no idioma nativo do aluno, a cada
  // turno. `_fillerToken` garante que uma frase de um turno anterior nunca
  // toca por cima do turno atual.

  Future<String?> _fetchFillerPhrase(String nativeLang) async {
    try {
      final json = await postJson(
        _httpClient,
        'ai-filler',
        {'nativeLanguage': nativeLang},
        errorLabel: 'Netlify AI filler',
      );
      final phrase = (json['phrase'] as String?)?.trim();
      return (phrase != null && phrase.isNotEmpty) ? phrase : null;
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._fetchFillerPhrase failed', fatal: false));
      return null;
    }
  }

  // Call site commented out in _assessAndSend (diagnostic test, see comment
  // there); kept intact to make reverting easy.
  // ignore: unused_element
  Future<void> _playFiller() async {
    final token = ++_fillerToken;
    if (!mounted) return;
    final nativeLang = _app.nativeLanguage;
    final phrase = await _fetchFillerPhrase(nativeLang);
    if (phrase == null || token != _fillerToken || !mounted) return;
    try {
      await _app.cloudTts.speakSpeechify(
        phrase,
        langCode: nativeLang,
        voiceGender: _app.voiceGender,
        fallbackLanguage: resolveLocale(nativeLang),
      );
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._playFiller: speak failed', fatal: false));
    }
  }

  // Divide a resposta do Tutor em trechos por idioma usando o marcador
  // {{...}} que os system prompts de 'call' (migration 060, WEB_BASE)
  // inserem ao redor de palavras/frases no idioma-alvo -- o resto do texto
  // fica no idioma nativo do aluno. Mesmo marcador que o web app usa, ja
  // que ambos consomem o mesmo system_prompt de ai_tutor_modes.
  List<_CallSegment> _parseBilingualSegments(String text) {
    final nativeLang = _app.nativeLanguage;
    final targetLang = _app.courseLanguage;
    final segments = <_CallSegment>[];
    final re = RegExp(r'\{\{([^{}]*)\}\}');
    var lastIndex = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > lastIndex) {
        segments.add(_CallSegment(text.substring(lastIndex, m.start), nativeLang));
      }
      final inner = m.group(1) ?? '';
      if (inner.isNotEmpty) {
        segments.add(_CallSegment(inner, targetLang));
      }
      lastIndex = m.end;
    }
    if (lastIndex < text.length) {
      segments.add(_CallSegment(text.substring(lastIndex), nativeLang));
    }
    return segments.where((s) => s.text.trim().isNotEmpty).toList();
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() => _state = _CallState.speaking);
    final clean = text.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('**', '');
    // Item 3 do pedido: trechos no idioma-alvo tocam 20-40% mais devagar
    // conforme o nível do aluno (quanto mais iniciante, mais devagar);
    // trechos no idioma nativo tocam em velocidade normal.
    final reduction = _kCallTargetSlowdownByLevel[_app.journeyProgress.cefr] ?? 0.30;
    final targetExtraRate = 1.0 - reduction;
    final segments = _parseBilingualSegments(clean);
    // Texto todo já é conhecido de antemão aqui (mensagem de boas-vindas
    // fixa), então já dispara o fetch de todos os segmentos em paralelo em
    // vez de deixar o loop abaixo buscar um de cada vez -- mesma lógica do
    // prefetch em _StreamTtsQueue.pushSegment, só que sem streaming. Mirrors
    // web's _callSpeak (src/main.js).
    for (final seg in segments) {
      _app.cloudTts.preloadSpeechify(seg.text, langCode: seg.langCode, voiceGender: _app.voiceGender);
    }
    // Último trecho no idioma-alvo desta resposta vira a frase que o tutor
    // pediu pro aluno repetir (ver migration 069); null se não pediu nenhuma.
    final targetSegs = segments.where((s) => s.langCode == _app.courseLanguage).toList();
    _expectedPhrase = targetSegs.isNotEmpty ? targetSegs.last.text.trim() : null;
    for (final seg in segments) {
      if (!mounted) return;
      // AI Tutor sempre usa Speechify (paridade com web's _route()), com
      // fallback pro TTS on-device do proprio CloudTtsService.speakSpeechify
      // se a Netlify function falhar/sem rede.
      await _app.cloudTts.speakSpeechify(
        seg.text,
        langCode: seg.langCode,
        voiceGender: _app.voiceGender,
        fallbackLanguage: resolveLocale(seg.langCode),
        playbackRate: seg.langCode == _app.courseLanguage ? targetExtraRate : 1.0,
      );
    }
    if (mounted) setState(() => _state = _CallState.idle);
  }

  String get _statusText {
    final l10n = AppLocalizations.of(context)!;
    if (_muted) return l10n.aiTutorCallStatusMuted;
    switch (_state) {
      case _CallState.idle:
        return l10n.aiTutorCallStatusIdle;
      case _CallState.listening:
        return l10n.aiTutorCallStatusListening;
      case _CallState.thinking:
        return l10n.aiTutorCallStatusThinking;
      case _CallState.speaking:
        return l10n.aiTutorCallStatusSpeaking;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ampSub?.cancel();
    unawaited(WakelockPlus.disable());
    _httpClient.close();
    // stop() must finish before dispose() runs — firing both unawaited let
    // dispose() tear down the plugin's native session while stop() was
    // still flushing the in-progress recording, which could throw inside
    // stop() (using an already-disposed channel) or leave the Android
    // AudioRecord session half-released for the next screen that needs it.
    unawaited(_stopThenDisposeRecorder());
    unawaited(_app.cloudTts.stop());
    _app.tts.stop();
    super.dispose();
  }

  Future<void> _stopThenDisposeRecorder() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._stopThenDisposeRecorder: stop failed', fatal: false));
    }
    await _recorder.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speaking = _state == _CallState.speaking;
    final listening = _state == _CallState.listening;

    return Scaffold(
      backgroundColor: AppTheme.bgDashboard,
      appBar: AppBar(
        backgroundColor: AppTheme.topbar,
        title: Text(AppLocalizations.of(context)!.aiTutorCallScreenTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceDark,
                  border: Border.all(
                    color: speaking ? AppTheme.accentBright : AppTheme.borderDark,
                    width: speaking ? 3 : 1.5,
                  ),
                  boxShadow: speaking
                      ? [BoxShadow(color: AppTheme.accentBright.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)]
                      : null,
                ),
                child: Center(child: Text(_persona.avatar, style: const TextStyle(fontSize: 56))),
              ),
              if (_persona.displayName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _persona.displayName,
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textMainDark),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Sora', fontSize: 16, color: AppTheme.textMainDark, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: _transcript.isNotEmpty
                    ? Text(
                        '"$_transcript"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textSubDark, fontStyle: FontStyle.italic),
                      )
                    : null,
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.red),
                  ),
                ),
              const SizedBox(height: 32),
              Semantics(
                button: true,
                enabled: true,
                label: _muted
                    ? AppLocalizations.of(context)!.aiTutorCallMicMutedLabel
                    : listening
                        ? AppLocalizations.of(context)!.aiTutorCallMicRecordingLabel
                        : AppLocalizations.of(context)!.aiTutorCallMicIdleLabel,
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _muted ? AppTheme.surfaceDark : (listening ? AppTheme.red : AppTheme.accent),
                      border: _muted ? Border.all(color: AppTheme.borderDark, width: 1.5) : null,
                      boxShadow: listening && !_muted
                          ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 3)]
                          : null,
                    ),
                    child: Icon(
                      _muted ? Icons.mic_off_rounded : (listening ? Icons.graphic_eq_rounded : Icons.mic_rounded),
                      color: _muted ? AppTheme.textSubDark : Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.call_end_rounded, size: 18),
                label: Text(
                  AppLocalizations.of(context)!.aiTutorCallEndButton,
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.red,
                  side: const BorderSide(color: AppTheme.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
