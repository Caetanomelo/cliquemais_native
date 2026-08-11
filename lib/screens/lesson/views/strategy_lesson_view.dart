import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';
import 'lesson_items_view.dart';

class StrategyLessonView extends StatelessWidget {
  final List<StrategyItem> items;
  final void Function(String text) onSpeak;
  const StrategyLessonView({super.key, required this.items, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return LessonItemsView<StrategyItem>(
      items: items,
      onSpeak: onSpeak,
      speakTextOf: (it) => it.phrase,
      titleOf: (it) => it.phrase,
      subtitlesOf: (it) => [
        Text(it.meaning, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
      ],
    );
  }
}
