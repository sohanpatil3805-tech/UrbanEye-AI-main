import 'package:flutter/material.dart';

import '../models/live_detection.dart';

/// Paint inside the same aspect-ratio rectangle as CameraPreview, so normalized
/// coordinates never include the surrounding black letterbox bars.
class DetectionPainter extends CustomPainter {
  const DetectionPainter(this.detections);
  final List<LiveDetection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final color = switch (detection.severity) {
        DetectionSeverity.low => Colors.greenAccent,
        DetectionSeverity.medium => Colors.yellow,
        DetectionSeverity.high => Colors.redAccent,
      };
      final rect = Rect.fromLTRB(
          detection.box[0] * size.width,
          detection.box[1] * size.height,
          detection.box[2] * size.width,
          detection.box[3] * size.height);
      canvas.drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
      final label = TextPainter(
        text: TextSpan(
            text:
                '${detection.label} ${(detection.confidence * 100).round()}% · ${detection.severity.name}',
            style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (size.width - 8).clamp(1, double.infinity));
      final left = rect.left
          .clamp(0.0, (size.width - label.width - 8).clamp(0, double.infinity))
          .toDouble();
      final top = (rect.top - label.height - 6)
          .clamp(
              0.0, (size.height - label.height - 6).clamp(0, double.infinity))
          .toDouble();
      canvas.drawRect(
          Rect.fromLTWH(left, top, label.width + 8, label.height + 6),
          Paint()..color = color);
      label.paint(canvas, Offset(left + 4, top + 3));
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) =>
      !identical(oldDelegate.detections, detections);
}
