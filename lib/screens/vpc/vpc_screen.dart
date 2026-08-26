import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/scoring_service.dart';
import '../../data/models/course_language.dart';
import '../../data/models/vocab_item.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/leave_while_recording_dialog.dart';
import '../../widgets/live_transcript_text.dart';
import '../../widgets/practice_result_overlay.dart';
import '../../widgets/record_mic_button.dart';
import '../../widgets/speech_bubble.dart';
import '../../widgets/unit_complete_dialog.dart';
import '../../widgets/vpc_ring_painter.dart';

enum _Overlay { none, celebrate, fail }

/// Port of the VPC (vocabulary flashcard) module (decoded_app.html ~8247-
/// 8830): word-overlap + exact-match scoring, live partial STT streaming,
/// synchronous ring/percent update before the result overlay appears, and
/// the deliberate "never auto-advance on failure" rule (`willAdvance=exact`,
/// commit 5cdad43) — VPC only advances on an exact spoken match, regardless
/// of attempt count, unlike Drive Mode's 3-attempt fallback.
class VpcScreen extends StatefulWidget {
  final List<int> units;
  final int startIndex;
  // Fase 7: skip already-mastered words when building the session queue.
  // Direct single-word entry (VocabLessonView._testPronunciation) passes
  // false — the student explicitly chose that word, so it must never be
  // filtered out from under them, mirroring web's VPC.openAndRecord.
  final bool filterCompleted;
  const VpcScreen({super.key, required this.units, this.startIndex = 0, this.filterCompleted = true});

  @override
  State<VpcScreen> createState() => _VpcScreenState();
}

class _VpcScreenState extends State<VpcScreen> {
  late final AppStateProvider _app;
  late final ConfettiController _confetti;
  List<VocabItem> _items = const [];
  // Parallel to _items (same index) — see the identical _phraseUnits field
  // on DriveModeScreen for why a multi-unit session needs this tracked
  // alongside instead of on the model.
  List<int> _itemUnits = const [];
  final Set<int> _correctIndices = {};
  int _index = 0;
  bool _listening = false;
  bool _processing = false;
  final ValueNotifier<LiveTranscript> _liveTranscript = ValueNotifier(const LiveTranscript());

  int? _score;
  String? _spoken;
  _Overlay _overlay = _Overlay.none;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    final items = <VocabItem>[];
    final itemUnits = <int>[];
    for (final u in widget.units) {
      final vs = _app.unitData.vocabForUnit(u);
      items.addAll(vs);
      itemUnits.addAll(List.filled(vs.length, u));
    }
    if (widget.filterCompleted) {
      final fi = <VocabItem>[];
      final fu = <int>[];
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        if (it.id == null || !_app.completions.isCompleted('vocab:${it.id}')) {
          fi.add(it);
          fu.add(itemUnits[i]);
        }
      }
      // Don't strand the student: if every word here is already mastered,
      // fall back to the full unfiltered list instead of an empty session.
      _items = fi.isNotEmpty ? fi : items;
      _itemUnits = fi.isNotEmpty ? fu : itemUnits;
    } else {
      _items = items;
      _itemUnits = itemUnits;
    }
    _index = widget.startIndex.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    _confetti = ConfettiController(duration: const Duration(milliseconds: 600));
    // speech.init() is no longer awaited during boot (PERF-1) — warm it up
    // here so it's ready by the time the user taps the mic, instead of
    // eating that latency on the first listen() call.
    unawaited(_app.speech.init());
  }

  @override
  void dispose() {
    _confetti.dispose();
    _liveTranscript.dispose();
    _app.speech.cancel();
    _app.cloudTts.stop();
    super.dispose();
  }

  // Resolved to the current (target, native) pair — vocab_items.json items
  // come straight from UnitDataRepository, unrelated to any Lesson block, so
  // there's no raw JSON left around for a per-screen forPair() call; each
  // item's own retained triple (VocabItem.byLanguage) is what resolvePair
  // re-picks from.
  VocabItem? get _current =>
      _index < _items.length ? _items[_index].resolvePair(_app.courseLanguage, _app.nativeLanguage) : null;

  void _resetUi() {
    _liveTranscript.value = const LiveTranscript();
    setState(() {
      _score = null;
      _spoken = null;
      _overlay = _Overlay.none;
    });
  }

  Future<void> _playTutor() async {
    final item = _current;
    if (item == null) return;
    await _app.cloudTts.speak(item.en, rate: 0.5, voiceGender: _app.voiceGender, language: resolveLocale(_app.courseLanguage));
  }

  Future<void> _record() async {
    final item = _current;
    if (item == null || _listening || _processing) return;
    _liveTranscript.value = const LiveTranscript();
    setState(() => _listening = true);
    await _app.speech.listen(
      partialResults: true,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      localeId: resolveLocale(_app.courseLanguage).replaceAll('-', '_'),
      onResult: (text, isFinal) {
        if (!mounted) return;
        _liveTranscript.value = LiveTranscript(text: text, isFinal: isFinal);
        if (isFinal && text.trim().isNotEmpty) {
          _finishRecording(item, text);
        } else if (isFinal) {
          setState(() => _listening = false);
        }
      },
    );
  }

  Future<void> _stopRecording() async {
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

  void _finishRecording(VocabItem item, String spoken) {
    if (_processing) return;
    _processing = true;
    setState(() => _listening = false);
    final result = ScoringService.scoreVpc(item.en, spoken);
    _showResult(result.score, spoken, result.exact);
  }

  void _showResult(int sc, String spoken, bool exact) {
    final xp = sc >= 85 ? 15 : (sc >= 50 ? 8 : 3);
    _app.addXp(xp);
    if (exact) {
      _correctIndices.add(_index);
      final item = _items[_index];
      if (item.id != null) {
        unawaited(_app.completions.record(
          module: 'vocab_lab',
          contentId: 'vocab:${item.id}',
          unit: _itemUnits[_index],
          domain: 'vocabulary',
        ));
      }
    }

    setState(() {
      _score = sc;
      _spoken = spoken;
      _overlay = exact ? _Overlay.celebrate : _Overlay.fail;
    });

    if (exact) {
      _confetti.play();
    }
    _app.chime.play(exact);

    final dismissAfter = exact ? const Duration(milliseconds: 2400) : const Duration(milliseconds: 2200);
    Future.delayed(dismissAfter, () {
      if (!mounted) return;
      _processing = false;
      if (exact) {
        if (_index < _items.length - 1) {
          setState(() {
            _overlay = _Overlay.none;
            _index++;
          });
          _resetUi();
        } else {
          setState(() => _overlay = _Overlay.none);
          _finishSession();
        }
      } else {
        // Retry: never auto-advances on failure, no matter the attempt count.
        _liveTranscript.value = const LiveTranscript();
        setState(() {
          _overlay = _Overlay.none;
          _score = null;
          _spoken = null;
        });
      }
    });
  }

  void _finishSession() {
    if (_correctIndices.length == _items.length) {
      unawaited(_app.markVocabUnitsComplete(widget.units));
    }
    showUnitCompleteDialog(context, message: 'Você praticou todo o vocabulário desta unidade.');
  }

  Color _ringColor(int sc) {
    if (sc >= 85) return AppTheme.green;
    if (sc >= 50) return AppTheme.accent2;
    return AppTheme.red;
  }

  String _verdictText(int sc) {
    if (sc >= 85) return '🌟 Incrível!';
    if (sc >= 50) return '👍 Muito Bom!';
    return '💪 Continue tentando!';
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    final ringPercent = (_score ?? 0) / 100;
    final ringColor = _score != null ? _ringColor(_score!) : AppTheme.green;

    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      appBar: AppBar(
        title: const Text('Vocabulário'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${_index + 1}/${_items.length}',
                  style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textSubDark)),
            ),
          ),
        ],
      ),
      body: item == null
          ? const Center(child: Text('Sem vocabulário para esta unidade.', style: TextStyle(color: AppTheme.textSubDark)))
          : Stack(
              alignment: Alignment.topCenter,
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 88,
                          height: 88,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(88, 88),
                                painter: VpcRingPainter(percent: ringPercent, strokeColor: ringColor),
                              ),
                              Text(_score != null ? '$_score%' : '0%',
                                  style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(item.en,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontFamily: 'Sora', fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                              const SizedBox(height: 8),
                              Text(item.pt,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontFamily: 'Sora', fontSize: 15, color: AppTheme.textSubDark)),
                              const SizedBox(height: 20),
                              LiveTranscriptText(
                                listenable: _liveTranscript,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              if (_score != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(_verdictText(_score!),
                                      style: TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: ringColor)),
                                ),
                            ],
                          ),
                        ),
                        // Fixed-height slot, see DriveModeScreen's identical comment:
                        // reserves the bubble's space regardless of visibility so the
                        // Expanded above doesn't re-center and jump the item text.
                        SizedBox(
                          height: 60,
                          child: !_listening ? const Align(alignment: Alignment.topCenter, child: SpeechBubble()) : null,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _playTutor,
                              icon: const Icon(Icons.volume_up_rounded, color: AppTheme.accentBright),
                              label: const Text('Tutor', style: TextStyle(color: AppTheme.accentBright)),
                            ),
                            const SizedBox(width: 12),
                            RecordMicButton(
                              listening: _listening,
                              onTap: _listening ? _stopRecording : _record,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _confetti,
                    blastDirectionality: BlastDirectionality.explosive,
                    numberOfParticles: _score == 100 ? 80 : (_score != null && _score! >= 90 ? 55 : 35),
                    maxBlastForce: 20,
                    minBlastForce: 8,
                    emissionFrequency: 0.04,
                    gravity: 0.3,
                    colors: const [AppTheme.gold, AppTheme.green, AppTheme.accentBright, Colors.white],
                  ),
                ),
                if (_overlay != _Overlay.none) _resultOverlay(),
              ],
            ),
      bottomNavigationBar: AppBottomNav(onBeforeLeave: _confirmLeaveWhileRecording),
    );
  }

  Widget _resultOverlay() {
    final success = _overlay == _Overlay.celebrate;
    final score = _score ?? 0;
    return PracticeResultOverlay(
      icon: success ? (score == 100 ? '🏆' : (score >= 90 ? '🌟' : '🎉')) : '✕',
      title: success ? 'Correto!' : '✕',
      subtitle: success ? (score == 100 ? 'Pronúncia perfeita!' : (score >= 90 ? 'Excelente pronúncia!' : 'Muito bem!')) : 'Tente novamente',
      color: success ? AppTheme.green : AppTheme.red,
      detail: !success && _spoken != null && _spoken!.trim().isNotEmpty ? 'Você disse: "$_spoken"' : null,
    );
  }
}
