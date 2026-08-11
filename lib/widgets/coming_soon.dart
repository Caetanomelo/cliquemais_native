import 'package:flutter/material.dart';

/// Shared "Em breve" snackbar shown by nav destinations/features not yet
/// implemented — was hand-duplicated at each call site.
void showComingSoonSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Em breve'), duration: Duration(seconds: 2)),
  );
}
