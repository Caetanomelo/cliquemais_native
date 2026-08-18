import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/completions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';
import '../../../providers/app_state_provider.dart';
import 'lesson_items_view.dart';

/// No per-item interaction exists for this lesson type — being displayed
/// IS the completion signal, same reasoning as GrammarLessonView.
class PronuncLessonView extends StatefulWidget {
  final int unit;
  final int blockIndex;
  final List<PronuncItem> items;
  final void Function(String text) onSpeak;
  const PronuncLessonView({
    super.key,
    required this.unit,
    required this.blockIndex,
    required this.items,
    required this.onSpeak,
  });

  @override
  State<PronuncLessonView> createState() => _PronuncLessonViewState();
}

class _PronuncLessonViewState extends State<PronuncLessonView> {
  @override
  void initState() {
    super.initState();
    final completions = context.read<AppStateProvider>().completions;
    for (var ii = 0; ii < widget.items.length; ii++) {
      unawaited(completions.record(
        module: 'curriculum',
        contentId: CompletionsService.curriculumContentId(widget.unit, 'pronunc', widget.blockIndex, ii),
        unit: widget.unit,
        domain: 'pronunciation',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LessonItemsView<PronuncItem>(
      items: widget.items,
      onSpeak: widget.onSpeak,
      speakTextOf: (it) => it.word,
      titleOf: (it) => it.word,
      subtitlesOf: (it) => [
        Text(it.example, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.accentBright)),
        Text(it.rule, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
      ],
    );
  }
}
