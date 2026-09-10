import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:urbaneye_mobile/screens/monitoring_screen.dart';
import 'package:urbaneye_mobile/services/monitoring_controller.dart';
import 'package:urbaneye_mobile/widgets/urbaneye_design_system.dart';

void main() {
  testWidgets('start and stop control the active indicator and live preview',
      (tester) async {
    final controller = _FakeMonitoringController();
    await _openMonitoring(tester, controller);

    expect(find.text('Ready to Monitor'), findsOneWidget);
    expect(find.text('Monitoring Active'), findsNothing);
    expect(find.byType(CameraPreview), findsNothing);
    expect(controller.startCalls, 0);
    expect(_startButton(tester).onPressed, isNotNull);
    expect(_stopButton(tester).onPressed, isNull);
    expect(find.byType(GradientHeader), findsOneWidget);
    expect(find.byType(PrimaryCard), findsWidgets);
    expect(Theme.of(tester.element(find.byType(MonitoringScreen))).useMaterial3,
        isTrue);

    await _tapControl(tester, 'Start Monitoring');

    expect(controller.startCalls, 1);
    expect(find.text('Monitoring Active'), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(tester.widget<CameraPreview>(find.byType(CameraPreview)).controller,
        same(controller.preview));
    expect(find.byKey(const ValueKey('live-camera-image')), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
    expect(_stopButton(tester).onPressed, isNotNull);

    await _tapControl(tester, 'Stop Monitoring');

    expect(controller.stopCalls, 1);
    expect(find.text('Monitoring Active'), findsNothing);
    expect(find.byType(CameraPreview), findsNothing);
    expect(find.text('Ready to Monitor'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNotNull);
    expect(_stopButton(tester).onPressed, isNull);
  });

  testWidgets(
      'stop remains available while starting and disables while stopping',
      (tester) async {
    final controller = _FakeMonitoringController()
      ..holdStart = true
      ..holdStop = true;
    await _openMonitoring(tester, controller);

    await _tapControl(tester, 'Start Monitoring', settle: false);
    expect(find.text('Starting Monitoring'), findsOneWidget);
    expect(find.text('Monitoring Active'), findsNothing);
    expect(_startButton(tester).onPressed, isNull);
    expect(_stopButton(tester).onPressed, isNotNull);

    await _tapControl(tester, 'Stop Monitoring', settle: false);
    expect(controller.stopCalls, 1);
    expect(find.text('Stopping Monitoring'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNull);
    expect(_stopButton(tester).onPressed, isNull);

    controller.finishStop();
    await tester.pumpAndSettle();
    expect(find.text('Ready to Monitor'), findsOneWidget);
    expect(_startButton(tester).onPressed, isNotNull);
  });

  testWidgets('camera errors are shown and Start Monitoring retries',
      (tester) async {
    final controller = _FakeMonitoringController()
      ..nextError = 'Allow camera access in Settings, then try again.';
    await _openMonitoring(tester, controller);

    await _tapControl(tester, 'Start Monitoring');
    expect(find.text('Monitoring Unavailable'), findsOneWidget);
    expect(find.text('Allow camera access in Settings, then try again.'),
        findsOneWidget);
    expect(find.text('Monitoring Active'), findsNothing);
    expect(find.byType(CameraPreview), findsNothing);
    expect(_startButton(tester).onPressed, isNotNull);
    expect(_stopButton(tester).onPressed, isNull);

    await _tapControl(tester, 'Start Monitoring');
    expect(controller.startCalls, 2);
    expect(find.text('Monitoring Active'), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(find.text('Allow camera access in Settings, then try again.'),
        findsNothing);
  });

  testWidgets(
      'backgrounding stops monitoring and resume waits for another start',
      (tester) async {
    final controller = _FakeMonitoringController();
    await _openMonitoring(tester, controller);
    await _tapControl(tester, 'Start Monitoring');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(controller.stopCalls, 1);
    expect(find.text('Monitoring Active'), findsNothing);
    expect(find.byType(CameraPreview), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.startCalls, 1);
    expect(find.text('Ready to Monitor'), findsOneWidget);

    await _tapControl(tester, 'Start Monitoring');
    expect(controller.startCalls, 2);
    expect(find.text('Monitoring Active'), findsOneWidget);
  });

  testWidgets('leaving the route stops the camera without disposing its owner',
      (tester) async {
    final controller = _FakeMonitoringController();
    await _openMonitoring(tester, controller);
    await _tapControl(tester, 'Start Monitoring');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open monitoring'), findsOneWidget);
    expect(controller.stopCalls, 1);
    expect(controller.state, MonitoringState.idle);
    expect(controller.wasDisposed, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'small ${brightness.name} screen keeps monitoring controls usable',
        (tester) async {
      final controller = _FakeMonitoringController();
      await _openMonitoring(
        tester,
        controller,
        size: const Size(320, 568),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      await _tapControl(tester, 'Start Monitoring');
      expect(find.text('Monitoring Active'), findsOneWidget);
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tapControl(tester, 'Stop Monitoring');
      expect(find.text('Ready to Monitor'), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.nextError = 'Allow camera access in Settings, then try again.';
      await _tapControl(tester, 'Start Monitoring');
      expect(find.text('Monitoring Unavailable'), findsOneWidget);
      expect(_startButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openMonitoring(
  WidgetTester tester,
  _FakeMonitoringController controller, {
  Size size = const Size(430, 932),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    await controller.preview.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: brightness),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => MonitoringScreen(controller: controller),
            )),
            child: const Text('Open monitoring'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open monitoring'));
  await tester.pumpAndSettle();
}

PrimaryButton _startButton(WidgetTester tester) => tester.widget<PrimaryButton>(
    find.widgetWithText(PrimaryButton, 'Start Monitoring'));

OutlinedButton _stopButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Stop Monitoring'));

Future<void> _tapControl(WidgetTester tester, String label,
    {bool settle = true}) async {
  final control = find.text(label);
  await tester.ensureVisible(control);
  await tester.tap(control);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _FakeMonitoringController extends MonitoringController {
  final preview = _PreviewCameraController();
  MonitoringState _state = MonitoringState.idle;
  String? _error;
  String? nextError;
  bool holdStart = false;
  bool holdStop = false;
  bool wasDisposed = false;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  MonitoringState get state => _state;

  @override
  CameraController? get cameraController =>
      _state == MonitoringState.active ? preview : null;

  @override
  String? get errorMessage => _error;

  @override
  Future<void> start() async {
    startCalls++;
    _error = nextError;
    nextError = null;
    _state = _error != null
        ? MonitoringState.error
        : holdStart
            ? MonitoringState.starting
            : MonitoringState.active;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _state = holdStop ? MonitoringState.stopping : MonitoringState.idle;
    notifyListeners();
  }

  void finishStop() {
    _state = MonitoringState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

class _PreviewCameraController extends CameraController {
  _PreviewCameraController()
      : super(
          const CameraDescription(
            name: 'Monitoring preview',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 0,
          ),
          ResolutionPreset.medium,
          enableAudio: false,
        ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  }

  @override
  Widget buildPreview() => const ColoredBox(
        key: ValueKey('live-camera-image'),
        color: Colors.black,
      );
}
