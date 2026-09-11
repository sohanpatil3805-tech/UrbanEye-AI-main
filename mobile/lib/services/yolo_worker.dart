import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import '../models/live_detection.dart';

class InferenceResult {
  const InferenceResult(this.detections, this.inferenceMs, this.maxConfidence,
      {this.preview});
  final List<LiveDetection> detections;
  final double inferenceMs, maxConfidence;
  final Uint8List? preview;
}

/// Owns a persistent isolate: conversion, inference and NMS never run on the UI.
class YoloWorker {
  Isolate? _isolate;
  ReceivePort? _responses;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _commands;
  Completer<Object>? _pending;
  Completer<void>? _closed;

  Future<void> initialize() async {
    if (_isolate != null) return;
    final bytes = await rootBundle.load('assets/models/best.tflite');
    final ready = Completer<void>();
    _responses = ReceivePort();
    _subscription = _responses!.listen((dynamic message) {
      if (message is SendPort) {
        _commands = message;
        ready.complete();
      } else if (message == 'closed') {
        if (_closed?.isCompleted == false) _closed!.complete();
      } else if (message is InferenceResult || message is Uint8List) {
        _pending?.complete(message);
        _pending = null;
      } else {
        final error = StateError('Local model failed: $message');
        if (!ready.isCompleted) ready.completeError(error);
        _pending?.completeError(error);
        _pending = null;
      }
    });
    try {
      _isolate = await Isolate.spawn(
          _workerMain,
          (
            _responses!.sendPort,
            TransferableTypedData.fromList([
              bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
            ]),
          ),
          onError: _responses!.sendPort,
          errorsAreFatal: true);
      await ready.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<InferenceResult> detect(CameraImage image, int rotation) async {
    if (_commands == null || _pending != null) {
      throw StateError('Inference worker unavailable or busy');
    }
    final result = Completer<Object>();
    _pending = result;
    _commands!.send(CameraFrame(
      image.width,
      image.height,
      rotation,
      image.format.group == ImageFormatGroup.bgra8888,
      image.planes
          .map((p) => FramePlane(
                TransferableTypedData.fromList([p.bytes]),
                p.bytesPerRow,
                p.bytesPerPixel ?? 1,
              ))
          .toList(),
    ));
    return await result.future.timeout(const Duration(seconds: 5))
        as InferenceResult;
  }

  /// Called only after local confirmation, before the next frame is submitted.
  Future<Uint8List> encodeEvidence() async {
    if (_commands == null || _pending != null) throw StateError('Worker busy');
    final result = Completer<Object>();
    _pending = result;
    _commands!.send('jpeg');
    return await result.future.timeout(const Duration(seconds: 5)) as Uint8List;
  }

  Future<void> close() async {
    if (_commands != null) {
      _closed = Completer<void>();
      _commands!.send(null);
      try {
        await _closed!.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Kill only if native inference failed to finish and release normally.
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _pending?.completeError(StateError('Inference stopped'));
    _pending = null;
    await _subscription?.cancel();
    _responses?.close();
    _responses = null;
  }
}

class FramePlane {
  const FramePlane(this.data, this.rowStride, this.pixelStride);
  final TransferableTypedData data;
  final int rowStride;
  final int pixelStride;
}

class CameraFrame {
  const CameraFrame(
      this.width, this.height, this.rotation, this.bgra, this.planes);
  final int width, height, rotation;
  final bool bgra;
  final List<FramePlane> planes;
}

void _workerMain((SendPort, TransferableTypedData) args) {
  Interpreter? interpreter;
  final commands = ReceivePort();
  try {
    final options = InterpreterOptions()..threads = 3;
    interpreter = Interpreter.fromBuffer(args.$2.materialize().asUint8List(),
        options: options);
    options.delete();
    final input = interpreter.getInputTensor(0);
    final output = interpreter.getOutputTensor(0);
    if (input.type != TensorType.float32 ||
        input.shape.join(',') != '1,320,320,3' ||
        output.type != TensorType.float32 ||
        output.shape.length != 3 ||
        output.shape[0] != 1 ||
        output.shape[2] != 5) {
      throw StateError(
          'Expected float32 [1,320,320,3] -> [1,N,5] xyxy + score');
    }
    final buffer = Float32List(320 * 320 * 3);
    buffer.fillRange(0, buffer.length, 114 / 255);
    input.data = buffer.buffer.asUint8List();
    interpreter.invoke(); // Validate operators before reporting Model Loaded.
    CameraFrame? lastFrame;
    List<Uint8List>? lastPlanes;
    var frames = 0;
    args.$1.send(commands.sendPort);
    commands.listen((dynamic message) {
      if (message == null) {
        interpreter?.close();
        commands.close();
        args.$1.send('closed');
        return;
      }
      try {
        if (message == 'jpeg') {
          if (lastFrame == null) {
            throw StateError('No inference frame available');
          }
          args.$1.send(encodeFrameJpeg(lastFrame!, lastPlanes!));
          return;
        }
        final frame = message as CameraFrame;
        final planes = frame.planes
            .map((p) => p.data.materialize().asUint8List())
            .toList();
        prepareInput(frame, buffer, 320, planeBytes: planes);
        lastFrame = frame;
        lastPlanes = planes;
        input.data = buffer.buffer.asUint8List();
        final timer = Stopwatch()..start();
        interpreter!.invoke();
        timer.stop();
        final raw = output.data;
        final values =
            raw.buffer.asFloat32List(raw.offsetInBytes, raw.length ~/ 4);
        final uprightWidth =
            frame.rotation % 180 == 0 ? frame.width : frame.height;
        final uprightHeight =
            frame.rotation % 180 == 0 ? frame.height : frame.width;
        var maxConfidence = 0.0;
        for (var i = 4; i < values.length; i += 5) {
          if (values[i].isFinite) {
            maxConfidence = math.max(maxConfidence, values[i]);
          }
        }
        args.$1.send(InferenceResult(
          decodeDetections(values, uprightWidth, uprightHeight),
          timer.elapsedMicroseconds / 1000,
          maxConfidence,
          preview: frames++ % 30 == 0 ? encodeInputPreview(buffer) : null,
        ));
      } catch (error) {
        args.$1.send(error.toString());
      }
    });
  } catch (error) {
    interpreter?.close();
    commands.close();
    args.$1.send(error.toString());
  }
}

/// Fused stride-aware YUV/BGRA conversion, rotation and letterbox sampling.
/// No full-resolution RGB image or per-pixel objects are allocated.
void prepareInput(CameraFrame frame, Float32List target, int size,
    {List<Uint8List>? planeBytes}) {
  final planes = planeBytes ??
      frame.planes.map((p) => p.data.materialize().asUint8List()).toList();
  final width = frame.rotation % 180 == 0 ? frame.width : frame.height;
  final height = frame.rotation % 180 == 0 ? frame.height : frame.width;
  final scale = math.min(size / width, size / height);
  final padX = (size - width * scale) / 2;
  final padY = (size - height * scale) / 2;
  var index = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final ux = ((x - padX) / scale).floor();
      final uy = ((y - padY) / scale).floor();
      if (ux < 0 || uy < 0 || ux >= width || uy >= height) {
        target[index++] = 114 / 255;
        target[index++] = 114 / 255;
        target[index++] = 114 / 255;
        continue;
      }
      final (sx, sy) = switch (frame.rotation) {
        90 => (uy, frame.height - 1 - ux),
        180 => (frame.width - 1 - ux, frame.height - 1 - uy),
        270 => (frame.width - 1 - uy, ux),
        _ => (ux, uy),
      };
      if (frame.bgra) {
        final offset = sy * frame.planes[0].rowStride + sx * 4;
        target[index++] = planes[0][offset + 2] / 255;
        target[index++] = planes[0][offset + 1] / 255;
        target[index++] = planes[0][offset] / 255;
      } else {
        if (planes.length != 3) {
          throw StateError('Expected three YUV420 planes');
        }
        final yy = planes[0][sy * frame.planes[0].rowStride +
                sx * frame.planes[0].pixelStride]
            .toDouble();
        final u = planes[1][(sy ~/ 2) * frame.planes[1].rowStride +
                (sx ~/ 2) * frame.planes[1].pixelStride] -
            128;
        final v = planes[2][(sy ~/ 2) * frame.planes[2].rowStride +
                (sx ~/ 2) * frame.planes[2].pixelStride] -
            128;
        target[index++] = (yy + 1.402 * v).clamp(0, 255) / 255;
        target[index++] =
            (yy - 0.344136 * u - 0.714136 * v).clamp(0, 255) / 255;
        target[index++] = (yy + 1.772 * u).clamp(0, 255) / 255;
      }
    }
  }
}

List<LiveDetection> decodeDetections(Float32List values, int width, int height,
    {double threshold = 0.25}) {
  final scale = math.min(320 / width, 320 / height);
  final padX = (320 - width * scale) / 2;
  final padY = (320 - height * scale) / 2;
  final candidates = <LiveDetection>[];
  for (var i = 0; i + 4 < values.length; i += 5) {
    final score = values[i + 4];
    if (!score.isFinite ||
        score < threshold ||
        score > 1 ||
        !values[i].isFinite ||
        !values[i + 1].isFinite ||
        !values[i + 2].isFinite ||
        !values[i + 3].isFinite) {
      continue;
    }
    final box = <double>[
      ((values[i] * 320 - padX) / (width * scale)).clamp(0, 1).toDouble(),
      ((values[i + 1] * 320 - padY) / (height * scale)).clamp(0, 1).toDouble(),
      ((values[i + 2] * 320 - padX) / (width * scale)).clamp(0, 1).toDouble(),
      ((values[i + 3] * 320 - padY) / (height * scale)).clamp(0, 1).toDouble(),
    ];
    if (box.any((v) => !v.isFinite) || box[2] <= box[0] || box[3] <= box[1]) {
      continue;
    }
    candidates.add(LiveDetection(box, score));
  }
  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <LiveDetection>[];
  for (final detection in candidates.take(200)) {
    if (kept.every((other) => detection.iou(other) < 0.45)) kept.add(detection);
    if (kept.length == 20) break;
  }
  return kept;
}

Uint8List encodeInputPreview(Float32List input) {
  final image = img.Image(width: 320, height: 320, numChannels: 3);
  var i = 0;
  for (var y = 0; y < 320; y++) {
    for (var x = 0; x < 320; x++) {
      image.setPixelRgb(x, y, (input[i++] * 255).round(),
          (input[i++] * 255).round(), (input[i++] * 255).round());
    }
  }
  return img.encodeJpg(image, quality: 65);
}

/// Encode the corresponding upright camera frame in memory, with no file IO
/// and no extra camera capture (which would interrupt image streaming).
Uint8List encodeFrameJpeg(CameraFrame frame, List<Uint8List> planes) {
  final width = frame.rotation % 180 == 0 ? frame.width : frame.height;
  final height = frame.rotation % 180 == 0 ? frame.height : frame.width;
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (sx, sy) = switch (frame.rotation) {
        90 => (y, frame.height - 1 - x),
        180 => (frame.width - 1 - x, frame.height - 1 - y),
        270 => (frame.width - 1 - y, x),
        _ => (x, y),
      };
      if (frame.bgra) {
        final i = sy * frame.planes[0].rowStride + sx * 4;
        image.setPixelRgb(
            x, y, planes[0][i + 2], planes[0][i + 1], planes[0][i]);
      } else {
        if (planes.length != 3) {
          throw StateError('Expected three YUV420 planes');
        }
        final yy = planes[0]
            [sy * frame.planes[0].rowStride + sx * frame.planes[0].pixelStride];
        final u = planes[1][(sy ~/ 2) * frame.planes[1].rowStride +
                (sx ~/ 2) * frame.planes[1].pixelStride] -
            128;
        final v = planes[2][(sy ~/ 2) * frame.planes[2].rowStride +
                (sx ~/ 2) * frame.planes[2].pixelStride] -
            128;
        image.setPixelRgb(
            x,
            y,
            (yy + 1.402 * v).round().clamp(0, 255),
            (yy - .344136 * u - .714136 * v).round().clamp(0, 255),
            (yy + 1.772 * u).round().clamp(0, 255));
      }
    }
  }
  return img.encodeJpg(image, quality: 85);
}
