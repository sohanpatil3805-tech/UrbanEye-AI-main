import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/screens/camera_screen.dart';
import 'package:urbaneye_mobile/services/api_service.dart';
import 'package:urbaneye_mobile/widgets/bounding_box_overlay.dart';
import 'package:urbaneye_mobile/widgets/urbaneye_design_system.dart';

/// 1x1 transparent GIF bytes for testing Image.memory widgets
final Uint8List _testImageBytes = Uint8List.fromList(<int>[
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
  0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
  0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
]);

void main() {
  group('BoundingBoxOverlay & Severity Colors', () {
    test('severityColor maps each level to correct UrbanEye design palette', () {
      expect(severityColor('Critical'), const Color(0xFFEF4444));
      expect(severityColor('High'), const Color(0xFFF97316));
      expect(severityColor('Medium'), const Color(0xFFF59E0B));
      expect(severityColor('Low'), const Color(0xFF10B981));
      expect(severityColor('unknown'), const Color(0xFF3B82F6));
    });

    testWidgets('BoundingBoxOverlay paints without error for detections', (
      WidgetTester tester,
    ) async {
      const detections = [
        RoadDamageDetection(
          label: 'Pothole',
          confidence: 0.88,
          bbox: [10.0, 20.0, 100.0, 150.0],
          severity: 'Critical',
        ),
        RoadDamageDetection(
          label: 'Alligator Crack',
          confidence: 0.65,
          bbox: [120.0, 50.0, 300.0, 250.0],
          severity: 'High',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: Stack(
                children: [
                  Image.memory(_testImageBytes, fit: BoxFit.contain),
                  const BoundingBoxOverlay(
                    detections: detections,
                    imageSize: Size(640, 480),
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BoundingBoxOverlay), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('CameraScreen - Initial State & Capture Controls', () {
    testWidgets('Camera route shows live monitoring header and preview controls',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CameraScreen(),
        ),
      );

      // Verify header and initial preview mode
      expect(find.byType(GradientHeader), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(
        find.text('Front camera preview and capture controls.'),
        findsOneWidget,
      );
      expect(find.text('PREVIEW MODE'), findsOneWidget);
      expect(find.byTooltip('Capture'), findsOneWidget);
      expect(find.text('Flash'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
    });
  });
}
