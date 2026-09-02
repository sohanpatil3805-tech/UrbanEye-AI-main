import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:urbaneye_mobile/main.dart';
import 'package:urbaneye_mobile/widgets/urbaneye_design_system.dart';

Future<void> _openProfile(WidgetTester tester) async {
  await tester.pumpWidget(const UrbanEyeApp());

  await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
  await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
  await tester.tap(find.text('Login'));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();

  await tester.tap(find.bySemanticsLabel('Open profile'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Profile route shows the driver settings dashboard', (
    WidgetTester tester,
  ) async {
    await _openProfile(tester);

    expect(find.byType(GradientHeader), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('Driver ID'), findsOneWidget);
    expect(find.text('UE-DR-1024'), findsOneWidget);
    expect(find.text('Assigned Bus'), findsOneWidget);
    expect(find.text('UE-1024'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Route updates'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('App Version'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });

  testWidgets('Route updates notification setting can be toggled', (
    WidgetTester tester,
  ) async {
    await _openProfile(tester);

    final routeUpdatesTile = find.ancestor(
      of: find.text('Route updates'),
      matching: find.byType(SwitchListTile),
    );
    final routeUpdatesSwitch = find.descendant(
      of: routeUpdatesTile,
      matching: find.byType(Switch),
    );

    expect(routeUpdatesTile, findsOneWidget);
    expect(routeUpdatesSwitch, findsOneWidget);
    final initialValue = tester.widget<Switch>(routeUpdatesSwitch).value;

    await tester.scrollUntilVisible(routeUpdatesSwitch, 200);
    await tester.tap(routeUpdatesSwitch);
    await tester.pumpAndSettle();

    expect(
      tester.widget<Switch>(routeUpdatesSwitch).value,
      isNot(initialValue),
    );
  });

  testWidgets('Profile back navigation returns to the driver dashboard', (
    WidgetTester tester,
  ) async {
    await _openProfile(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Good afternoon, Alex Morgan'), findsOneWidget);
  });
}
