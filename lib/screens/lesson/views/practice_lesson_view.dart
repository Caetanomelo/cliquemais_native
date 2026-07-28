import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/lesson_content.dart';

enum _OptState { neutral, correct, wrong }

/// Tap-to-select quiz: single-attempt lock per question, +10 XP on correct.
/// Mirrors the source app's real completion rule — the lesson unlocks
/// "continue" on the first correct answer, not on answering every question.
class PracticeLessonView extends StatefulWidget {
  final List<PracticeQuestion> questions;
  final ValueChanged<bool> onCanCompleteChanged;
  final ValueChanged<int> onCorrectAnswer;
  const PracticeLessonView({
    super.key,
    required this.questions,
    required this.onCanCompleteChanged,
    required this.onCorrectAnswer,
  });

  @override
  State<PracticeLessonView> createState() => _PracticeLessonViewState();
}

class _PracticeLessonViewState extends State<PracticeLessonView> {
  final Map<int, int> _selected = {};
  bool _anyCorrect = false;

  void _select(int qIndex, int optIndex) {
    if (_selected.containsKey(qIndex)) return;
    setState(() => _selected[qIndex] = optIndex);
    if (optIndex == widget.questions[qIndex].correct) {
      widget.onCorrectAnswer(10);
      if (!_anyCorrect) {
        _anyCorrect = true;
        widget.onCanCompleteChanged(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widget.questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, qi) {
        final q = widget.questions[qi];
        final selected = _selected[qi];
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
              Text(q.q,
                  style: const TextStyle(
                      fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
              const SizedBox(height: 12),
              for (var oi = 0; oi < q.opts.length; oi++)
                _QuizOption(
                  text: q.opts[oi],
                  state: selected == null
                      ? _OptState.neutral
                      : (oi == q.correct ? _OptState.correct : (oi == selected ? _OptState.wrong : _OptState.neutral)),
                  onTap: () => _select(qi, oi),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QuizOption extends StatelessWidget {
  final String text;
  final _OptState state;
  final VoidCallback onTap;
  const _QuizOption({required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _OptState.correct => AppTheme.green,
      _OptState.wrong => AppTheme.red,
      _OptState.neutral => AppTheme.borderDark,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: state == _OptState.neutral ? Colors.transparent : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
            child: Text(text,
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 14,
                    color: state == _OptState.neutral ? AppTheme.textMainDark : color)),
          ),
        ),
      ),
    );
  }
}
