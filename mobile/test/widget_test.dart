import 'package:flutter_test/flutter_test.dart';

import 'package:urbaneye_mobile/main.dart';
import 'package:urbaneye_mobile/screens/camera_screen.dart';
import 'package:urbaneye_mobile/screens/monitoring_screen.dart';
import 'package:urbaneye_mobile/widgets/urbaneye_design_system.dart';

void main() {
  testWidgets('Start Monitoring opens monitoring and returns to the dashboard',
      (tester) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start Monitoring'), 200);
    await tester.tap(find.text('Start Monitoring'));
    await tester.pumpAndSettle();
    expect(find.byType(MonitoringScreen), findsOneWidget);
    expect(find.text('Ready to Monitor'), findsOneWidget);
    expect(find.text('Stop Monitoring'), findsOneWidget);
    expect(find.byType(CameraScreen), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MonitoringScreen), findsNothing);
    expect(find.text('Start Monitoring'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login validates empty email and password', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());

    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('valid credentials navigate to the driver dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());

    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Good afternoon, Alex Morgan'), findsOneWidget);
    expect(find.text('Vehicle Online'), findsOneWidget);
    expect(find.text('GPS Ready'), findsOneWidget);
    expect(find.text('Camera Ready'), findsOneWidget);
    expect(find.text('0 Active Alerts'), findsOneWidget);
    expect(find.text('Start Monitoring'), findsOneWidget);
  });

  testWidgets('GPS readiness card keeps the existing navigation route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GPS Ready'));
    await tester.pumpAndSettle();

    expect(find.text('Live GPS'), findsOneWidget);
  });

  testWidgets('Live GPS route shows the tracking dashboard and returns home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GPS Ready'));
    await tester.pumpAndSettle();

    expect(find.byType(GradientHeader), findsOneWidget);
    expect(find.byType(StatusChip), findsNWidgets(2));
    expect(find.byType(PrimaryCard), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);
    expect(find.text('Live GPS'), findsOneWidget);
    expect(find.text('READY'), findsNWidgets(2));
    expect(find.text('Waiting for a GPS fix'), findsOneWidget);
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(2));
    expect(find.text('Last updated'), findsOneWidget);
    expect(find.text('Not yet updated'), findsOneWidget);
    expect(find.text('Start Tracking'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('GPS Ready'), findsOneWidget);
  });

  testWidgets('camera readiness card keeps the existing navigation route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Camera Ready'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('Camera route handles an unavailable camera and returns home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Camera Ready'));
    await tester.pumpAndSettle();

    expect(find.byType(CameraScreen), findsOneWidget);
    expect(find.byType(GradientHeader), findsOneWidget);
    expect(find.byType(PrimaryCard), findsOneWidget);
    expect(find.byType(StatusChip), findsNWidgets(2));
    expect(find.text('Camera'), findsOneWidget);
    expect(
      find.text('Front camera preview and capture controls.'),
      findsOneWidget,
    );
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(
      find.text(
          'Check that a camera is available and not in use by another app.'),
      findsOneWidget,
    );
    expect(find.text('PREVIEW MODE'), findsOneWidget);
    expect(find.byTooltip('Camera unavailable'), findsOneWidget);
    expect(find.text('Flash'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(
      find.text(
          'Select an image from Gallery, or resolve camera access above.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Camera Ready'), findsOneWidget);
  });

  testWidgets('active alerts card opens the Notifications dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0 Active Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Bus arriving soon'), findsOneWidget);
    expect(find.text('Route update'), findsOneWidget);
    expect(find.text('Incident detected'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Attention'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Driver reminder'),
      200,
    );

    expect(find.text('Driver reminder'), findsOneWidget);
    expect(find.text('Reminder'), findsOneWidget);
    final driverReminderCard = find.ancestor(
      of: find.text('Driver reminder'),
      matching: find.byType(PrimaryCard),
    );
    expect(driverReminderCard, findsOneWidget);
    expect(
      find.descendant(
        of: driverReminderCard,
        matching: find.text('Dismiss'),
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('0 Active Alerts'), findsOneWidget);
  });

  testWidgets('dismissing the bus arrival notification removes only that alert',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UrbanEyeApp());
    await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
    await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0 Active Alerts'));
    await tester.pumpAndSettle();

    final busArrivalCard = find.ancestor(
      of: find.text('Bus arriving soon'),
      matching: find.byType(PrimaryCard),
    );
    expect(busArrivalCard, findsOneWidget);

    await tester.tap(find.descendant(
      of: busArrivalCard,
      matching: find.text('Dismiss'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bus arriving soon'), findsNothing);
    expect(find.text('Route update'), findsOneWidget);
    expect(find.text('Incident detected'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Driver reminder'),
      200,
    );

    expect(find.text('Driver reminder'), findsOneWidget);
  });
}
