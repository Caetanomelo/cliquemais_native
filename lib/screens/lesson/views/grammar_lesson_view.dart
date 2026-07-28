import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';

class GrammarLessonView extends StatelessWidget {
  final GrammarLessonContent content;
  const GrammarLessonView({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (content.powerLogic.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
            ),
            child: Text(content.powerLogic,
                style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textMainDark, height: 1.4)),
          ),
        for (final rule in content.rules) ...[
          Text(rule.label,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accentBright)),
          const SizedBox(height: 8),
          for (final row in rule.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.sub, style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textMainDark)),
                  Text(row.pt, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
