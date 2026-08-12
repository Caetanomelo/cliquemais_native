import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  final List<VocabItem> items;
  final void Function(String text) onSpeak;
  const VocabLessonView({super.key, required this.unit, required this.items, required this.onSpeak});

  @override
  State<VocabLessonView> createState() => _VocabLessonViewState();
}

class _VocabLessonViewState extends State<VocabLessonView> {
  int _index = 0;

  VocabItem get _current => widget.items[_index];

  void _go(int i) {
    if (i < 0 || i >= widget.items.length) return;
    setState(() => _index = i);
    widget.onSpeak(widget.items[i].en);
  }

  Future<void> _testPronunciation() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VpcScreen(units: [widget.unit], startIndex: _index),
    ));
  }

  Future<void> _practiceAll() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VpcScreen(units: [widget.unit])));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppStateProvider>();
    final total = widget.items.length;
    final item = _current;
    final emoji = app.unitData.emojiFor(item.en) ?? '📝';

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
