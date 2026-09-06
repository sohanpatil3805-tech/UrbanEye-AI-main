import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/models/detection_response.dart';
import 'package:urbaneye_mobile/screens/camera_screen.dart';

const _transparentImage = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
  8, 215, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0,
  0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

Widget resultView(
  List<Detection> detections, {
  bool isAnalyzing = false,
  VoidCallback? onRetry,
  VoidCallback? onRetake,
}) => MaterialApp(
      home: DetectionResultView(
        photoBytes: Uint8List.fromList(_transparentImage),
        imageSize: const Size(100, 100),
        response: DetectionResponse(status: 'success', filename: 'road.jpg', detections: detections),
        isAnalyzing: isAnalyzing,
        onRetry: onRetry ?? () {},
        onRetake: onRetake ?? () {},
      ),
    );

void main() {
  testWidgets('shows clear state for empty detections', (tester) async {
    await tester.pumpWidget(resultView(const []));
    await tester.pump();

    expect(find.text('ROAD SURFACE CLEAR'), findsOneWidget);
    expect(find.text('Retry Analysis'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byTooltip('Back')).onPressed, isNotNull);
  });

  testWidgets('shows a successful result with multiple road issues and metadata', (tester) async {
    await tester.pumpWidget(resultView(const [
      Detection(label: 'Pothole', confidence: 0.91, boundingBox: [1, 2, 50, 60], severity: 'High'),
      Detection(label: 'Alligator Crack', confidence: 0.67, boundingBox: [20, 10, 80, 90], severity: 'Medium'),
    ]));
    await tester.pump();

    expect(find.text('2 road issues detected'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('91.0% confidence'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('MEDIUM'), findsOneWidget);
    expect(find.text('Retake / Scan Another'), findsOneWidget);
  });

  testWidgets('invokes retry and scan-another callbacks when idle', (tester) async {
    var retryCount = 0;
    var retakeCount = 0;

    await tester.pumpWidget(
      resultView(
        const [],
        onRetry: () => retryCount += 1,
        onRetake: () => retakeCount += 1,
      ),
    );

    await tester.tap(find.text('Retry Analysis'));
    await tester.tap(find.text('Retake / Scan Another'));

    expect(retryCount, 1);
    expect(retakeCount, 1);
  });

  testWidgets('shows analysis loading state and disables result actions', (tester) async {
    await tester.pumpWidget(resultView(const [], isAnalyzing: true));

    expect(find.text('Analyzing Road Damage...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(find.byTooltip('Back')).onPressed, isNull);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Retake / Scan Another')).onPressed,
      isNull,
    );
  });
}
