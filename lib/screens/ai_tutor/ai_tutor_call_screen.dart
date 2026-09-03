import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/ai_tutor_service.dart';
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
/// every tick). So instead, a disposable "monitor" recording runs whenever
/// the call is armed (idle, unmuted) purely to sample dBFS amplitude; the
/// instant that crosses the calibrated threshold, the monitor recording is
/// stopped/discarded and the real per-turn WAV recording starts immediately
/// on the same `AudioRecorder` (its amplitude stream survives across
/// start/stop cycles of one instance) — trading a small (~100-150ms) restart
/// gap for not having to trim a continuously-growing WAV file.
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

  late final AppStateProvider _app;
  final AudioRecorder _recorder = AudioRecorder();
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
  StreamSubscription<Amplitude>? _ampSub;
  String? _monitorPath;
  int _fillerToken = 0;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _persona = _app.aiContent.pickPersona();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWelcome());
  }

  // Continuous listening leaves a raw AudioRecord session open (monitor or
  // real turn recording) if the user backgrounds the app — without this, the
  // recorder keeps the mic reserved and TTS keeps playing while the app
  // isn't in front of the user.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
      unawaited(_beginTurnFromVad());
    }
  }

  Future<void> _beginTurnFromVad() async {
    if (_turnActive || _state != _CallState.idle || _muted) return;
    _turnActive = true;
    _vadSilenceSince = null;
    try {
      final monitorPath = await _recorder.stop();
      if (monitorPath != null) unawaited(_safeDelete(monitorPath));
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._beginTurnFromVad: stop monitor failed', fatal: false));
    }
    final path = '${Directory.systemTemp.path}/call_turn_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._beginTurnFromVad: start turn failed', fatal: false));
      _turnActive = false;
      unawaited(_armVad());
      return;
    }
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
      final bytes = await File(path).readAsBytes();
      unawaited(_safeDelete(path));
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

  Future<void> _assessAndSend(List<int> wavBytes) async {
    unawaited(_playFillers(includeAnalyzing: true));

    final result = await assessCallTurn(
      _app.pronunciation,
      wavBytes,
      primaryLang: resolveLocale(_app.courseLanguage),
      nativeLang: resolveLocale(_app.nativeLanguage),
      onError: (e, st, {required reason}) =>
          unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._assessAndSend: $reason', fatal: false)),
    );

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
      final reply = await _app.aiTutor.send(
        systemPrompt: systemPrompt,
        history: priorHistory,
        userMessage: outgoing,
      );
      _history.add(AiChatMessage(role: 'assistant', content: reply));
      if (!mounted) return;
      await _speak(reply.isNotEmpty ? reply : AppLocalizations.of(context)!.aiTutorCallRepeatFallback);
      if (!mounted || _muted) return;
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

  String _randomFillerAck() {
    final l10n = AppLocalizations.of(context)!;
    final options = [l10n.aiTutorCallFillerAck1, l10n.aiTutorCallFillerAck2, l10n.aiTutorCallFillerAck3];
    return options[_rng.nextInt(options.length)];
  }

  String _randomFillerAnalyzing() {
    final l10n = AppLocalizations.of(context)!;
    final options = [l10n.aiTutorCallFillerAnalyzing1, l10n.aiTutorCallFillerAnalyzing2];
    return options[_rng.nextInt(options.length)];
  }

  Future<void> _playFillers({required bool includeAnalyzing}) async {
    final token = ++_fillerToken;
    if (!mounted) return;
    final nativeLang = _app.nativeLanguage;
    try {
      await _app.cloudTts.speakSpeechify(
        _randomFillerAck(),
        langCode: nativeLang,
        voiceGender: _app.voiceGender,
        fallbackLanguage: resolveLocale(nativeLang),
      );
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._playFillers: ack failed', fatal: false));
    }
    if (!includeAnalyzing || token != _fillerToken || !mounted || _state != _CallState.thinking) return;
    try {
      await _app.cloudTts.speakSpeechify(
        _randomFillerAnalyzing(),
        langCode: nativeLang,
        voiceGender: _app.voiceGender,
        fallbackLanguage: resolveLocale(nativeLang),
      );
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._playFillers: analyzing failed', fatal: false));
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
    for (final seg in _parseBilingualSegments(clean)) {
      if (!mounted) return;
      // AI Tutor sempre usa Speechify (paridade com web's _route()), com
      // fallback pro TTS on-device do proprio CloudTtsService.speakSpeechify
      // se a Netlify function falhar/sem rede.
      await _app.cloudTts.speakSpeechify(
        seg.text,
        langCode: seg.langCode,
        voiceGender: _app.voiceGender,
        fallbackLanguage: resolveLocale(seg.langCode),
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
