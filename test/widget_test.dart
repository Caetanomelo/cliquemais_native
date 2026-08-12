import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliquemais_native/core/theme/app_theme.dart';

/// The original `flutter create` counter smoke test targeted the removed
/// boilerplate `MyApp`/counter widgets. Screens wired to a booted
/// AppStateProvider still need platform-channel mocks for
/// shared_preferences/speech_to_text/flutter_tts to test (out of scope
/// here — see scoring_service_test.dart, voice_command_service_test.dart,
/// persistence_service_test.dart for that logic's coverage, and
/// info_card_row_test.dart/speech_bubble_test.dart for widget tests that
/// don't need a provider). This keeps a trivial sanity check that the
/// widget-test harness itself still works.
void main() {
  testWidgets('AppTheme.dark builds a usable MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
  });
}
