import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../widgets/urbaneye_design_system.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _cameraDiscoveryTimeout = Duration(seconds: 3);

  CameraController? _cameraController;
  Uint8List? _capturedPhoto;
  _CameraUiState _cameraState = _CameraUiState.loading;
  bool _isCapturing = false;
  int _initializationToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_releaseCamera());
      return;
    }

    if (state == AppLifecycleState.resumed && _capturedPhoto == null) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationToken += 1;
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(_disposeController(controller));
    }
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final initializationToken = ++_initializationToken;
    final previousController = _cameraController;
    _cameraController = null;
    if (previousController != null) {
      await _disposeController(previousController);
    }

    if (!mounted || initializationToken != _initializationToken) {
      return;
    }

    setState(() {
      _cameraState = _CameraUiState.loading;
      _isCapturing = false;
    });

    try {
      final cameras = await availableCameras().timeout(_cameraDiscoveryTimeout);
      if (!mounted || initializationToken != _initializationToken) {
        return;
      }

      if (cameras.isEmpty) {
        _setCameraState(_CameraUiState.unavailable, initializationToken);
        return;
      }

      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );

      try {
        await controller.initialize();
      } on CameraException catch (error) {
        await _disposeController(controller);
        _setCameraState(
          _isPermissionError(error)
              ? _CameraUiState.permissionDenied
              : _CameraUiState.unavailable,
          initializationToken,
        );
        return;
      } catch (_) {
        await _disposeController(controller);
        _setCameraState(_CameraUiState.unavailable, initializationToken);
        return;
      }

      if (!mounted || initializationToken != _initializationToken) {
        await _disposeController(controller);
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraState = _CameraUiState.ready;
      });
    } on CameraException catch (error) {
      _setCameraState(
        _isPermissionError(error)
            ? _CameraUiState.permissionDenied
            : _CameraUiState.unavailable,
        initializationToken,
      );
    } catch (_) {
      _setCameraState(_CameraUiState.unavailable, initializationToken);
    }
  }

  Future<void> _releaseCamera() async {
    _initializationToken += 1;
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      await _disposeController(controller);
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final photo = await controller.takePicture();
      final photoBytes = await photo.readAsBytes();

      if (!mounted || controller != _cameraController) {
        return;
      }

      try {
        await controller.pausePreview();
      } catch (_) {
        // The image has already been captured, so retaining it is safe even
        // if a platform implementation cannot pause the live preview.
      }

      if (!mounted || controller != _cameraController) {
        return;
      }

      setState(() {
        _capturedPhoto = photoBytes;
        _isCapturing = false;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCapturing = false;
        _cameraState = _isPermissionError(error)
            ? _CameraUiState.permissionDenied
            : _CameraUiState.unavailable;
      });
      unawaited(_releaseCamera());
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCapturing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to capture a photo. Please try again.'),
        ),
      );
    }
  }

  Future<void> _retakePhoto() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _capturedPhoto = null;
    });

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _initializeCamera();
      return;
    }

    try {
      await controller.resumePreview();
    } catch (_) {
      await _initializeCamera();
    }
  }

  void _setCameraState(_CameraUiState state, int initializationToken) {
    if (!mounted || initializationToken != _initializationToken) {
      return;
    }

    setState(() {
      _cameraState = state;
      _isCapturing = false;
    });
  }

  static bool _isPermissionError(CameraException error) {
    return error.code.startsWith('CameraAccessDenied') ||
        error.code == 'CameraAccessRestricted';
  }

  static Future<void> _disposeController(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // A controller can already be disposed during a lifecycle transition.
    }
  }

  _HeaderStatus get _headerStatus {
    switch (_cameraState) {
      case _CameraUiState.ready:
        return const _HeaderStatus(
          label: 'LIVE',
          backgroundColor: Color(0xFFF0FDF4),
          foregroundColor: Color(0xFF15803D),
        );
      case _CameraUiState.loading:
        return const _HeaderStatus(
          label: 'STARTING',
          backgroundColor: Color(0xFFE0F2FE),
          foregroundColor: Color(0xFF0369A1),
        );
      case _CameraUiState.permissionDenied:
        return const _HeaderStatus(
          label: 'PERMISSION NEEDED',
          backgroundColor: Color(0xFFFFE4E6),
          foregroundColor: Color(0xFFBE123C),
        );
      case _CameraUiState.unavailable:
        return const _HeaderStatus(
          label: 'UNAVAILABLE',
          backgroundColor: Color(0xFFFFF7ED),
          foregroundColor: Color(0xFFB45309),
        );
    }
  }

  String get _footerText {
    if (_cameraState == _CameraUiState.ready) {
      return _isCapturing
          ? 'Capturing your photo...'
          : 'Frame your subject, then tap Capture. Flash and Gallery are unavailable for now.';
    }
    if (_cameraState == _CameraUiState.loading) {
      return 'Requesting camera access and preparing the live preview...';
    }
    return 'Resolve camera access above, then try again.';
  }

  @override
  Widget build(BuildContext context) {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto != null) {
      return _CapturedPhotoPreview(
        photoBytes: capturedPhoto,
        onRetake: () => unawaited(_retakePhoto()),
        onContinue: () => Navigator.of(context).maybePop(),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final headerStatus = _headerStatus;
    final isCameraReady = _cameraState == _CameraUiState.ready && !_isCapturing;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientHeader(
                eyebrow: 'URBANEYE AI  •  LIVE MONITORING',
                title: 'Camera',
                subtitle: 'Front camera preview and capture controls.',
                leading: _HeaderBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                footer: StatusChip(
                  label: headerStatus.label,
                  backgroundColor: headerStatus.backgroundColor,
                  foregroundColor: headerStatus.foregroundColor,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: PrimaryCard(
                  color: const Color(0xFF0F172A),
                  padding: EdgeInsets.zero,
                  child: _CameraSurface(
                    controller: _cameraController,
                    state: _cameraState,
                    onRetry: () => unawaited(_initializeCamera()),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const _DisabledToolButton(
                    icon: Icons.flash_on_rounded,
                    label: 'Flash',
                  ),
                  _CaptureButton(
                    isCapturing: _isCapturing,
                    onPressed:
                        isCameraReady ? () => unawaited(_capturePhoto()) : null,
                  ),
                  const _DisabledToolButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _footerText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBackButton extends StatelessWidget {
  const _HeaderBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x33FFFFFF),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Back',
        onPressed: onPressed,
        color: Colors.white,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    );
  }
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface({
    required this.controller,
    required this.state,
    required this.onRetry,
  });

  final CameraController? controller;
  final _CameraUiState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isLivePreview = state == _CameraUiState.ready &&
        controller?.value.isInitialized == true;

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF172554), Color(0xFF0F172A)],
            ),
          ),
        ),
        if (isLivePreview)
          _LiveCameraPreview(controller: controller!)
        else
          _CameraStateMessage(state: state, onRetry: onRetry),
        const Positioned(
          top: 20,
          right: 20,
          child: StatusChip(
            label: 'PREVIEW MODE',
            backgroundColor: Color(0x33FFFFFF),
            foregroundColor: Colors.white,
          ),
        ),
        Positioned(
          left: 20,
          bottom: 20,
          child: _RecordingFrameLabel(isLivePreview: isLivePreview),
        ),
      ],
    );
  }
}

class _LiveCameraPreview extends StatelessWidget {
  const _LiveCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _CameraStateMessage extends StatelessWidget {
  const _CameraStateMessage({required this.state, required this.onRetry});

  final _CameraUiState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == _CameraUiState.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Preparing camera...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0x332563EB),
                shape: BoxShape.circle,
              ),
              child: Icon(
                state == _CameraUiState.permissionDenied
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              state.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingFrameLabel extends StatelessWidget {
  const _RecordingFrameLabel({required this.isLivePreview});

  final bool isLivePreview;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isLivePreview
                ? const Color(0xFF22C55E)
                : const Color(0xFF94A3B8),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isLivePreview ? 'Live camera' : 'Camera standby',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.isCapturing, required this.onPressed});

  final bool isCapturing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Tooltip(
      message: isCapturing
          ? 'Capturing photo'
          : isEnabled
              ? 'Capture'
              : 'Camera unavailable',
      child: Semantics(
        button: true,
        enabled: isEnabled,
        label: isCapturing ? 'Capturing photo' : 'Capture',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Opacity(
              opacity: isEnabled || isCapturing ? 1 : 0.5,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFF2563EB),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCapturing
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisabledToolButton extends StatelessWidget {
  const _DisabledToolButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: '$label unavailable',
          onPressed: null,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            minimumSize: const Size(52, 52),
            disabledBackgroundColor: colorScheme.surfaceContainerHighest,
            disabledForegroundColor: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _CapturedPhotoPreview extends StatelessWidget {
  const _CapturedPhotoPreview({
    required this.photoBytes,
    required this.onRetake,
    required this.onContinue,
  });

  final Uint8List photoBytes;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(photoBytes, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x550F172A), Color(0xDD0F172A)],
                stops: [0.35, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(
                      label: 'PHOTO CAPTURED',
                      backgroundColor: Color(0xE6FFFFFF),
                      foregroundColor: Color(0xFF1D4ED8),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Review your photo',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This image is stored locally for preview only and has not been sent.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onRetake,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retake'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      side: const BorderSide(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: onContinue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStatus {
  const _HeaderStatus({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

enum _CameraUiState {
  loading,
  ready,
  permissionDenied,
  unavailable;

  String get title {
    switch (this) {
      case _CameraUiState.loading:
        return 'Preparing camera';
      case _CameraUiState.ready:
        return 'Camera preview';
      case _CameraUiState.permissionDenied:
        return 'Camera permission needed';
      case _CameraUiState.unavailable:
        return 'Camera unavailable';
    }
  }

  String get message {
    switch (this) {
      case _CameraUiState.loading:
        return 'Requesting access to the device camera.';
      case _CameraUiState.ready:
        return 'Your live camera feed is ready.';
      case _CameraUiState.permissionDenied:
        return 'Allow camera access in your device settings, then try again.';
      case _CameraUiState.unavailable:
        return 'Check that a camera is available and not in use by another app.';
    }
  }
}
