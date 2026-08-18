import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/completions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';
import '../../../providers/app_state_provider.dart';

/// No per-item interaction exists for this lesson type (all rules render
/// at once, no quiz) — per the feature plan's design decision, being
/// displayed IS the completion signal, recorded once per rule in initState.
class GrammarLessonView extends StatefulWidget {
  final int unit;
  final int blockIndex;
  final GrammarLessonContent content;
  const GrammarLessonView({super.key, required this.unit, required this.blockIndex, required this.content});

  @override
  State<GrammarLessonView> createState() => _GrammarLessonViewState();
}

class _GrammarLessonViewState extends State<GrammarLessonView> {
  @override
  void initState() {
    super.initState();
    final completions = context.read<AppStateProvider>().completions;
    for (var ri = 0; ri < widget.content.rules.length; ri++) {
      unawaited(completions.record(
        module: 'curriculum',
        contentId: CompletionsService.curriculumContentId(widget.unit, 'grammar', widget.blockIndex, ri),
        unit: widget.unit,
        domain: 'comprehension',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
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
