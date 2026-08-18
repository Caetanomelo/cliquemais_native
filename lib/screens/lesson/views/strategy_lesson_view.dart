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
class StrategyLessonView extends StatefulWidget {
  final int unit;
  final int blockIndex;
  final List<StrategyItem> items;
  final void Function(String text) onSpeak;
  const StrategyLessonView({
    super.key,
    required this.unit,
    required this.blockIndex,
    required this.items,
    required this.onSpeak,
  });

  @override
  State<StrategyLessonView> createState() => _StrategyLessonViewState();
}

class _StrategyLessonViewState extends State<StrategyLessonView> {
  @override
  void initState() {
    super.initState();
    final completions = context.read<AppStateProvider>().completions;
    for (var ii = 0; ii < widget.items.length; ii++) {
      unawaited(completions.record(
        module: 'curriculum',
        contentId: CompletionsService.curriculumContentId(widget.unit, 'strategy', widget.blockIndex, ii),
        unit: widget.unit,
        domain: 'comprehension',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LessonItemsView<StrategyItem>(
      items: widget.items,
      onSpeak: widget.onSpeak,
      speakTextOf: (it) => it.phrase,
      titleOf: (it) => it.phrase,
      subtitlesOf: (it) => [
        Text(it.meaning, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
      ],
    );
  }
}
