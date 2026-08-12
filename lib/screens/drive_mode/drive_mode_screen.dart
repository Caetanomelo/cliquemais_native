import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/scoring_service.dart';
import '../../core/services/voice_command_service.dart';
import '../../data/models/phrase.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/speech_bubble.dart';
import '../../widgets/unit_complete_dialog.dart';

enum _ResultKind { none, success, retry }

/// Port of DriveModeController (index.html:2866-4804): hands-free voice
/// practice. Word-overlap scoring against 0.40 raw-fraction threshold; like
/// Vocabulário, never auto-advances on failure — only a genuinely correct
/// score moves to the next phrase. 5s celebration/retry overlays, local
/// voice-command matching for NEXT/PREV/REPEAT/SKIP/EXIT, live partial STT
/// transcript and manual stop-to-finish recording (same as VPC's `_record`).
class DriveModeScreen extends StatefulWidget {
  final List<int> units;
  const DriveModeScreen({super.key, required this.units});

  @override
  State<DriveModeScreen> createState() => _DriveModeScreenState();
}

class _DriveModeScreenState extends State<DriveModeScreen> {
  late final AppStateProvider _app;
  List<Phrase> _phrases = const [];
  int _index = 0;
  int _attemptCount = 0;
  final Set<int> _correctIndices = {};
  bool _busy = false;
  bool _listening = false;
  bool _processing = false;
  String _statusText = 'Preparando…';
  String _liveText = '';
  bool _liveIsFinal = false;

  double? _lastScore;
  String? _lastTranscript;
  _ResultKind _resultKind = _ResultKind.none;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _phrases = widget.units.expand((u) => _app.unitData.phrasesForUnit(u)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakAndListen());
  }

  @override
  void dispose() {
    _app.speech.cancel();
    _app.cloudTts.stop();
    super.dispose();
  }

  Phrase? get _current => _index < _phrases.length ? _phrases[_index] : null;

  Future<void> _speakAndListen() async {
    final phrase = _current;
    if (phrase == null) return;
    _processing = false;
    setState(() {
      _busy = true;
      _statusText = '▶ Ouvindo a frase…';
      _resultKind = _ResultKind.none;
      _liveText = '';
      _liveIsFinal = false;
    });

    final baseRate = phrase.rate;
    final firstRate = (baseRate - 0.06).clamp(0.45, 1.0);
    if (_attemptCount == 0) {
      await _app.cloudTts.speak(phrase.en, rate: firstRate, voiceGender: _app.voiceGender);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    await _app.cloudTts.speak(phrase.en, rate: baseRate, voiceGender: _app.voiceGender);

    if (!mounted) return;
    setState(() {
      _statusText = 'Aperte para falar';
      _busy = false;
    });
  }

  Future<void> _startListening() async {
    if (!mounted || _listening || _processing) return;
    setState(() {
      _listening = true;
      _statusText = '🎙️ Escutando…';
      _liveText = '';
      _liveIsFinal = false;
    });
    await _app.speech.listen(
      partialResults: true,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _liveText = text;
          _liveIsFinal = isFinal;
        });
        if (isFinal) _handleVoiceResult(text);
      },
    );
  }

  Future<void> _stopRecording() async {
    await _app.speech.stop();
  }

  void _handleVoiceResult(String transcript) {
    if (_processing || !mounted) return;
    setState(() {
      _listening = false;
      _statusText = 'Toque para falar';
    });
    if (transcript.trim().isEmpty) return;
    _processing = true;

    final wordCount = transcript.trim().split(RegExp(r'\s+')).length;
    if (wordCount <= 3) {
      final cmd = VoiceCommandService.match(transcript);
      if (cmd != null) {
        _dispatchCommand(cmd);
        return;
      }
    }

    final phrase = _current;
    if (phrase == null) return;
    final score = ScoringService.driveScore(transcript, phrase.en);
    _attemptCount++;

    setState(() {
      _lastScore = score;
      _lastTranscript = transcript;
    });

    final correct = score >= 0.40;
    _app.chime.play(correct);
    if (correct) _correctIndices.add(_index);
    setState(() => _resultKind = correct ? _ResultKind.success : _ResultKind.retry);

    Future.delayed(const Duration(milliseconds: 5000), () async {
      if (!mounted) return;
      _processing = false;
      setState(() => _resultKind = _ResultKind.none);
      if (correct) {
        _attemptCount = 0;
        await _app.addXp(5);
        _nextPhrase();
      } else {
        // Retry: never auto-advances on failure, same rule as Vocabulário.
        _speakAndListen();
      }
    });
  }

  void _dispatchCommand(VoiceCommandMatch cmd) {
    switch (cmd.intent) {
      case VoiceIntent.next:
      case VoiceIntent.skip:
      case VoiceIntent.confirm:
        _attemptCount = 0;
        _nextPhrase();
        break;
      case VoiceIntent.prev:
        _attemptCount = 0;
        _prevPhrase();
        break;
      case VoiceIntent.repeat:
      case VoiceIntent.resume:
        _speakAndListen();
        break;
      case VoiceIntent.pause:
        _app.speech.cancel();
        setState(() => _statusText = 'Pausado — diga "resume" ou toque no microfone');
        break;
      case VoiceIntent.exit:
        Navigator.of(context).maybePop();
        break;
    }
  }

  void _nextPhrase() {
    if (_index < _phrases.length - 1) {
      setState(() {
        _index++;
        _lastScore = null;
        _lastTranscript = null;
      });
      _speakAndListen();
    } else {
      _finishSession();
    }
  }

  void _prevPhrase() {
    if (_index > 0) {
      setState(() {
        _index--;
        _lastScore = null;
        _lastTranscript = null;
      });
      _speakAndListen();
    }
  }

  void _finishSession() {
    if (_correctIndices.length == _phrases.length) {
      unawaited(_app.markDriveUnitsComplete(widget.units));
    }
    showUnitCompleteDialog(context, message: 'Você praticou todas as frases desta unidade.');
  }

  Color _scoreColor(double score) {
    if (score >= 0.9) return AppTheme.green;
    if (score >= 0.70) return AppTheme.accent;
    if (score >= 0.40) return AppTheme.gold;
    return AppTheme.red;
  }

  String _scoreEmoji(double score) {
    if (score >= 0.9) return '⭐';
    if (score >= 0.70) return '👏';
    if (score >= 0.40) return '👍';
    return '🔁';
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _current;
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      appBar: AppBar(
        title: const Text('Drive Mode'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${_index + 1}/${_phrases.length}',
                  style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textSubDark)),
            ),
          ),
        ],
      ),
      body: phrase == null
          ? const Center(child: Text('Sem frases para esta unidade.', style: TextStyle(color: AppTheme.textSubDark)))
          : Stack(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _phrases.isEmpty ? 0 : (_index + 1) / _phrases.length,
                          backgroundColor: AppTheme.navBorder,
                          valueColor: const AlwaysStoppedAnimation(AppTheme.accentBright),
                        ),
                        const SizedBox(height: 32),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(phrase.en,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontFamily: 'Sora', fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                              const SizedBox(height: 10),
                              Text(phrase.pt,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontFamily: 'Sora', fontSize: 15, color: AppTheme.textSubDark)),
                              const SizedBox(height: 28),
                              Text(_statusText,
                                  style: TextStyle(
                                      fontFamily: 'Sora',
                                      fontSize: 13,
                                      color: _listening ? AppTheme.accentBright : AppTheme.textSubDark)),
                              if (_liveText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    '"$_liveText"',
                                    style: TextStyle(
                                      fontFamily: 'Sora',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FontStyle.italic,
                                      color: _liveIsFinal ? AppTheme.green : AppTheme.accentBright,
                                    ),
                                  ),
                                ),
                              if (_lastScore != null && _lastTranscript != null) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _scoreColor(_lastScore!).withValues(alpha: 0.12),
                                    border: Border.all(color: _scoreColor(_lastScore!).withValues(alpha: 0.35)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_scoreEmoji(_lastScore!)} ${(_lastScore! * 100).round()}% — Ouvi: "$_lastTranscript"',
                                    style: TextStyle(fontFamily: 'Sora', fontSize: 13, color: _scoreColor(_lastScore!)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!_busy && !_listening) ...[
                          const SpeechBubble(),
                          const SizedBox(height: 12),
                        ],
                        Semantics(
                          button: true,
                          enabled: !_busy,
                          label: _listening ? 'Parar gravação' : 'Gravar pronúncia',
                          child: GestureDetector(
                            onTap: _busy ? null : (_listening ? _stopRecording : _startListening),
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _listening ? AppTheme.red : AppTheme.accent,
                                boxShadow: _listening
                                    ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)]
                                    : null,
                              ),
                              child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _prevPhrase,
                              icon: const Icon(Icons.skip_previous_rounded, color: AppTheme.textSubDark),
                              label: const Text('Anterior', style: TextStyle(color: AppTheme.textSubDark)),
                            ),
                            TextButton.icon(
                              onPressed: () => _speakAndListen(),
                              icon: const Icon(Icons.replay_rounded, color: AppTheme.textSubDark),
                              label: const Text('Repetir', style: TextStyle(color: AppTheme.textSubDark)),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                _attemptCount = 0;
                                _nextPhrase();
                              },
                              icon: const Icon(Icons.skip_next_rounded, color: AppTheme.textSubDark),
                              label: const Text('Próximo', style: TextStyle(color: AppTheme.textSubDark)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_resultKind != _ResultKind.none)
                  _ResultOverlay(success: _resultKind == _ResultKind.success),
              ],
            ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  final bool success;
  const _ResultOverlay({required this.success});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: success ? AppTheme.green : AppTheme.red, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(success ? '🎉' : '🔁', style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 10),
                Text(
                  success ? 'Muito bem!' : 'Tente novamente!',
                  style: TextStyle(
                      fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w700, color: success ? AppTheme.green : AppTheme.red),
                ),
                const SizedBox(height: 6),
                Text(
                  success ? 'Pronúncia correta!' : 'Vamos tentar mais uma vez',
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
