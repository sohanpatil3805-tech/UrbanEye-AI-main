import 'dart:math';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Helper to get consistent severity colors matching the UrbanEye palette.
Color severityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return const Color(0xFFEF4444);
    case 'high':
      return const Color(0xFFF97316);
    case 'medium':
      return const Color(0xFFF59E0B);
    case 'low':
      return const Color(0xFF10B981);
    default:
      return const Color(0xFF3B82F6);
  }
}

/// Helper to get a softer background tint for severity chips.
Color severityBackgroundColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return const Color(0xFFFFE4E6);
    case 'high':
      return const Color(0xFFFFEDD5);
    case 'medium':
      return const Color(0xFFFEF3C7);
    case 'low':
      return const Color(0xFFDCFCE7);
    default:
      return const Color(0xFFDBEAFE);
  }
}

/// A CustomPainter widget that overlays YOLO bounding boxes onto the captured photo.
class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    required this.detections,
    required this.imageSize,
    this.fit = BoxFit.contain,
    super.key,
  });

  final List<RoadDamageDetection> detections;
  final Size? imageSize;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty || imageSize == null) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: _BoundingBoxPainter(
        detections: detections,
        originalImageSize: imageSize!,
        fit: fit,
      ),
      size: Size.infinite,
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  const _BoundingBoxPainter({
    required this.detections,
    required this.originalImageSize,
    required this.fit,
  });

  final List<RoadDamageDetection> detections;
  final Size originalImageSize;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (originalImageSize.width <= 0 ||
        originalImageSize.height <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final double scaleX = size.width / originalImageSize.width;
    final double scaleY = size.height / originalImageSize.height;

    double scale;
    double offsetX;
    double offsetY;

    if (fit == BoxFit.cover) {
      scale = max(scaleX, scaleY);
      final double renderedWidth = originalImageSize.width * scale;
      final double renderedHeight = originalImageSize.height * scale;
      offsetX = (size.width - renderedWidth) / 2;
      offsetY = (size.height - renderedHeight) / 2;
    } else {
      // Default: BoxFit.contain
      scale = min(scaleX, scaleY);
      final double renderedWidth = originalImageSize.width * scale;
      final double renderedHeight = originalImageSize.height * scale;
      offsetX = (size.width - renderedWidth) / 2;
      offsetY = (size.height - renderedHeight) / 2;
    }

    for (final detection in detections) {
      if (detection.bbox.length < 4) {
        continue;
      }

      final double left = offsetX + (detection.bbox[0] * scale);
      final double top = offsetY + (detection.bbox[1] * scale);
      final double right = offsetX + (detection.bbox[2] * scale);
      final double bottom = offsetY + (detection.bbox[3] * scale);

      final rect = Rect.fromLTRB(left, top, right, bottom);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      final color = severityColor(detection.severity);

      // Semi-transparent box fill
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, fillPaint);

      // Solid box border
      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(rrect, borderPaint);

      // Label text
      final textSpan = TextSpan(
        text:
            '${detection.label} • ${detection.confidencePercentage} • ${detection.severity}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      const horizontalPadding = 7.0;
      const verticalPadding = 3.5;
      final labelWidth = textPainter.width + (horizontalPadding * 2);
      final labelHeight = textPainter.height + (verticalPadding * 2);

      // Place pill above box if room permits, otherwise inside top edge of box
      final double labelTop =
          (rect.top - labelHeight - 4) >= 0 ? rect.top - labelHeight - 4 : rect.top + 4;
      final double labelLeft = max(4.0, min(rect.left, size.width - labelWidth - 4));

      final labelRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight),
        const Radius.circular(4),
      );

      // Label background pill
      final labelBgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRRect(labelRRect, labelBgPaint);

      // Draw label text
      textPainter.paint(
        canvas,
        Offset(labelLeft + horizontalPadding, labelTop + verticalPadding),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.originalImageSize != originalImageSize ||
        oldDelegate.fit != fit;
  }
}
