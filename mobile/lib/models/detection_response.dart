class Detection {
  const Detection({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.severity,
  });

  final String label;
  final double confidence;
  final List<double> boundingBox;
  final String severity;

  factory Detection.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('A detection must be an object.');
    }
    final bbox = value['bbox'];
    if (value['label'] is! String ||
        value['severity'] is! String ||
        value['confidence'] is! num ||
        bbox is! List ||
        bbox.length != 4 ||
        bbox.any((coordinate) => coordinate is! num)) {
      throw const FormatException('A detection has an invalid format.');
    }

    return Detection(
      label: value['label'] as String,
      confidence: (value['confidence'] as num).toDouble(),
      boundingBox: bbox.map((coordinate) => (coordinate as num).toDouble()).toList(growable: false),
      severity: value['severity'] as String,
    );
  }
}

class DetectionResponse {
  const DetectionResponse({
    required this.status,
    required this.filename,
    required this.detections,
  });

  final String status;
  final String filename;
  final List<Detection> detections;

  factory DetectionResponse.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['status'] is! String ||
        value['filename'] is! String ||
        value['detections'] is! List) {
      throw const FormatException('The detection response has an invalid format.');
    }

    final detections = <Detection>[];
    for (final value in value['detections'] as List) {
      try {
        detections.add(Detection.fromJson(value));
      } on FormatException {
        // A valid response can still contain an individual malformed detection.
        // Keep the usable detections rather than failing the entire analysis.
      }
    }

    return DetectionResponse(
      status: value['status'] as String,
      filename: value['filename'] as String,
      detections: List.unmodifiable(detections),
    );
  }
}

class DetectionUploadResult {
  const DetectionUploadResult._({this.response, this.errorMessage});

  const DetectionUploadResult.success(DetectionResponse response)
      : this._(response: response);

  const DetectionUploadResult.failure(String errorMessage)
      : this._(errorMessage: errorMessage);

  final DetectionResponse? response;
  final String? errorMessage;

  bool get isSuccess => response != null;
}
