import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Shared "Em breve" snackbar shown by nav destinations/features not yet
/// implemented — was hand-duplicated at each call site.
void showComingSoonSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AppLocalizations.of(context)!.comingSoonMessage), duration: const Duration(seconds: 2)),
  );
}
