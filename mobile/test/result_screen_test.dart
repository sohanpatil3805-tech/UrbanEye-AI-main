import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:urbaneye_mobile/models/detection_result.dart';
import 'package:urbaneye_mobile/screens/result_screen.dart';
import 'package:urbaneye_mobile/widgets/urbaneye_design_system.dart';

final _timestamp = DateTime(2026, 9, 5, 14, 8, 9);
final Uint8List _photoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6Q'
  'AAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAALSURBVBhX'
  'Y2AAAgAABQABqtXIUQAAAABJRU5ErkJggg==',
);

void main() {
  test('parses every backend detection and retains its supplied severity', () {
    final result = DetectionResult.fromJson(
      _response(_backendDetections),
      timestamp: _timestamp,
    );

    expect(result.timestamp, _timestamp);
    expect(
      result.detections.map((detection) => detection.label),
      <String>[
        'Pothole',
        'Alligator Crack',
        'Longitudinal Crack',
        'Transverse Crack',
      ],
    );
    expect(
      result.detections.map((detection) => detection.confidence),
      <double>[0.93, 0.71, 0.45, 0.22],
    );
    expect(
      result.detections.map((detection) => detection.severity),
      HazardSeverity.values,
    );
    expect(result.detections.first.boundingBox.left, 0.05);
    expect(result.detections.first.boundingBox.bottom, 0.35);
    expect(
      const BoundingBox(
        left: 10,
        top: 20,
        right: 30,
        bottom: 40,
      ).scaledTo(
        const Size(200, 400),
        sourceSize: const Size(100, 200),
      ),
      const Rect.fromLTRB(20, 40, 60, 80),
    );
  });

  test('an explicitly empty detections array is a valid result', () {
    final result = DetectionResult.fromJson(
      _response(<Object?>[]),
      timestamp: _timestamp,
    );

    expect(result.detections, isEmpty);
  });

  final malformedResponses = <String, Map<String, dynamic>>{
    'failed status': <String, dynamic>{
      'status': 'error',
      'detections': <Object?>[],
    },
    'missing detections': <String, dynamic>{'status': 'success'},
    'null detections': _response(null),
    'detections is not an array': _response(<String, dynamic>{}),
    'non-object detection': _response(<Object?>[null]),
    'missing bounding box': _response(<Object?>[
      <String, dynamic>{..._backendDetections.first}..remove('bbox'),
    ]),
    'short bounding box': _response(<Object?>[
      <String, dynamic>{
        ..._backendDetections.first,
        'bbox': <num>[1, 2, 3]
      },
    ]),
    'inverted bounding box': _response(<Object?>[
      <String, dynamic>{
        ..._backendDetections.first,
        'bbox': <num>[30, 20, 10, 40]
      },
    ]),
    'blank label': _response(<Object?>[
      <String, dynamic>{..._backendDetections.first, 'label': '  '},
    ]),
    'non-numeric confidence': _response(<Object?>[
      <String, dynamic>{..._backendDetections.first, 'confidence': '0.93'},
    ]),
    'negative confidence': _response(<Object?>[
      <String, dynamic>{..._backendDetections.first, 'confidence': -0.1},
    ]),
    'confidence above one': _response(<Object?>[
      <String, dynamic>{..._backendDetections.first, 'confidence': 1.1},
    ]),
    'non-finite confidence': _response(<Object?>[
      <String, dynamic>{..._backendDetections.first, 'confidence': double.nan},
    ]),
    'unknown severity after a valid detection': _response(<Object?>[
      _backendDetections.first,
      <String, dynamic>{..._backendDetections.last, 'severity': 'Unknown'},
    ]),
  };
  for (final entry in malformedResponses.entries) {
    test('${entry.key} cannot become a false no-hazards result', () {
      expect(
        () => DetectionResult.fromJson(entry.value, timestamp: _timestamp),
        throwsFormatException,
      );
    });
  }

  testWidgets('shows the captured image, every detection, and report details',
      (tester) async {
    await _openResult(
      tester,
      result: DetectionResult.fromJson(
        _response(_backendDetections),
        timestamp: _timestamp,
      ),
      position: _position(),
    );

    expect(find.byType(GradientHeader), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, orderedEquals(_photoBytes));
    expect(find.text('Captured image unavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey('detection-bounding-box-overlay')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('detection-bounding-box-overlay')),
      ),
      tester.getSize(find.byType(Image)),
    );

    const expectedOverlayColors = <Color>[
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
    ];
    for (var index = 0; index < _backendDetections.length; index += 1) {
      final pillFinder = find.byKey(ValueKey('detection-overlay-label-$index'));
      expect(pillFinder, findsOneWidget);
      final pill = tester.widget<Container>(pillFinder);
      expect((pill.decoration as BoxDecoration).color,
          expectedOverlayColors[index]);
      expect(
        find.descendant(
          of: pillFinder,
          matching: find.text(
            '${_backendDetections[index]['label']} '
            '${((_backendDetections[index]['confidence'] as num) * 100).toStringAsFixed(1)}%',
          ),
        ),
        findsOneWidget,
      );
    }

    expect(
      find.text('Latitude: 12.345678\nLongitude: -76.123456'),
      findsOneWidget,
    );
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(ResultScreen)),
    );
    expect(
      find.textContaining(localizations.formatFullDate(_timestamp)),
      findsOneWidget,
    );
    expect(find.textContaining('14:08:09'), findsOneWidget);
    _expectGreenConfirmation(tester);

    for (final detection in _backendDetections) {
      final label = detection['label'] as String;
      await tester.scrollUntilVisible(find.text(label), 200);
      final card = find.ancestor(
        of: find.text(label),
        matching: find.byType(PrimaryCard),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.text(detection['severity'] as String),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            'Confidence: ${((detection['confidence'] as num) * 100).toStringAsFixed(1)}%',
          ),
        ),
        findsOneWidget,
      );
    }

    await tester.scrollUntilVisible(find.text('AI Recommendation'), 200);
    final recommendationCard =
        find.byKey(const ValueKey('ai-recommendation-card'));
    expect(recommendationCard, findsOneWidget);
    expect(
      find.descendant(
        of: recommendationCard,
        matching: find.text('Reduce speed immediately'),
      ),
      findsOneWidget,
    );
    expect(find.text('Report queued'), findsOneWidget);
    expect(find.text('Dashboard notified'), findsOneWidget);
    expect(
      find.descendant(
        of: recommendationCard,
        matching: find.byIcon(Icons.speed_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);

    expect(find.text('No hazards detected'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty results show no hazards while keeping image and metadata',
      (tester) async {
    await _openResult(
      tester,
      result: DetectionResult.fromJson(
        _response(<Object?>[]),
        timestamp: _timestamp,
      ),
      position: _position(),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('Latitude: 12.345678'), findsOneWidget);
    expect(find.textContaining('14:08:09'), findsOneWidget);
    _expectGreenConfirmation(tester);
    final noHazards = find.byKey(const ValueKey('no-hazards-image-message'));
    expect(noHazards, findsOneWidget);
    expect(find.text('No hazards detected'), findsOneWidget);
    expect(tester.getCenter(noHazards), tester.getCenter(find.byType(Image)));
    expect(find.textContaining('Confidence:'), findsNothing);
    expect(
      find.byKey(const ValueKey('detection-bounding-box-overlay')),
      findsNothing,
    );
    await tester.scrollUntilVisible(find.text('Road appears safe'), 200);
    final safeCard = tester.widget<PrimaryCard>(
      find.byKey(const ValueKey('ai-recommendation-card')),
    );
    expect(safeCard.color, const Color(0xFFF0FDF4));
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommendations use the highest-severity detection',
      (tester) async {
    await _openResult(
      tester,
      result: DetectionResult.fromJson(
        _response(<Map<String, dynamic>>[
          _detection(
            label: 'Pothole',
            confidence: 0.99,
            severity: 'Low',
          ),
          _detection(
            label: 'Alligator Crack',
            confidence: 0.72,
            severity: 'High',
          ),
        ]),
        timestamp: _timestamp,
      ),
    );

    await tester.scrollUntilVisible(find.text('AI Recommendation'), 200);
    expect(find.text('Drive cautiously'), findsOneWidget);
    expect(find.text('Road requires inspection'), findsOneWidget);
    expect(find.byIcon(Icons.directions_car_filled_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(find.text('Reduce speed immediately'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final crackLabel in ['Longitudinal Crack', 'Transverse Crack']) {
    testWidgets('$crackLabel recommends monitoring the road', (tester) async {
      await _openResult(
        tester,
        result: DetectionResult.fromJson(
          _response(<Map<String, dynamic>>[
            _detection(
              label: crackLabel,
              confidence: 0.86,
              severity: 'Critical',
            ),
          ]),
          timestamp: _timestamp,
        ),
      );

      await tester.scrollUntilVisible(find.text('AI Recommendation'), 200);
      expect(find.text('Monitor road condition'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a missing GPS fix shows an unavailable state', (tester) async {
    await _openResult(
      tester,
      result: DetectionResult(detections: const [], timestamp: _timestamp),
    );

    expect(find.text('GPS coordinates unavailable'), findsOneWidget);
    expect(find.textContaining('Latitude:'), findsNothing);
    expect(find.textContaining('Longitude:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'long results scroll without overflow in ${brightness.name} mode',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final detections = List<HazardDetection>.generate(
        30,
        (index) => HazardDetection(
          label: 'Hazard ${index + 1} with an extended road damage description',
          confidence: 0.84,
          severity: HazardSeverity.values[index % HazardSeverity.values.length],
          boundingBox: const BoundingBox(
            left: 0.1,
            top: 0.1,
            right: 0.2,
            bottom: 0.2,
          ),
        ),
      );
      await _openResult(
        tester,
        result: DetectionResult(detections: detections, timestamp: _timestamp),
        brightness: brightness,
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      _expectGreenConfirmation(tester);
      await tester.scrollUntilVisible(
        find.text(detections.last.label),
        400,
        maxScrolls: 50,
      );
      expect(find.text(detections.last.label).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        Theme.of(tester.element(find.byType(ResultScreen))).brightness,
        brightness,
      );
    });
  }
}

Map<String, dynamic> _response(Object? detections) => <String, dynamic>{
      'status': 'success',
      'filename': '20260905_140809_123456.jpg',
      'detections': detections,
    };

Map<String, dynamic> _detection({
  required String label,
  required double confidence,
  required String severity,
}) =>
    <String, dynamic>{
      'label': label,
      'confidence': confidence,
      'severity': severity,
      'bbox': <num>[0.1, 0.1, 0.9, 0.9],
    };

const _backendDetections = <Map<String, dynamic>>[
  <String, dynamic>{
    'label': 'Pothole',
    'confidence': 0.93,
    'severity': 'Critical',
    'bbox': <num>[0.05, 0.05, 0.40, 0.35],
  },
  <String, dynamic>{
    'label': 'Alligator Crack',
    'confidence': 0.71,
    'severity': 'High',
    'bbox': <num>[0.50, 0.10, 0.95, 0.40],
  },
  <String, dynamic>{
    'label': 'Longitudinal Crack',
    'confidence': 0.45,
    'severity': 'Medium',
    'bbox': <num>[0.10, 0.50, 0.45, 0.90],
  },
  <String, dynamic>{
    'label': 'Transverse Crack',
    'confidence': 0.22,
    'severity': 'Low',
    'bbox': <num>[0.55, 0.55, 0.95, 0.95],
  },
];

Future<void> _openResult(
  WidgetTester tester, {
  required DetectionResult result,
  Position? position,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: ResultScreen(
        photoBytes: _photoBytes,
        result: result,
        position: position,
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Native image decoding completes outside the widget-test frame loop.
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  await tester.pumpAndSettle();
}

void _expectGreenConfirmation(WidgetTester tester) {
  final confirmation = find.text('Reported to Dashboard');
  expect(confirmation, findsOneWidget);
  final text = tester.widget<Text>(confirmation);
  final color = text.style?.color ??
      DefaultTextStyle.of(tester.element(confirmation)).style.color;
  expect(color, isNotNull);
  expect(color!.g, greaterThan(color.r));
  expect(color.g, greaterThan(color.b));
}

Position _position() => Position(
      latitude: 12.345678,
      longitude: -76.123456,
      timestamp: _timestamp,
      accuracy: 4.2,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
