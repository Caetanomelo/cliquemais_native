import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliquemais_native/core/theme/app_theme.dart';

/// The original `flutter create` counter smoke test targeted the removed
/// boilerplate `MyApp`/counter widgets. Full-app widget tests need
/// platform-channel mocks for shared_preferences/speech_to_text/flutter_tts,
/// which is out of scope for Phase 1 (see scoring_service_test.dart,
/// voice_command_service_test.dart, persistence_service_test.dart for the
/// logic that actually needs coverage). This keeps a trivial sanity check
/// that the widget-test harness itself still works.
void main() {
  testWidgets('AppTheme.dark builds a usable MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
  });
}
