import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Shared "unidade concluída" dialog shown by [VpcScreen] and
/// [DriveModeScreen] at the end of a practice session — dismisses itself
/// and pops back to the screen that opened it.
void showUnitCompleteDialog(BuildContext context, {required String message}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: Text(AppLocalizations.of(ctx)!.unitCompleteTitle, style: const TextStyle(color: AppTheme.textMainDark)),
      content: Text(message, style: const TextStyle(color: AppTheme.textSubDark)),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
          },
          child: Text(AppLocalizations.of(ctx)!.unitCompleteBackToStart),
        ),
      ],
    ),
  );
}
