import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliquemais_native/core/theme/app_theme.dart';
import 'package:cliquemais_native/l10n/app_localizations.dart';
import 'package:cliquemais_native/widgets/speech_bubble.dart';

void main() {
  // SpeechBubble resolves its default hint text via AppLocalizations, so the
  // test harness needs the same delegates/locale wiring app.dart sets up —
  // pinned to 'pt' to match the literal strings this test asserts against.
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('shows the default hint text', (tester) async {
    await tester.pumpWidget(wrap(const SpeechBubble()));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Aperte para falar'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });

  testWidgets('shows custom text when provided', (tester) async {
    await tester.pumpWidget(wrap(const SpeechBubble(text: 'Grave sua resposta')));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Grave sua resposta'), findsOneWidget);
    expect(find.text('Aperte para falar'), findsNothing);
  });
}
