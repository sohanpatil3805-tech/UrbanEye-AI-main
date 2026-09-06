import 'package:flutter/material.dart';

import '../models/detection_response.dart';

/// Paints backend image-space detections over an image displayed at its aspect ratio.
class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    required this.detections,
    required this.imageSize,
    super.key,
  });

  final List<Detection> detections;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty || imageSize.isEmpty) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _BoundingBoxPainter(detections: detections, imageSize: imageSize),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  const _BoundingBoxPainter({required this.detections, required this.imageSize});

  final List<Detection> detections;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final xScale = size.width / imageSize.width;
    final yScale = size.height / imageSize.height;
    final stroke = Paint()
      ..color = const Color(0xFF22C55E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final detection in detections) {
      final box = detection.boundingBox;
      final rect = Rect.fromLTRB(
        box[0] * xScale,
        box[1] * yScale,
        box[2] * xScale,
        box[3] * yScale,
      ).intersect(Offset.zero & size);
      if (rect.isEmpty) {
        continue;
      }
      canvas.drawRect(rect, stroke);

      final text = '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}% · ${detection.severity}';
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width - 8);
      final labelTop = (rect.top - painter.height - 6)
          .clamp(0.0, size.height - painter.height - 4)
          .toDouble();
      final labelLeft = rect.left
          .clamp(0.0, size.width - painter.width - 8)
          .toDouble();
      final labelRect = Rect.fromLTWH(
        labelLeft,
        labelTop,
        painter.width + 8,
        painter.height + 4,
      );
      canvas.drawRect(labelRect, Paint()..color = const Color(0xE610172A));
      painter.paint(canvas, labelRect.topLeft + const Offset(4, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) =>
      oldDelegate.detections != detections || oldDelegate.imageSize != imageSize;
}
