import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/unit_curriculum_meta.dart';
import '../../l10n/app_localizations.dart';

/// Bottom sheet shown on completing a non-milestone unit: up to 3 "I can..."
/// statements, mirroring the source app's `showCanDoCard`.
Future<void> showCanDoCard(BuildContext context, UnitCurriculumMeta meta) {
  final statements = [
    ...meta.canDo.spoken,
    ...meta.canDo.listening,
    ...meta.canDo.reading,
    ...meta.canDo.writing,
  ].take(3).toList();

  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surfaceDark,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✅', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(AppLocalizations.of(ctx)!.canDoUnitCompleteTitle(meta.cefr),
                      style: const TextStyle(
                          fontFamily: 'Sora', fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(ctx)!.canDoNowYouCan,
                style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
            const SizedBox(height: 16),
            for (final s in statements)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(color: AppTheme.accentBright, fontWeight: FontWeight.w700)),
                    Expanded(
                      child: Text(s, style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textMainDark)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(ctx)!.canDoContinue),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
