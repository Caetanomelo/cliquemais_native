import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/ai_tutor_service.dart';
import '../../data/models/course_language.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import 'call_turn_assessor.dart';

enum _CallState { idle, listening, thinking, speaking }

class _CallSegment {
  final String text;
  final String language;
  const _CallSegment(this.text, this.language);
}

/// Live voice call with the AI Tutor — hold-to-talk (press and hold the mic
/// to speak, release to send), mirroring the web app's `AiTutor.openCall()`
/// flow but with raw audio capture instead of live on-device STT, so Azure
/// Pronunciation Assessment can score real mispronounced English words.
///
/// Deliberate divergence from the web app: `speech_to_text` + a raw-audio
/// recorder can't run at once on Android (both claim the mic's exclusive
/// `AudioRecord` session), so this screen uses only `record` for capture and
/// has no live captions — the transcript only appears after the turn ends.
/// Since the call is mostly in Portuguese (the tutor corrects English only
/// when attempted), a single WAV is assessed first against `en-US`; if that
/// pass isn't confidently English, the same bytes are re-sent to Azure as a
/// plain `pt-BR` transcription so ordinary Portuguese turns still work.
/// `SpeechService` is untouched and keeps being used everywhere else (Vocab
/// Lab, Drive Mode).
class AiTutorCallScreen extends StatefulWidget {
  const AiTutorCallScreen({super.key});

  @override
  State<AiTutorCallScreen> createState() => _AiTutorCallScreenState();
}

class _AiTutorCallScreenState extends State<AiTutorCallScreen> with WidgetsBindingObserver {
  late final AppStateProvider _app;
  final AudioRecorder _recorder = AudioRecorder();
  final List<AiChatMessage> _history = [];
  _CallState _state = _CallState.idle;
  String _transcript = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWelcome());
  }

  // Hold-to-talk still leaves a raw AudioRecord session open if the user
  // backgrounds the app mid-hold (e.g. a notification pulls focus away) —
  // without this, the recorder keeps the mic reserved and TTS keeps
  // playing while the app isn't in front of the user.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (_state == _CallState.listening) {
      unawaited(_cancelRecording());
    }
    _app.tts.stop();
  }

  Future<void> _speakWelcome() async {
    final welcome = _app.aiContent.welcomeMessageForKey('call');
    if (welcome.isEmpty) return;
    await _speak(welcome);
  }

  Future<void> _startRecording() async {
    if (_state != _CallState.idle) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final path = '${Directory.systemTemp.path}/call_turn_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _state = _CallState.listening;
      _transcript = '';
      _errorText = null;
    });
  }

  Future<void> _cancelRecording() async {
    if (_state != _CallState.listening) return;
    try {
      final path = await _recorder.stop();
      if (path != null) await _safeDelete(path);
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._cancelRecording failed', fatal: false));
    }
    if (mounted) setState(() => _state = _CallState.idle);
  }

  Future<void> _stopRecordingAndSend() async {
    if (_state != _CallState.listening) return;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._stopRecordingAndSend: recorder.stop failed', fatal: false));
    }
    setState(() => _state = _CallState.thinking);

    if (path == null) {
      if (mounted) setState(() => _state = _CallState.idle);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      unawaited(_safeDelete(path));
      // ~0.25s of 16kHz/16-bit/mono PCM — filters out accidental taps
      // without any real speech before spending an Azure call on them.
      if (bytes.length < 8000) {
        if (mounted) setState(() => _state = _CallState.idle);
        return;
      }
      await _assessAndSend(bytes);
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._stopRecordingAndSend failed', fatal: false));
      if (mounted) setState(() => _state = _CallState.idle);
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
    final result = await assessCallTurn(
      _app.pronunciation,
      wavBytes,
      primaryLang: resolveLocale(_app.courseLanguage),
      nativeLang: resolveLocale(_app.nativeLanguage),
      onError: (e, st, {required reason}) =>
          unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._assessAndSend: $reason', fatal: false)),
    );

    if (result.transcript.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _state = _CallState.idle;
          // Azure unreachable/misconfigured vs. a legitimately silent/noise
          // turn (already filtered above by the byte-length gate) — only
          // the former is worth surfacing as an error the user can act on.
          _errorText = result.failed ? AppLocalizations.of(context)!.aiTutorCallAudioError : null;
        });
      }
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
      final reply = await _app.aiTutor.send(
        systemPrompt: _app.aiContent.systemPromptForKey('call'),
        history: priorHistory,
        userMessage: outgoing,
      );
      _history.add(AiChatMessage(role: 'assistant', content: reply));
      if (!mounted) return;
      await _speak(reply.isNotEmpty ? reply : AppLocalizations.of(context)!.aiTutorCallRepeatFallback);
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._sendToAI failed', fatal: false));
      if (mounted) {
        setState(() {
          _state = _CallState.idle;
          _errorText = AppLocalizations.of(context)!.aiTutorCallReplyError;
        });
      }
    }
  }

  // Divide a resposta do Tutor em trechos por idioma usando o marcador
  // {{...}} que os system prompts de 'call' (migration 060, WEB_BASE)
  // inserem ao redor de palavras/frases no idioma-alvo -- o resto do texto
  // fica no idioma nativo do aluno. Mesmo marcador que o web app usa, ja
  // que ambos consomem o mesmo system_prompt de ai_tutor_modes.
  List<_CallSegment> _parseBilingualSegments(String text) {
    final nativeLocale = resolveLocale(_app.nativeLanguage);
    final targetLocale = resolveLocale(_app.courseLanguage);
    final segments = <_CallSegment>[];
    final re = RegExp(r'\{\{([^{}]*)\}\}');
    var lastIndex = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > lastIndex) {
        segments.add(_CallSegment(text.substring(lastIndex, m.start), nativeLocale));
      }
      final inner = m.group(1) ?? '';
      if (inner.isNotEmpty) {
        segments.add(_CallSegment(inner, targetLocale));
      }
      lastIndex = m.end;
    }
    if (lastIndex < text.length) {
      segments.add(_CallSegment(text.substring(lastIndex), nativeLocale));
    }
    return segments.where((s) => s.text.trim().isNotEmpty).toList();
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() => _state = _CallState.speaking);
    final clean = text.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('**', '');
    for (final seg in _parseBilingualSegments(clean)) {
      if (!mounted) return;
      await _app.tts.speak(seg.text, language: seg.language, voiceGender: _app.voiceGender);
    }
    if (mounted) setState(() => _state = _CallState.idle);
  }

  String get _statusText {
    final l10n = AppLocalizations.of(context)!;
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
    // stop() must finish before dispose() runs — firing both unawaited let
    // dispose() tear down the plugin's native session while stop() was
    // still flushing the in-progress recording, which could throw inside
    // stop() (using an already-disposed channel) or leave the Android
    // AudioRecord session half-released for the next screen that needs it.
    unawaited(_stopThenDisposeRecorder());
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
    final busy = _state == _CallState.thinking || _state == _CallState.speaking;

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
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 56))),
              ),
              const SizedBox(height: 24),
              Text(
                _statusText,
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
                enabled: !busy,
                label: listening
                    ? AppLocalizations.of(context)!.aiTutorCallMicRecordingLabel
                    : AppLocalizations.of(context)!.aiTutorCallMicIdleLabel,
                child: GestureDetector(
                  onTapDown: busy ? null : (_) => _startRecording(),
                  onTapUp: busy ? null : (_) => _stopRecordingAndSend(),
                  onTapCancel: busy ? null : _cancelRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listening ? AppTheme.red : AppTheme.accent,
                      boxShadow: listening
                          ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 3)]
                          : null,
                    ),
                    child: Icon(
                      listening ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
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
