import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';
import 'lesson_items_view.dart';

class PronuncLessonView extends StatelessWidget {
  final List<PronuncItem> items;
  final void Function(String text) onSpeak;
  const PronuncLessonView({super.key, required this.items, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return LessonItemsView<PronuncItem>(
      items: items,
      onSpeak: onSpeak,
      speakTextOf: (it) => it.word,
      titleOf: (it) => it.word,
      subtitlesOf: (it) => [
        Text(it.example, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.accentBright)),
        Text(it.rule, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
      ],
    );
  }
}
