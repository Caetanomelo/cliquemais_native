import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/ai_tutor_service.dart';
import '../../providers/app_state_provider.dart';

enum _CallState { idle, listening, thinking, speaking }

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

class _AiTutorCallScreenState extends State<AiTutorCallScreen> {
  late final AppStateProvider _app;
  final AudioRecorder _recorder = AudioRecorder();
  final List<AiChatMessage> _history = [];
  _CallState _state = _CallState.idle;
  String _transcript = '';

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWelcome());
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
    String transcript = '';
    String feedback = '';
    try {
      final enResult = await _app.pronunciation.assess(wavBytes, lang: 'en-US');
      if (enResult != null && enResult.isConfidentEnglish) {
        transcript = enResult.recognizedText;
        feedback = enResult.toFeedbackNote();
      } else {
        final ptResult = await _app.pronunciation.assess(wavBytes, lang: 'pt-BR');
        transcript = ptResult?.recognizedText ?? '';
      }
    } catch (e, st) {
      // Azure unreachable/misconfigured (missing keys, timeout, etc.) — try
      // one plain pt-BR pass as a last resort; if that also fails, give up
      // on this turn gracefully below rather than sending garbage upstream.
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._assessAndSend: en-US assess failed', fatal: false));
      try {
        final ptResult = await _app.pronunciation.assess(wavBytes, lang: 'pt-BR');
        transcript = ptResult?.recognizedText ?? '';
      } catch (e2, st2) {
        unawaited(FirebaseCrashlytics.instance.recordError(e2, st2, reason: 'AiTutorCallScreen._assessAndSend: pt-BR fallback assess failed', fatal: false));
      }
    }

    if (transcript.trim().isEmpty) {
      if (mounted) setState(() => _state = _CallState.idle);
      return;
    }
    if (mounted) setState(() => _transcript = transcript);
    await _sendToAI(transcript, feedback);
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
      await _speak(reply.isNotEmpty ? reply : 'Desculpe, pode repetir?');
    } catch (e, st) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'AiTutorCallScreen._sendToAI failed', fatal: false));
      if (mounted) setState(() => _state = _CallState.idle);
    }
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() => _state = _CallState.speaking);
    final clean = text.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('**', '');
    await _app.tts.speak(clean, language: 'pt-BR', voiceGender: _app.voiceGender);
    if (mounted) setState(() => _state = _CallState.idle);
  }

  String get _statusText {
    switch (_state) {
      case _CallState.idle:
        return 'Segure para falar';
      case _CallState.listening:
        return 'Ouvindo...';
      case _CallState.thinking:
        return 'Pensando...';
      case _CallState.speaking:
        return 'Falando...';
    }
  }

  @override
  void dispose() {
    unawaited(_recorder.stop());
    _recorder.dispose();
    _app.tts.stop();
    super.dispose();
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
        title: const Text('Chamada com o Tutor'),
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
              const SizedBox(height: 32),
              Semantics(
                button: true,
                enabled: !busy,
                label: listening ? 'Gravando. Solte para enviar.' : 'Aperte e segure para falar',
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
                label: const Text('Encerrar chamada', style: TextStyle(fontFamily: 'Sora', fontSize: 13)),
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
