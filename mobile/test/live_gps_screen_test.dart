import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:urbaneye_mobile/screens/live_gps_screen.dart';
import 'package:urbaneye_mobile/services/location_service.dart';
import 'package:urbaneye_mobile/widgets/urbaneye_design_system.dart';

void main() {
  setUp(() => LocationStore.latestPosition = null);
  tearDown(() => LocationStore.latestPosition = null);

  testWidgets('Live GPS stays ready until tracking is started', (
    WidgetTester tester,
  ) async {
    final locationService = _FakeLocationService();

    await _openLiveGps(tester, locationService);

    expect(find.byType(GradientHeader), findsOneWidget);
    expect(find.byType(PrimaryCard), findsOneWidget);
    expect(find.text('READY'), findsNWidgets(2));
    expect(find.text('Waiting for a GPS fix'), findsOneWidget);
    expect(find.text('Not yet updated'), findsOneWidget);
    expect(find.text('Start Tracking'), findsOneWidget);
    expect(
      find.text('Start tracking to request location access.'),
      findsOneWidget,
    );
    expect(locationService.getCurrentPositionCalls, isZero);
  });

  testWidgets('granted access starts, refreshes, and stops tracking', (
    WidgetTester tester,
  ) async {
    final locationService = _FakeLocationService(
      permission: LocationPermission.denied,
      requestedPermission: LocationPermission.whileInUse,
      positions: <Position>[
        _position(latitude: 28.6139, longitude: 77.2090),
        _position(latitude: 28.6140, longitude: 77.2091),
      ],
    );

    await _openLiveGps(tester, locationService);

    await _tapTrackingControl(tester, 'Start Tracking');
    await tester.pumpAndSettle();

    expect(locationService.requestPermissionCalls, 1);
    expect(locationService.getCurrentPositionCalls, 1);
    expect(LocationStore.latestPosition?.latitude, 28.6139);
    expect(LocationStore.latestPosition?.longitude, 77.2090);
    expect(find.text('TRACKING'), findsNWidgets(2));
    expect(find.text('Stop Tracking'), findsOneWidget);
    expect(find.text('28.613900\u00b0 N, 77.209000\u00b0 E'), findsOneWidget);
    expect(find.text('4.2 m'), findsOneWidget);
    expect(find.text('45.0 km/h'), findsOneWidget);
    expect(find.text('Not yet updated'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(locationService.getCurrentPositionCalls, 2);
    expect(LocationStore.latestPosition?.latitude, 28.6140);
    expect(LocationStore.latestPosition?.longitude, 77.2091);
    expect(find.text('28.614000\u00b0 N, 77.209100\u00b0 E'), findsOneWidget);

    await _tapTrackingControl(tester, 'Stop Tracking');
    await tester.pump();

    expect(find.text('READY'), findsNWidgets(2));
    expect(find.text('Start Tracking'), findsOneWidget);

    final callsAfterStopping = locationService.getCurrentPositionCalls;
    await tester.pump(const Duration(seconds: 6));

    expect(locationService.getCurrentPositionCalls, callsAfterStopping);
    expect(LocationStore.latestPosition?.latitude, 28.6140);
  });

  testWidgets('disabled services and denied permission show actionable states',
      (
    WidgetTester tester,
  ) async {
    final disabledService = _FakeLocationService(locationServiceEnabled: false);

    await _openLiveGps(tester, disabledService);
    await _tapTrackingControl(tester, 'Start Tracking');
    await tester.pumpAndSettle();

    expect(find.text('GPS OFF'), findsNWidgets(2));
    expect(find.text('Location services are off'), findsOneWidget);
    expect(find.text('Open location settings'), findsOneWidget);
    expect(disabledService.requestPermissionCalls, isZero);
    expect(disabledService.getCurrentPositionCalls, isZero);

    final deniedService = _FakeLocationService(
      permission: LocationPermission.denied,
      requestedPermission: LocationPermission.denied,
    );

    await _openLiveGps(tester, deniedService);
    await _tapTrackingControl(tester, 'Start Tracking');
    await tester.pumpAndSettle();

    expect(find.text('ACTION NEEDED'), findsNWidgets(2));
    expect(find.text('Location permission denied'), findsOneWidget);
    expect(deniedService.requestPermissionCalls, 1);
    expect(deniedService.getCurrentPositionCalls, isZero);
  });

  testWidgets('back navigation disposes the active tracker', (
    WidgetTester tester,
  ) async {
    final locationService = _FakeLocationService();

    await _openLiveGps(tester, locationService);
    await _tapTrackingControl(tester, 'Start Tracking');
    await tester.pumpAndSettle();

    expect(locationService.getCurrentPositionCalls, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Driver dashboard'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));

    expect(locationService.getCurrentPositionCalls, 1);
  });
}

Future<void> _openLiveGps(
  WidgetTester tester,
  LocationService locationService,
) async {
  await tester.pumpWidget(
    _GpsTestApp(
      key: UniqueKey(),
      locationService: locationService,
    ),
  );
  await tester.tap(find.text('Open Live GPS'));
  await tester.pumpAndSettle();
}

Future<void> _tapTrackingControl(WidgetTester tester, String label) async {
  final control = find.text(label);
  await tester.scrollUntilVisible(control, 200);
  await tester.tap(control);
}

class _GpsTestApp extends StatelessWidget {
  const _GpsTestApp({required this.locationService, super.key});

  final LocationService locationService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Driver dashboard'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => LiveGpsScreen(
                            locationService: locationService,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Live GPS'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FakeLocationService implements LocationService {
  _FakeLocationService({
    this.locationServiceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    LocationPermission? requestedPermission,
    List<Position>? positions,
  })  : _requestedPermission = requestedPermission ?? permission,
        _positions = positions ?? <Position>[_position()];

  final bool locationServiceEnabled;
  LocationPermission permission;
  final LocationPermission _requestedPermission;
  final List<Position> _positions;

  int requestPermissionCalls = 0;
  int getCurrentPositionCalls = 0;
  int _positionIndex = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => locationServiceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls += 1;
    permission = _requestedPermission;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    getCurrentPositionCalls += 1;
    final index = _positionIndex < _positions.length
        ? _positionIndex
        : _positions.length - 1;
    _positionIndex += 1;
    return _positions[index];
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

Position _position({
  double latitude = 28.6139,
  double longitude = 77.2090,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2026, 9, 2, 12),
    accuracy: 4.2,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 12.5,
    speedAccuracy: 0,
  );
}
