import 'dart:ui';

enum HazardSeverity {
  critical('Critical'),
  high('High'),
  medium('Medium'),
  low('Low');

  const HazardSeverity(this.label);

  final String label;
}

class HazardDetection {
  const HazardDetection({
    required this.label,
    required this.confidence,
    required this.severity,
    required this.boundingBox,
  });

  final String label;
  final double confidence;
  final HazardSeverity severity;
  final BoundingBox boundingBox;

  factory HazardDetection.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final confidence = json['confidence'];
    final severityLabel = json['severity'];
    final boundingBox = json['bbox'];
    if (label is! String || label.trim().isEmpty) {
      throw const FormatException('Detection label is missing or invalid.');
    }
    if (confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw const FormatException('Detection confidence is invalid.');
    }

    final severity = switch (severityLabel) {
      'Critical' => HazardSeverity.critical,
      'High' => HazardSeverity.high,
      'Medium' => HazardSeverity.medium,
      'Low' => HazardSeverity.low,
      _ => throw const FormatException('Detection severity is invalid.'),
    };

    return HazardDetection(
      label: label.trim(),
      confidence: confidence.toDouble(),
      severity: severity,
      boundingBox: BoundingBox.fromJson(boundingBox),
    );
  }
}

/// Source-image coordinates returned by the detector as [left, top, right,
/// bottom].
class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  Rect scaledTo(Size size, {required Size sourceSize}) {
    return Rect.fromLTRB(
      left / sourceSize.width * size.width,
      top / sourceSize.height * size.height,
      right / sourceSize.width * size.width,
      bottom / sourceSize.height * size.height,
    );
  }

  factory BoundingBox.fromJson(Object? json) {
    if (json is! List ||
        json.length != 4 ||
        json.any((value) => value is! num)) {
      throw const FormatException('Detection bounding box is invalid.');
    }
    final values = json.cast<num>().map((value) => value.toDouble()).toList();
    if (values.any((value) => !value.isFinite) ||
        values[0] < 0 ||
        values[1] < 0 ||
        values[2] <= values[0] ||
        values[3] <= values[1]) {
      throw const FormatException('Detection bounding box is invalid.');
    }
    return BoundingBox(
      left: values[0],
      top: values[1],
      right: values[2],
      bottom: values[3],
    );
  }
}

class DetectionResult {
  DetectionResult({
    required List<HazardDetection> detections,
    required this.timestamp,
  }) : detections = List.unmodifiable(detections);

  final List<HazardDetection> detections;

  /// The local response receipt time; the backend provides no timestamp.
  final DateTime timestamp;

  factory DetectionResult.fromJson(
    Map<String, dynamic> json, {
    required DateTime timestamp,
  }) {
    final detections = json['detections'];
    if (json['status'] != 'success' || detections is! List) {
      throw const FormatException('Detection response is missing or invalid.');
    }

    return DetectionResult(
      detections: detections.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Detection entry is invalid.');
        }
        return HazardDetection.fromJson(entry);
      }).toList(),
      timestamp: timestamp,
    );
  }
}
