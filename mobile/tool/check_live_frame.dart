// Host-side integration check: real image -> padded YUV420 camera planes ->
// production conversion -> real TFLite (Python) -> production decoding/filter.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:urbaneye_mobile/models/live_detection.dart';
import 'package:urbaneye_mobile/services/yolo_worker.dart';

void main() {
  test('real road frame passes the live YUV pipeline', () {
    const stage =
        String.fromEnvironment('LIVE_FRAME_STAGE', defaultValue: 'prepare');
    if (stage == 'decode') {
      final dimensions =
          jsonDecode(File('build/live-frame-size.json').readAsStringSync())
              as List;
      final raw = File('build/live-frame-output.bin').readAsBytesSync();
      final detections = decodeDetections(
          raw.buffer.asFloat32List(raw.offsetInBytes),
          dimensions[0] as int,
          dimensions[1] as int);
      expect(detections, isNotEmpty,
          reason: 'Real TFLite output must contain potholes');
      final filter = LiveConfirmationFilter();
      final now = DateTime.now();
      final confirmed = filter.update(detections, now);
      expect(confirmed, isNotEmpty);
      expect(
          filter.update(detections, now.add(const Duration(milliseconds: 100))),
          isEmpty);
      File('build/live-frame-result.json').writeAsStringSync(jsonEncode({
        'detections': detections.length,
        'confirmed': confirmed.length,
        'max_confidence': detections.first.confidence,
        'box': detections.first.box,
        'duplicate_confirmations': 0,
      }));
      return;
    }
    final source = img.bakeOrientation(img
        .decodeImage(File('build/live-frame-source.jpg').readAsBytesSync())!);
    final scale = math.min(640 / source.width, 640 / source.height);
    final upright = img.copyResize(source,
        width: ((source.width * scale).floor() ~/ 2) * 2,
        height: ((source.height * scale).floor() ~/ 2) * 2);
    final sensor = img.copyRotate(upright, angle: -90);
    final width = sensor.width, height = sensor.height;
    final yStride = width + 16, uvStride = width + 8;
    final planes = [
      Uint8List(yStride * height),
      Uint8List(uvStride * (height ~/ 2)),
      Uint8List(uvStride * (height ~/ 2))
    ];
    final bgra = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = sensor.getPixel(x, y);
        planes[0][y * yStride + x] =
            (.299 * p.r + .587 * p.g + .114 * p.b).round();
        final i = (y * width + x) * 4;
        bgra.setRange(i, i + 4, [p.b.toInt(), p.g.toInt(), p.r.toInt(), 255]);
      }
    }
    for (var y = 0; y < height; y += 2) {
      for (var x = 0; x < width; x += 2) {
        double u = 0, v = 0;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final p = sensor.getPixel(x + dx, y + dy);
            u += -.168736 * p.r - .331264 * p.g + .5 * p.b + 128;
            v += .5 * p.r - .418688 * p.g - .081312 * p.b + 128;
          }
        }
        final i = (y ~/ 2) * uvStride + x;
        planes[1][i] = (u / 4).round().clamp(0, 255);
        planes[2][i] = (v / 4).round().clamp(0, 255);
      }
    }
    final frame = CameraFrame(width, height, 90, false, [
      FramePlane(TransferableTypedData.fromList([planes[0]]), yStride, 1),
      FramePlane(TransferableTypedData.fromList([planes[1]]), uvStride, 2),
      FramePlane(TransferableTypedData.fromList([planes[2]]), uvStride, 2),
    ]);
    final input = Float32List(320 * 320 * 3);
    prepareInput(frame, input, 320, planeBytes: planes);
    final reference = Float32List(input.length);
    prepareInput(
        CameraFrame(width, height, 90, true, [
          FramePlane(TransferableTypedData.fromList([bgra]), width * 4, 4)
        ]),
        reference,
        320);
    var error = 0.0;
    for (var i = 0; i < input.length; i++) {
      error += (input[i] - reference[i]).abs();
    }
    error /= input.length;
    expect(error, lessThan(.025),
        reason: 'YUV conversion must preserve RGB colors and orientation');
    File('build/live-frame-input.bin')
        .writeAsBytesSync(input.buffer.asUint8List());
    File('build/live-frame-size.json')
        .writeAsStringSync(jsonEncode([upright.width, upright.height]));
    File('build/live-frame-evidence.jpg')
        .writeAsBytesSync(encodeFrameJpeg(frame, planes));
    File('build/live-frame-conversion.json')
        .writeAsStringSync(jsonEncode({'mean_rgb_error': error}));
  });
}
