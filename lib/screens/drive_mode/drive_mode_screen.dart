import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/scoring_service.dart';
import '../../core/services/voice_command_service.dart';
import '../../data/models/course_language.dart';
import '../../data/models/phrase.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/leave_while_recording_dialog.dart';
import '../../widgets/live_transcript_text.dart';
import '../../widgets/practice_result_overlay.dart';
import '../../widgets/record_mic_button.dart';
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

class _DriveModeScreenState extends State<DriveModeScreen> with WidgetsBindingObserver {
  late final AppStateProvider _app;
  List<Phrase> _phrases = const [];
  // Parallel to _phrases (same index) — a multi-unit session concatenates
  // several units' phrase lists, so the phrase's own index in _phrases can't
  // tell _handleVoiceResult which unit it came from, but
  // content_completions.unit needs that. Phrase itself has no unit field
  // (it's shared with the single-unit lookup in UnitDataRepository), so this
  // is tracked alongside instead of on the model.
  List<int> _phraseUnits = const [];
  int _index = 0;
  int _attemptCount = 0;
  final Set<int> _correctIndices = {};
  bool _busy = false;
  bool _listening = false;
  bool _processing = false;
  // Empty until didChangeDependencies() sets the localized default — the
  // field initializer runs during construction, before context is available.
  String _statusText = '';
  final ValueNotifier<LiveTranscript> _liveTranscript = ValueNotifier(const LiveTranscript());

  double? _lastScore;
  String? _lastTranscript;
  _ResultKind _resultKind = _ResultKind.none;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    final phrases = <Phrase>[];
    final phraseUnits = <int>[];
    for (final u in widget.units) {
      final ps = _app.unitData.phrasesForUnit(u);
      phrases.addAll(ps);
      phraseUnits.addAll(List.filled(ps.length, u));
    }
    // Fase 7: skip phrases already mastered on this (or a synced) device.
    // Don't strand the student: if every phrase here is already mastered,
    // fall back to the full unfiltered list instead of an empty session.
    final fp = <Phrase>[];
    final fu = <int>[];
    for (var i = 0; i < phrases.length; i++) {
      final p = phrases[i];
      if (p.id == null || !_app.completions.isCompleted('drive:${p.id}')) {
        fp.add(p);
        fu.add(phraseUnits[i]);
      }
    }
    _phrases = fp.isNotEmpty ? fp : phrases;
    _phraseUnits = fp.isNotEmpty ? fu : phraseUnits;
    WidgetsBinding.instance.addObserver(this);
    // speech.init() is no longer awaited during boot (PERF-1) — warm it up
    // here so it's ready by the time _speakAndListen's first listen() call
    // needs it, instead of eating that latency on screen entry.
    unawaited(_app.speech.init());
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakAndListen());
  }

  bool _statusInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_statusInitialized) {
      _statusInitialized = true;
      _statusText = AppLocalizations.of(context)!.driveModeStatusHold;
    }
  }

  // Hands-free voice practice means the mic can be actively recording when
  // the user switches apps or takes a call — without this, it keeps
  // capturing audio in the background and the phrase never advances since
  // no result callback fires while backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _app.cloudTts.stop();
    if (_listening) {
      _app.speech.cancel();
      if (mounted) {
        setState(() {
          _listening = false;
          _statusText = AppLocalizations.of(context)!.driveModeStatusPausedBackground;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTranscript.dispose();
    _app.speech.cancel();
    _app.cloudTts.stop();
    super.dispose();
  }

  // Resolved to the current (target, native) pair — drive_phrases.json items
  // come straight from UnitDataRepository, unrelated to any Lesson block, so
  // there's no raw JSON left around for a per-screen forPair() call; each
  // phrase's own retained triple (Phrase.byLanguage) is what forPair()
  // re-picks from.
  Phrase? get _current =>
      _index < _phrases.length ? _phrases[_index].forPair(_app.courseLanguage, _app.nativeLanguage) : null;

  Future<void> _speakAndListen() async {
    final phrase = _current;
    if (phrase == null) return;
    _processing = false;
    _liveTranscript.value = const LiveTranscript();
    // _busy still gates mic input (RecordMicButton's `enabled: !_busy`) and
    // the bubble slot below, but no longer swaps in a distinct "listening"
    // screen/status text — the phrase audio plays over the same ready-state
    // layout the screen opens with, instead of visibly flashing through a
    // separate loading state first.
    setState(() {
      _busy = true;
      _resultKind = _ResultKind.none;
    });

    final text = phrase.en;
    final locale = resolveLocale(_app.courseLanguage);
    final baseRate = phrase.rate;
    final firstRate = (baseRate - 0.06).clamp(0.45, 1.0);
    if (_attemptCount == 0) {
      await _app.cloudTts.speak(text, rate: firstRate, voiceGender: _app.voiceGender, language: locale);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    await _app.cloudTts.speak(text, rate: baseRate, voiceGender: _app.voiceGender, language: locale);

    if (!mounted) return;
    setState(() {
      _statusText = AppLocalizations.of(context)!.driveModeStatusHold;
      _busy = false;
    });
  }

  Future<void> _startListening() async {
    if (!mounted || _listening || _processing) return;
    _liveTranscript.value = const LiveTranscript();
    setState(() {
      _listening = true;
      _statusText = AppLocalizations.of(context)!.driveModeStatusListening;
    });
    await _app.speech.listen(
      partialResults: true,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      localeId: resolveLocale(_app.courseLanguage).replaceAll('-', '_'),
      onResult: (text, isFinal) {
        if (!mounted) return;
        _liveTranscript.value = LiveTranscript(text: text, isFinal: isFinal);
        if (isFinal) _handleVoiceResult(text);
      },
    );
  }

  Future<void> _stopRecording() async {
    // Flip the button off on this tap itself — waiting for speech.stop() to
    // resolve via the plugin's final onResult callback left the mic showing
    // red/"listening" on silence (no speech captured => no final result
    // ever fires), so a second tap didn't visibly turn it off. Any transcript
    // still in flight keeps landing in _handleVoiceResult as before; it just
    // re-sets _listening (already false) rather than being the first setter.
    if (mounted) {
      setState(() {
        _listening = false;
        _statusText = AppLocalizations.of(context)!.driveModeStatusTapToSpeak;
      });
    }
    await _app.speech.stop();
  }

  // Guards the bottom nav's tab switch (see AppBottomNav.onBeforeLeave):
  // without this, tapping another tab mid-recording silently throws away
  // whatever the user has already spoken.
  Future<bool> _confirmLeaveWhileRecording() => confirmLeaveWhileRecording(
        context,
        listening: _listening,
        onDiscard: _app.speech.cancel,
      );

  void _handleVoiceResult(String transcript) {
    if (_processing || !mounted) return;
    setState(() {
      _listening = false;
      _statusText = AppLocalizations.of(context)!.driveModeStatusTapToSpeak;
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
    if (correct) {
      _correctIndices.add(_index);
      // id is a defensive-nullable JSON field — record() itself also
      // no-ops silently when logged out.
      if (phrase.id != null) {
        unawaited(_app.completions.record(
          module: 'drive_mode',
          contentId: 'drive:${phrase.id}',
          unit: _phraseUnits[_index],
          domain: 'pronunciation',
        ));
      }
    }
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
        setState(() => _statusText = AppLocalizations.of(context)!.driveModeStatusPausedVoice);
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
    showUnitCompleteDialog(context, message: AppLocalizations.of(context)!.driveModeFinishMessage);
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
        title: Text(AppLocalizations.of(context)!.driveModeTitle),
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
          ? Center(child: Text(AppLocalizations.of(context)!.driveModeNoPhrases, style: const TextStyle(color: AppTheme.textSubDark)))
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
                              LiveTranscriptText(
                                listenable: _liveTranscript,
                                padding: const EdgeInsets.only(top: 12),
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
                                    AppLocalizations.of(context)!.driveModeScoreResult(
                                      _scoreEmoji(_lastScore!),
                                      (_lastScore! * 100).round(),
                                      _lastTranscript!,
                                    ),
                                    style: TextStyle(fontFamily: 'Sora', fontSize: 13, color: _scoreColor(_lastScore!)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Fixed-height slot (bubble height + the 12px gap it used to
                        // add) reserved regardless of whether the bubble is shown —
                        // otherwise the Expanded above re-centers into the freed/taken
                        // space every time _listening flips, and the phrase text
                        // visibly jumps. Shown regardless of _busy too, matching the
                        // rest of the screen staying on the same ready-state layout
                        // while the phrase audio plays.
                        SizedBox(
                          height: 60,
                          child: !_listening ? const Align(alignment: Alignment.topCenter, child: SpeechBubble()) : null,
                        ),
                        RecordMicButton(
                          listening: _listening,
                          enabled: !_busy,
                          onTap: _listening ? _stopRecording : _startListening,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _prevPhrase,
                              icon: const Icon(Icons.skip_previous_rounded, color: AppTheme.textSubDark),
                              label: Text(AppLocalizations.of(context)!.driveModePrevious, style: const TextStyle(color: AppTheme.textSubDark)),
                            ),
                            TextButton.icon(
                              onPressed: () => _speakAndListen(),
                              icon: const Icon(Icons.replay_rounded, color: AppTheme.textSubDark),
                              label: Text(AppLocalizations.of(context)!.driveModeRepeat, style: const TextStyle(color: AppTheme.textSubDark)),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                _attemptCount = 0;
                                _nextPhrase();
                              },
                              icon: const Icon(Icons.skip_next_rounded, color: AppTheme.textSubDark),
                              label: Text(AppLocalizations.of(context)!.driveModeNext, style: const TextStyle(color: AppTheme.textSubDark)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_resultKind != _ResultKind.none) _resultOverlay(),
              ],
            ),
      bottomNavigationBar: AppBottomNav(onBeforeLeave: _confirmLeaveWhileRecording),
    );
  }

  Widget _resultOverlay() {
    final success = _resultKind == _ResultKind.success;
    final l10n = AppLocalizations.of(context)!;
    return PracticeResultOverlay(
      icon: success ? '🎉' : '🔁',
      title: success ? l10n.driveModeResultSuccessTitle : l10n.driveModeResultRetryTitle,
      subtitle: success ? l10n.driveModeResultSuccessSubtitle : l10n.driveModeResultRetrySubtitle,
      color: success ? AppTheme.green : AppTheme.red,
      // Below the phrase card, near the mic/nav row — centered would sit on
      // top of the phrase text and the score badge.
      alignment: const Alignment(0, 0.8),
    );
  }
}
