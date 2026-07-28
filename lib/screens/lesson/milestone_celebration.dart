import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/unit_curriculum_meta.dart';

/// Full-screen modal shown on completing a milestone unit (5/14/15/16 in the
/// source app): CEFR badge/trophy plus up to 4 "I can..." statements,
/// mirroring `showMilestoneCelebration`.
Future<void> showMilestoneCelebration(BuildContext context, UnitCurriculumMeta meta) {
  final statements = [
    ...meta.canDo.spoken,
    ...meta.canDo.listening,
    ...meta.canDo.reading,
    ...meta.canDo.writing,
  ].take(4).toList();

  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => _MilestoneDialog(meta: meta, statements: statements),
  );
}

class _MilestoneDialog extends StatefulWidget {
  final UnitCurriculumMeta meta;
  final List<String> statements;
  const _MilestoneDialog({required this.meta, required this.statements});

  @override
  State<_MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<_MilestoneDialog> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 1200));
    WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Dialog(
          backgroundColor: AppTheme.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppTheme.gold, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 12),
                Text('Marco ${widget.meta.cefr} alcançado!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Sora', fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.gold)),
                if (widget.meta.progression.milestoneLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(widget.meta.progression.milestoneLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
                ],
                const SizedBox(height: 20),
                for (final s in widget.statements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('✓  ', style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700)),
                        Expanded(
                          child: Text(s,
                              style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textMainDark)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Continuar'),
                  ),
                ),
              ],
            ),
          ),
        ),
        ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 90,
          maxBlastForce: 24,
          minBlastForce: 10,
          emissionFrequency: 0.05,
          gravity: 0.3,
          colors: const [AppTheme.gold, AppTheme.green, AppTheme.accentBright, Colors.white],
        ),
      ],
    );
  }
}
