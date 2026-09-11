import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/live_detection.dart';

/// Owns a persistent isolate: conversion, inference and NMS never run on the UI.
class YoloWorker {
  Isolate? _isolate;
  ReceivePort? _responses;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _commands;
  Completer<List<LiveDetection>>? _pending;
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
      } else if (message is List<LiveDetection>) {
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
            TransferableTypedData.fromList([bytes.buffer.asUint8List()]),
          ),
          onError: _responses!.sendPort,
          errorsAreFatal: true);
      await ready.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<List<LiveDetection>> detect(CameraImage image, int rotation) async {
    if (_commands == null || _pending != null) {
      throw StateError('Inference worker unavailable or busy');
    }
    final result = Completer<List<LiveDetection>>();
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
    return result.future.timeout(const Duration(seconds: 5));
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
    args.$1.send(commands.sendPort);
    commands.listen((dynamic message) {
      if (message == null) {
        interpreter?.close();
        commands.close();
        args.$1.send('closed');
        return;
      }
      try {
        final frame = message as CameraFrame;
        prepareInput(frame, buffer, 320);
        input.data = buffer.buffer.asUint8List();
        interpreter!.invoke();
        final raw = output.data;
        final values =
            raw.buffer.asFloat32List(raw.offsetInBytes, raw.length ~/ 4);
        final uprightWidth =
            frame.rotation % 180 == 0 ? frame.width : frame.height;
        final uprightHeight =
            frame.rotation % 180 == 0 ? frame.height : frame.width;
        args.$1.send(decodeDetections(values, uprightWidth, uprightHeight));
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
void prepareInput(CameraFrame frame, Float32List target, int size) {
  final planes =
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

List<LiveDetection> decodeDetections(
    Float32List values, int width, int height) {
  final scale = math.min(320 / width, 320 / height);
  final padX = (320 - width * scale) / 2;
  final padY = (320 - height * scale) / 2;
  final candidates = <LiveDetection>[];
  for (var i = 0; i + 4 < values.length; i += 5) {
    final score = values[i + 4];
    if (!score.isFinite || score < 0.5 || score > 1) continue;
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
