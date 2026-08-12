import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliquemais_native/core/theme/app_theme.dart';
import 'package:cliquemais_native/widgets/speech_bubble.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child));

  testWidgets('shows the default hint text', (tester) async {
    await tester.pumpWidget(wrap(const SpeechBubble()));
    expect(find.text('Aperte para falar'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });

  testWidgets('shows custom text when provided', (tester) async {
    await tester.pumpWidget(wrap(const SpeechBubble(text: 'Grave sua resposta')));
    expect(find.text('Grave sua resposta'), findsOneWidget);
    expect(find.text('Aperte para falar'), findsNothing);
  });
}
