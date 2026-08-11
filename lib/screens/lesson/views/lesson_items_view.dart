import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Shared card-list rendering for lesson item views ([PronuncLessonView],
/// [StrategyLessonView]) — same title/speak-button card, parametrized by
/// how each item maps to its title, speak text, and subtitle lines.
class LessonItemsView<T> extends StatelessWidget {
  final List<T> items;
  final void Function(String text) onSpeak;
  final String Function(T item) speakTextOf;
  final String Function(T item) titleOf;
  final List<Widget> Function(T item) subtitlesOf;

  const LessonItemsView({
    super.key,
    required this.items,
    required this.onSpeak,
    required this.speakTextOf,
    required this.titleOf,
    required this.subtitlesOf,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final it = items[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titleOf(it),
                        style: const TextStyle(
                            fontFamily: 'Sora', fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                    const SizedBox(height: 3),
                    ...subtitlesOf(it),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onSpeak(speakTextOf(it)),
                icon: const Icon(Icons.volume_up_rounded, color: AppTheme.accentBright),
              ),
            ],
          ),
        );
      },
    );
  }
}
