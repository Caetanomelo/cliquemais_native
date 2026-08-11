import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shared "unidade concluída" dialog shown by [VpcScreen] and
/// [DriveModeScreen] at the end of a practice session — dismisses itself
/// and pops back to the screen that opened it.
void showUnitCompleteDialog(BuildContext context, {required String message}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: const Text('Unidade concluída!', style: TextStyle(color: AppTheme.textMainDark)),
      content: Text(message, style: const TextStyle(color: AppTheme.textSubDark)),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
          },
          child: const Text('Voltar ao início'),
        ),
      ],
    ),
  );
}
