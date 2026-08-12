import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/dialogue_line.dart';

class ConvoLessonView extends StatelessWidget {
  final List<List<DialogueLine>> dialogues;
  final void Function(String text) onSpeak;
  final bool shrinkWrap;
  const ConvoLessonView({
    super.key,
    required this.dialogues,
    required this.onSpeak,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
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
                        tooltip: 'Ouvir frase',
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
