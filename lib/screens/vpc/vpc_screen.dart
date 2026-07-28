import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/scoring_service.dart';
import '../../data/models/vocab_item.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/vpc_ring_painter.dart';

enum _Overlay { none, celebrate, fail }

/// Port of the VPC (vocabulary flashcard) module (decoded_app.html ~8247-
/// 8830): word-overlap + exact-match scoring, live partial STT streaming,
/// synchronous ring/percent update before the result overlay appears, and
/// the deliberate "never auto-advance on failure" rule (`willAdvance=exact`,
/// commit 5cdad43) — VPC only advances on an exact spoken match, regardless
/// of attempt count, unlike Drive Mode's 3-attempt fallback.
class VpcScreen extends StatefulWidget {
  final int unit;
  final int startIndex;
  final bool autoRecord;
  const VpcScreen({super.key, required this.unit, this.startIndex = 0, this.autoRecord = false});

  @override
  State<VpcScreen> createState() => _VpcScreenState();
}

class _VpcScreenState extends State<VpcScreen> {
  late final AppStateProvider _app;
  late final ConfettiController _confetti;
  List<VocabItem> _items = const [];
  int _index = 0;
  bool _listening = false;
  bool _processing = false;
  String _liveText = '';
  bool _liveIsFinal = false;

  int? _score;
  String? _spoken;
  _Overlay _overlay = _Overlay.none;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _items = _app.unitData.vocabForUnit(widget.unit);
    _index = widget.startIndex.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    _confetti = ConfettiController(duration: const Duration(milliseconds: 600));
    if (widget.autoRecord) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _record());
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    _app.speech.cancel();
    _app.cloudTts.stop();
    super.dispose();
  }

  VocabItem? get _current => _index < _items.length ? _items[_index] : null;

  void _resetUi() {
    setState(() {
      _score = null;
      _spoken = null;
      _liveText = '';
      _liveIsFinal = false;
      _overlay = _Overlay.none;
    });
  }

  Future<void> _playTutor() async {
    final item = _current;
    if (item == null) return;
    await _app.cloudTts.speak(item.en, rate: 0.5, voiceGender: _app.voiceGender);
  }

  Future<void> _record() async {
    final item = _current;
    if (item == null || _listening || _processing) return;
    setState(() {
      _listening = true;
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
      if (mounted) setState(() => _overlay = _Overlay.none);
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _processing = false;
      if (exact) {
        if (_index < _items.length - 1) {
          setState(() {
            _index++;
          });
          _resetUi();
        } else {
          _finishSession();
        }
      } else {
        // Retry: never auto-advances on failure, no matter the attempt count.
        setState(() {
          _score = null;
          _spoken = null;
          _liveText = '';
        });
      }
    });
  }

  void _finishSession() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text('Unidade concluída!', style: TextStyle(color: AppTheme.textMainDark)),
        content: const Text('Você praticou todo o vocabulário desta unidade.', style: TextStyle(color: AppTheme.textSubDark)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Voltar ao início'),
          ),
        ],
      ),
    );
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
                              if (_liveText.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              if (_score != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(_verdictText(_score!),
                                      style: TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: ringColor)),
                                ),
                            ],
                          ),
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
                            GestureDetector(
                              onTap: _listening ? _stopRecording : _record,
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
                if (_overlay != _Overlay.none) _VpcResultOverlay(kind: _overlay, score: _score ?? 0, spoken: _spoken),
              ],
            ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}

class _VpcResultOverlay extends StatelessWidget {
  final _Overlay kind;
  final int score;
  final String? spoken;
  const _VpcResultOverlay({required this.kind, required this.score, required this.spoken});

  @override
  Widget build(BuildContext context) {
    final success = kind == _Overlay.celebrate;
    final icon = success ? (score == 100 ? '🏆' : (score >= 90 ? '🌟' : '🎉')) : '✕';
    final title = success ? 'Correto!' : '✕';
    final sub = success ? (score == 100 ? 'Pronúncia perfeita!' : (score >= 90 ? 'Excelente pronúncia!' : 'Muito bem!')) : 'Tente novamente';
    final color = success ? AppTheme.green : AppTheme.red;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 10),
                Text(title, style: TextStyle(fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 6),
                Text(sub, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
                if (!success && spoken != null && spoken!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Você disse: "$spoken"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Sora', fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSubDark)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
