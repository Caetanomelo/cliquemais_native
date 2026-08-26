import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/completions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/dialogue_line.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/app_state_provider.dart';

/// unit/blockIndex are only known for curriculum lessons — CorpTrackDetailScreen
/// reuses this same widget for a corp track's dialogues, which aren't part of
/// the unit.lessons content_completions scheme (no matching content_id
/// convention), so they're left null there and no completion is recorded.
class ConvoLessonView extends StatefulWidget {
  final List<List<DialogueLine>> dialogues;
  final void Function(String text) onSpeak;
  final bool shrinkWrap;
  final int? unit;
  final int? blockIndex;
  const ConvoLessonView({
    super.key,
    required this.dialogues,
    required this.onSpeak,
    this.shrinkWrap = false,
    this.unit,
    this.blockIndex,
  });

  @override
  State<ConvoLessonView> createState() => _ConvoLessonViewState();
}

class _ConvoLessonViewState extends State<ConvoLessonView> {
  @override
  void initState() {
    super.initState();
    final unit = widget.unit;
    final blockIndex = widget.blockIndex;
    if (unit == null || blockIndex == null) return;
    final completions = context.read<AppStateProvider>().completions;
    // di indexes widget.dialogues directly — native's dialoguesFromJson
    // already concatenates dialogues+extraDialogues at parse time, unlike
    // web's renderConvo which does that concatenation itself (see its
    // comment on why convo's itemIdx isn't per-source-array).
    for (var di = 0; di < widget.dialogues.length; di++) {
      unawaited(completions.record(
        module: 'curriculum',
        contentId: CompletionsService.curriculumContentId(unit, 'convo', blockIndex, di),
        unit: unit,
        domain: 'fluency',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogues = widget.dialogues;
    final onSpeak = widget.onSpeak;
    final shrinkWrap = widget.shrinkWrap;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: dialogues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        final dialogue = dialogues[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in dialogue) _DialogueBubble(line: line, onSpeak: onSpeak),
            ],
          ),
        );
      },
    );
  }
}

class _DialogueBubble extends StatelessWidget {
  final DialogueLine line;
  final void Function(String) onSpeak;
  const _DialogueBubble({required this.line, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final isA = line.speaker == 'A';
    final color = isA ? AppTheme.accent : AppTheme.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isA ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${line.speaker}: ',
                          style: const TextStyle(
                              fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textSubDark)),
                      Flexible(
                        child: Text(line.text,
                            style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textMainDark)),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.volume_up_rounded, size: 16, color: AppTheme.accentBright),
                        onPressed: () => onSpeak(line.text),
                        tooltip: AppLocalizations.of(context)!.convoLessonListenTooltip,
                      ),
                    ],
                  ),
                  Text(line.pt,
                      style: const TextStyle(
                          fontFamily: 'Sora', fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSubDark)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
