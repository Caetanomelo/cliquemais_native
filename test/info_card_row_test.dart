import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliquemais_native/core/theme/app_theme.dart';
import 'package:cliquemais_native/widgets/info_card_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child));

  testWidgets('renders title, subtitle and leading icon', (tester) async {
    await tester.pumpWidget(wrap(InfoCardRow(
      leading: const Icon(Icons.call_rounded),
      title: 'Portal Corporativo',
      subtitle: '18 trilhas disponíveis',
      onTap: () {},
      decoration: AppTheme.glassCard(),
    )));

    expect(find.text('Portal Corporativo'), findsOneWidget);
    expect(find.text('18 trilhas disponíveis'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(InfoCardRow(
      leading: const Icon(Icons.call_rounded),
      title: 'Title',
      subtitle: 'Subtitle',
      onTap: () => tapped = true,
      decoration: AppTheme.glassCard(),
    )));

    await tester.tap(find.byType(InfoCardRow));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
