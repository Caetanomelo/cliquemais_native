import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';

class PronuncLessonView extends StatelessWidget {
  final List<PronuncItem> items;
  final void Function(String text) onSpeak;
  const PronuncLessonView({super.key, required this.items, required this.onSpeak});

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
                    Text(it.word,
                        style: const TextStyle(
                            fontFamily: 'Sora', fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                    const SizedBox(height: 3),
                    Text(it.example, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.accentBright)),
                    Text(it.rule, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onSpeak(it.word),
                icon: const Icon(Icons.volume_up_rounded, color: AppTheme.accentBright),
              ),
            ],
          ),
        );
      },
    );
  }
}
