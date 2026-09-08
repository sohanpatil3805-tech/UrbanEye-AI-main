import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/bounding_box_overlay.dart';
import '../widgets/urbaneye_design_system.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _cameraDiscoveryTimeout = Duration(seconds: 3);

  late final ApiService _apiService;
  late final bool _ownsApiService;
  CameraController? _cameraController;
  Uint8List? _capturedPhoto;
  Size? _capturedPhotoSize;
  DetectionResponse? _detectionResult;
  String? _detectionErrorMessage;
  bool _isBackendUnavailable = false;
  _CameraUiState _cameraState = _CameraUiState.loading;
  bool _isCapturing = false;
  bool _isUploading = false;
  int _initializationToken = 0;
  Completer<void>? _uploadAborter;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
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
    _cancelUpload();
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(_disposeController(controller));
    }
    if (_ownsApiService) {
      _apiService.dispose();
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

      Size? photoSize;
      try {
        final decoded = await decodeImageFromList(photoBytes);
        photoSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      } catch (_) {}

      setState(() {
        _capturedPhoto = photoBytes;
        _capturedPhotoSize = photoSize;
        _detectionResult = null;
        _detectionErrorMessage = null;
        _isBackendUnavailable = false;
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
    if (!mounted || _isUploading) {
      return;
    }

    setState(() {
      _capturedPhoto = null;
      _capturedPhotoSize = null;
      _detectionResult = null;
      _detectionErrorMessage = null;
      _isBackendUnavailable = false;
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

  Future<void> _uploadCapturedPhoto() async {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto == null || _isUploading) {
      return;
    }

    final aborter = Completer<void>();
    setState(() {
      _isUploading = true;
      _uploadAborter = aborter;
      _detectionErrorMessage = null;
      _isBackendUnavailable = false;
    });

    DetectionResult result;
    try {
      result = await _apiService.detectDamage(
        imageBytes: capturedPhoto,
        abortTrigger: aborter.future,
      );
    } catch (_) {
      result = const DetectionFailure(
        userMessage:
            'Unable to connect to the UrbanEye backend. Please check your connection and server status.',
        isBackendUnavailable: true,
      );
    }

    if (!mounted || !identical(_uploadAborter, aborter)) {
      return;
    }

    _uploadAborter = null;

    if (result is DetectionSuccess) {
      if (_capturedPhotoSize == null) {
        try {
          final decoded = await decodeImageFromList(capturedPhoto);
          if (mounted) {
            _capturedPhotoSize = Size(
              decoded.width.toDouble(),
              decoded.height.toDouble(),
            );
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _detectionResult = result.response;
        _detectionErrorMessage = null;
        _isBackendUnavailable = false;
      });
      return;
    }

    if (result is DetectionFailure) {
      setState(() {
        _isUploading = false;
        _detectionErrorMessage = result.userMessage;
        _isBackendUnavailable = result.isBackendUnavailable;
      });
    }
  }

  void _cancelUpload() {
    final aborter = _uploadAborter;
    _uploadAborter = null;
    if (aborter != null && !aborter.isCompleted) {
      aborter.complete();
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
        photoSize: _capturedPhotoSize,
        isUploading: _isUploading,
        detectionResult: _detectionResult,
        errorMessage: _detectionErrorMessage,
        isBackendUnavailable: _isBackendUnavailable,
        onRetake: _isUploading ? null : () => unawaited(_retakePhoto()),
        onAnalyze:
            _isUploading ? null : () => unawaited(_uploadCapturedPhoto()),
        onDone: () => Navigator.of(context).maybePop(),
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
    required this.photoSize,
    required this.isUploading,
    required this.detectionResult,
    required this.errorMessage,
    required this.isBackendUnavailable,
    required this.onRetake,
    required this.onAnalyze,
    required this.onDone,
  });

  final Uint8List photoBytes;
  final Size? photoSize;
  final bool isUploading;
  final DetectionResponse? detectionResult;
  final String? errorMessage;
  final bool isBackendUnavailable;
  final VoidCallback? onRetake;
  final VoidCallback? onAnalyze;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isUploading,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: detectionResult != null
            ? _buildResultView(context)
            : _buildReviewOrLoadingView(context),
      ),
    );
  }

  /// The view shown after detection inference completes.
  Widget _buildResultView(BuildContext context) {
    final result = detectionResult!;
    final colorScheme = Theme.of(context).colorScheme;

    String headerLabel;
    Color headerBg;
    Color headerFg;
    IconData headerIcon;

    if (result.hasDamage) {
      final highestSeverity = _findHighestSeverity(result.detections);
      if (highestSeverity == 'Critical') {
        headerLabel = '${result.damageCount} CRITICAL HAZARD${result.damageCount > 1 ? "S" : ""}';
        headerBg = const Color(0xFFFFE4E6);
        headerFg = const Color(0xFFBE123C);
        headerIcon = Icons.warning_rounded;
      } else {
        headerLabel = '${result.damageCount} ROAD HAZARD${result.damageCount > 1 ? "S" : ""} DETECTED';
        headerBg = const Color(0xFFFFEDD5);
        headerFg = const Color(0xFFC2410C);
        headerIcon = Icons.warning_amber_rounded;
      }
    } else {
      headerLabel = 'ROAD SURFACE CLEAR';
      headerBg = const Color(0xFFDCFCE7);
      headerFg = const Color(0xFF15803D);
      headerIcon = Icons.check_circle_rounded;
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Material(
                  color: const Color(0x33FFFFFF),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: 'Back to camera',
                    onPressed: onRetake,
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detection Results',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'YOLOv5 RDD2022 AI Model',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  label: headerLabel,
                  icon: headerIcon,
                  backgroundColor: headerBg,
                  foregroundColor: headerFg,
                ),
              ],
            ),
          ),

          // Image Surface with Bounding Boxes
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(photoBytes, fit: BoxFit.contain),
                    BoundingBoxOverlay(
                      detections: result.detections,
                      imageSize: photoSize,
                      fit: BoxFit.contain,
                    ),
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: StatusChip(
                        label: 'AI BBOX ACTIVE',
                        icon: Icons.layers_outlined,
                        backgroundColor: Color(0x4D000000),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Results List & Metrics
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          result.hasDamage
                              ? 'Detected Damage (${result.damageCount})'
                              : 'Road Condition',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          result.filename.isNotEmpty ? result.filename : 'Frame analyzed',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Scrollable damage items or clear message
                    Expanded(
                      child: result.hasDamage
                          ? ListView.separated(
                              itemCount: result.detections.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = result.detections[index];
                                final color = severityColor(item.severity);
                                final bgTint = severityBackgroundColor(item.severity);

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: bgTint,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          item.label.toLowerCase().contains('pothole')
                                              ? Icons.warning_rounded
                                              : Icons.broken_image_rounded,
                                          color: color,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.label,
                                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Confidence: ${item.confidencePercentage}',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      StatusChip(
                                        label: item.severity.toUpperCase(),
                                        backgroundColor: bgTint,
                                        foregroundColor: color,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDCFCE7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.verified_rounded,
                                      color: Color(0xFF15803D),
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No road hazards detected',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'The inspected pavement looks smooth and hazard-free.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    const SizedBox(height: 12),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onRetake,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Scan Another'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Done',
                            icon: Icons.check_rounded,
                            onPressed: onDone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The view shown before inference, during inference, or on error.
  Widget _buildReviewOrLoadingView(BuildContext context) {
    return Stack(
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    label: isUploading
                        ? 'AI PROCESSING'
                        : errorMessage != null
                            ? 'ANALYSIS FAILED'
                            : 'PHOTO CAPTURED',
                    icon: isUploading
                        ? Icons.sync_rounded
                        : errorMessage != null
                            ? Icons.error_outline_rounded
                            : Icons.photo_camera_rounded,
                    backgroundColor: errorMessage != null
                        ? const Color(0xFFFFE4E6)
                        : const Color(0xE6FFFFFF),
                    foregroundColor: errorMessage != null
                        ? const Color(0xFFBE123C)
                        : const Color(0xFF1D4ED8),
                  ),
                ),
                const Spacer(),

                // Error State Card
                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0x33EF4444),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isBackendUnavailable
                                    ? Icons.cloud_off_rounded
                                    : Icons.error_outline_rounded,
                                color: const Color(0xFFEF4444),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isBackendUnavailable
                                        ? 'Backend Unavailable'
                                        : 'Detection Failed',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isBackendUnavailable
                                        ? 'Cannot reach UrbanEye backend service'
                                        : 'Inference did not succeed',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.72),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: onRetake,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: const Text('Retake'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PrimaryButton(
                                label: 'Retry Analysis',
                                icon: Icons.refresh_rounded,
                                onPressed: onAnalyze,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Normal Review State Card
                  Text(
                    'Review your photo',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Review the road frame, then run AI detection to scan for potholes and cracks.',
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
                    label: isUploading ? 'Analyzing...' : 'Analyze Road Damage',
                    icon: isUploading ? null : Icons.auto_awesome_rounded,
                    onPressed: onAnalyze,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Full Screen Loading State Overlay
        if (isUploading)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xB80F172A),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Analyzing Road Damage...',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Running YOLOv5 RDD2022 AI inference to identify potholes and cracks...',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                      ),
                      const SizedBox(height: 16),
                      const StatusChip(
                        label: 'SIH DEMO AI PIPELINE',
                        icon: Icons.memory_rounded,
                        backgroundColor: Color(0x33FFFFFF),
                        foregroundColor: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _findHighestSeverity(List<RoadDamageDetection> detections) {
    if (detections.any((d) => d.severity.toLowerCase() == 'critical')) {
      return 'Critical';
    }
    if (detections.any((d) => d.severity.toLowerCase() == 'high')) {
      return 'High';
    }
    if (detections.any((d) => d.severity.toLowerCase() == 'medium')) {
      return 'Medium';
    }
    return 'Low';
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
