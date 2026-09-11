import 'dart:math' as math;
import 'dart:ui';

enum DetectionSeverity { low, medium, high }

/// Coordinates are normalized [x1, y1, x2, y2] in the upright camera image.
class LiveDetection {
  const LiveDetection(this.box, this.confidence);

  final List<double> box;
  final double confidence;
  String get label => 'Pothole';
  Rect get rect => Rect.fromLTRB(box[0], box[1], box[2], box[3]);

  // Visual proximity/size heuristic, not a measurement of pothole depth.
  DetectionSeverity get severity {
    final area = rect.width * rect.height;
    return area >= 0.12
        ? DetectionSeverity.high
        : area >= 0.035
            ? DetectionSeverity.medium
            : DetectionSeverity.low;
  }

  double iou(LiveDetection other) {
    final intersection = rect.intersect(other.rect);
    final area =
        math.max(0.0, intersection.width) * math.max(0.0, intersection.height);
    final union =
        rect.width * rect.height + other.rect.width * other.rect.height - area;
    return union > 0 ? area / union : 0;
  }
}

/// Three consecutive matching observations confirm an incident. A track is
/// reported once, then retained briefly through occlusion to suppress repeats.
class DetectionTracker {
  final List<_Track> _tracks = [];

  List<LiveDetection> update(List<LiveDetection> detections, DateTime now) {
    _tracks.removeWhere((t) => now.difference(t.seen).inMilliseconds > 1500);
    final unmatched = _tracks.toSet();
    final confirmed = <LiveDetection>[];
    for (final detection in detections) {
      _Track? match;
      var best = 0.3;
      for (final track in unmatched) {
        final overlap = track.detection.iou(detection);
        if (overlap > best) {
          best = overlap;
          match = track;
        }
      }
      if (match == null) {
        match = _Track(detection, now);
        _tracks.add(match);
      } else {
        unmatched.remove(match);
        match.hits++;
        match
          ..detection = detection
          ..seen = now;
      }
      if (match.hits >= 3 && !match.reported) {
        match.reported = true;
        confirmed.add(detection);
      }
    }
    for (final missed in unmatched) {
      missed.hits = 0;
    }
    return confirmed;
  }

  void clear() => _tracks.clear();
}

/// Report a threshold crossing immediately, then suppress overlapping boxes
/// until they have been absent for [cooldown]. Continued visibility refreshes
/// the window, so a stationary test video cannot flood the backend.
class LiveConfirmationFilter {
  LiveConfirmationFilter(
      {this.threshold = 0.25,
      this.cooldown = const Duration(seconds: 10),
      this.iouThreshold = 0.3});
  final double threshold, iouThreshold;
  final Duration cooldown;
  final List<_Track> _recent = [];

  List<LiveDetection> update(List<LiveDetection> detections, DateTime now) {
    _recent.removeWhere((track) => now.difference(track.seen) > cooldown);
    final confirmed = <LiveDetection>[];
    for (final detection in detections) {
      if (!detection.confidence.isFinite || detection.confidence < threshold) {
        continue;
      }
      _Track? matched;
      var best = iouThreshold;
      for (final track in _recent) {
        final overlap = detection.iou(track.detection);
        if (overlap >= best) {
          matched = track;
          best = overlap;
        }
      }
      if (matched != null) {
        matched
          ..detection = detection
          ..seen = now;
      } else {
        confirmed.add(detection);
        _recent.add(_Track(detection, now));
      }
    }
    return confirmed;
  }

  void clear() => _recent.clear();
}

class _Track {
  _Track(this.detection, this.seen);
  LiveDetection detection;
  DateTime seen;
  int hits = 1;
  bool reported = false;
}
