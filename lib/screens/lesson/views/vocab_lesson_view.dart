import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/completions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/vocab_item.dart';
import '../../../providers/app_state_provider.dart';
import '../../vpc/vpc_screen.dart';

/// Single-word deck (web's `renderVocab` + `SwipeEngine`): one card at a
/// time with a progress bar, emoji/EN/PT, a "Testar pronúncia" mic button
/// that jumps straight into VPC already recording (`VPC.openAndRecord`),
/// Back/Next paging between words, and a "Praticar Pronúncia de Todas as
/// Palavras" button that opens the full VPC session for the unit.
class VocabLessonView extends StatefulWidget {
  final int unit;
  final int blockIndex;
  final List<VocabItem> items;
  final void Function(String text) onSpeak;
  const VocabLessonView({
    super.key,
    required this.unit,
    required this.blockIndex,
    required this.items,
    required this.onSpeak,
  });

  @override
  State<VocabLessonView> createState() => _VocabLessonViewState();
}

class _VocabLessonViewState extends State<VocabLessonView> {
  late final AppStateProvider _app;
  int _index = 0;
  // Fase 7: positions in widget.items that aren't already mastered — the
  // deck only shows these, but VPC/completions still need the item's real
  // position (content_id, VpcScreen.startIndex), so every place that used
  // to read _index against widget.items now goes through _indices[_index].
  // Falls back to every position if filtering would leave nothing to show
  // (same don't-strand-the-student rule as web's renderVocab).
  late List<int> _indices;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _indices = [
      for (var i = 0; i < widget.items.length; i++)
        if (!_app.completions.isCompleted(CompletionsService.curriculumContentId(widget.unit, 'vocab', widget.blockIndex, i))) i,
    ];
    if (_indices.isEmpty) _indices = [for (var i = 0; i < widget.items.length; i++) i];
    _reportCurrent(0);
  }

  VocabItem get _current => widget.items[_indices[_index]];

  void _go(int i) {
    if (i < 0 || i >= _indices.length) return;
    setState(() => _index = i);
    widget.onSpeak(widget.items[_indices[i]].en);
    _reportCurrent(i);
  }

  // Viewing the card is this lesson type's completion signal (mirrors
  // web's renderVocab — see its comment on why there's no flip step
  // anymore). Shares its content_id with VPC's pronunciation-lab entry for
  // the same word, so acing it there already covers this and vice-versa.
  void _reportCurrent(int i) {
    unawaited(_app.completions.record(
      module: 'curriculum',
      contentId: CompletionsService.curriculumContentId(widget.unit, 'vocab', widget.blockIndex, _indices[i]),
      unit: widget.unit,
      domain: 'vocabulary',
    ));
  }

  Future<void> _testPronunciation() async {
    // Direct tap on a specific word — never filtered, mirrors web's
    // VPC.openAndRecord (the student explicitly chose this exact word).
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VpcScreen(units: [widget.unit], startIndex: _indices[_index], filterCompleted: false),
    ));
  }

  Future<void> _practiceAll() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VpcScreen(units: [widget.unit])));
  }

  @override
  Widget build(BuildContext context) {
    final total = _indices.length;
    final item = _current;
    final emoji = _app.unitData.emojiFor(item.enBase) ?? '📝';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / total,
                    minHeight: 5,
                    backgroundColor: AppTheme.borderDark,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accentBright),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${_index + 1} / $total',
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSubDark)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 52)),
                  const SizedBox(height: 8),
                  Text(item.en,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Sora', fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                  const SizedBox(height: 4),
                  Text(item.pt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Sora', fontSize: 15, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, color: AppTheme.green)),
                  const SizedBox(height: 14),
                  IconButton(
                    onPressed: () => widget.onSpeak(item.en),
                    icon: const Icon(Icons.volume_up_rounded, color: AppTheme.gold, size: 28),
                    tooltip: 'Ouvir pronúncia',
                  ),
                  const SizedBox(height: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _testPronunciation,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.red.withValues(alpha: 0.4), width: 2),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🎙️', style: TextStyle(fontSize: 18)),
                            SizedBox(width: 8),
                            Text('Testar pronúncia',
                                style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.red)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _NavPill(top: 'BACK', arrow: '←', label: 'VOLTAR', enabled: _index > 0, onTap: () => _go(_index - 1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavPill(top: 'NEXT', arrow: '→', label: 'PRÓXIMO', enabled: _index < total - 1, onTap: () => _go(_index + 1)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.primaryButtonGradient, borderRadius: BorderRadius.circular(AppTheme.radiusBtn)),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
                  onTap: _practiceAll,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text('🎙️ Praticar Pronúncia de Todas as Palavras',
                          style: TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  final String top;
  final String arrow;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _NavPill({required this.top, required this.arrow, required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppTheme.textMainDark : AppTheme.textSubDark.withValues(alpha: 0.4);
    return Material(
      color: AppTheme.surfaceDark.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.radiusSm), border: Border.all(color: AppTheme.borderDark)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(top, style: TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              Text(arrow, style: TextStyle(fontSize: 16, color: color)),
              Text(label, style: TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
