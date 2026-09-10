import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/detection_result_service.dart';
import '../services/location_service.dart';
import '../widgets/urbaneye_design_system.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    this.apiService,
    this.imagePicker,
    this.locationService = const GeolocatorLocationService(),
    super.key,
  });

  final ApiService? apiService;
  final ImagePicker? imagePicker;
  final LocationService locationService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _cameraDiscoveryTimeout = Duration(seconds: 3);

  late final ApiService _apiService;
  late final bool _ownsApiService;
  late final ImagePicker _imagePicker;
  CameraController? _cameraController;
  Uint8List? _capturedPhoto;
  _CameraUiState _cameraState = _CameraUiState.loading;
  bool _isCapturing = false;
  bool _isUploading = false;
  bool _isLocating = false;
  bool _isPickingImage = false;
  bool _isSettingFlash = false;
  bool _supportsFlash = false;
  String _photoFilename = 'capture.jpg';
  int _initializationToken = 0;
  Completer<void>? _uploadAborter;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? DetectionResultService();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_releaseCamera());
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _capturedPhoto == null &&
        !_isPickingImage) {
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
    if (_isPickingImage) {
      return;
    }
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
      _isSettingFlash = false;
      _supportsFlash = false;
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

      var supportsFlash = true;
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Cameras without flash must still support preview and capture.
        supportsFlash = false;
      }
      if (!mounted || initializationToken != _initializationToken) {
        await _disposeController(controller);
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraState = _CameraUiState.ready;
        _supportsFlash = supportsFlash;
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
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _isSettingFlash ||
        _isPickingImage) {
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
        if (controller.value.flashMode == FlashMode.torch) {
          await controller.setFlashMode(FlashMode.off);
        }
      } catch (_) {
        // Retain the captured image even if the camera cannot change flash mode.
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
        _photoFilename = photo.name;
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

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_supportsFlash ||
        _isSettingFlash ||
        _isCapturing ||
        _isPickingImage ||
        _isUploading) {
      return;
    }

    final mode = controller.value.flashMode == FlashMode.torch
        ? FlashMode.off
        : FlashMode.torch;
    setState(() => _isSettingFlash = true);
    try {
      await controller.setFlashMode(mode);
    } catch (_) {
      if (mounted && controller == _cameraController) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to change flash on this camera.')),
        );
      }
    } finally {
      if (mounted && controller == _cameraController) {
        setState(() => _isSettingFlash = false);
      }
    }
  }

  Future<void> _pickGalleryImage() async {
    if (_isPickingImage || _isCapturing || _isUploading || _isSettingFlash) {
      return;
    }

    setState(() {
      _isPickingImage = true;
      _cameraState = _CameraUiState.loading;
    });

    try {
      await _releaseCamera();
      if (!mounted) {
        return;
      }
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (photo == null || !mounted) {
        return;
      }
      final photoBytes = await photo.readAsBytes();
      if (!mounted) {
        return;
      }
      if (photoBytes.isEmpty) {
        throw const FormatException('Empty image');
      }
      setState(() {
        _capturedPhoto = photoBytes;
        _photoFilename = photo.name;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open gallery image. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
        if (_capturedPhoto == null) {
          await _initializeCamera();
        }
      }
    }
  }

  Future<void> _retakePhoto() async {
    if (!mounted || _isUploading) {
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

  Future<Position?> _fetchUploadPosition(Completer<void> aborter) async {
    bool isActive() => mounted && identical(_uploadAborter, aborter);
    final locationService = widget.locationService;
    final enabled = await locationService.isLocationServiceEnabled();
    if (!isActive()) return null;
    if (!enabled) {
      throw const _UploadLocationException(
        'Turn on location services, then tap Continue to try again.',
      );
    }

    var permission = await locationService.checkPermission();
    if (!isActive()) return null;
    if (permission == LocationPermission.denied) {
      permission = await locationService.requestPermission();
      if (!isActive()) return null;
    }
    if (permission == LocationPermission.deniedForever) {
      throw const _UploadLocationException(
        'Allow location access in app settings, then tap Continue to try again.',
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const _UploadLocationException(
        'Location permission is needed to upload. Tap Continue to try again.',
      );
    }

    final position = await locationService.getCurrentPosition();
    if (!isActive()) return null;
    if (!position.latitude.isFinite ||
        position.latitude < -90 ||
        position.latitude > 90 ||
        !position.longitude.isFinite ||
        position.longitude < -180 ||
        position.longitude > 180) {
      throw const _UploadLocationException(
        'Unable to get valid GPS coordinates. Please try again.',
      );
    }
    return position;
  }

  Future<void> _uploadCapturedPhoto() async {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto == null || _isUploading) {
      return;
    }

    final aborter = Completer<void>();
    setState(() {
      _isUploading = true;
      _isLocating = true;
      _uploadAborter = aborter;
    });

    var uploadSucceeded = false;
    var failureMessage =
        'Unable to upload your image. Please check your connection and try again.';
    Position? uploadPosition;
    try {
      uploadPosition = await _fetchUploadPosition(aborter);
      if (!mounted ||
          !identical(_uploadAborter, aborter) ||
          uploadPosition == null) {
        return;
      }
      setState(() => _isLocating = false);
      uploadSucceeded = await _apiService.uploadDetectionImage(
        imageBytes: capturedPhoto,
        filename: _photoFilename,
        latitude: uploadPosition.latitude,
        longitude: uploadPosition.longitude,
        abortTrigger: aborter.future,
      );
    } on _UploadLocationException catch (error) {
      failureMessage = error.message;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Image upload failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (_isLocating) {
        failureMessage =
            'Unable to get your location. Check GPS and try again.';
      }
    }

    if (!mounted || !identical(_uploadAborter, aborter)) {
      return;
    }

    _uploadAborter = null;
    setState(() {
      _isUploading = false;
      _isLocating = false;
    });

    if (uploadSucceeded) {
      final service = _apiService;
      final result = service is DetectionResultService ? service.result : null;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read detection results.')),
        );
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            photoBytes: capturedPhoto,
            result: result,
            position: uploadPosition,
          ),
        ),
      );
      if (mounted) {
        await _retakePhoto();
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failureMessage)),
    );
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
    if (_isPickingImage) {
      return 'Selecting a photo from your gallery...';
    }
    if (_cameraState == _CameraUiState.ready) {
      return _isCapturing
          ? 'Capturing your photo...'
          : 'Tap Capture to take a photo, or Gallery to select an image.';
    }
    if (_cameraState == _CameraUiState.loading) {
      return 'Requesting camera access and preparing the live preview...';
    }
    return 'Select an image from Gallery, or resolve camera access above.';
  }

  @override
  Widget build(BuildContext context) {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto != null) {
      return _CapturedPhotoPreview(
        photoBytes: capturedPhoto,
        isUploading: _isUploading,
        isLocating: _isLocating,
        onRetake: _isUploading ? null : () => unawaited(_retakePhoto()),
        onContinue:
            _isUploading ? null : () => unawaited(_uploadCapturedPhoto()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final headerStatus = _headerStatus;
    final isCameraReady = _cameraState == _CameraUiState.ready &&
        _cameraController?.value.isInitialized == true &&
        !_isCapturing &&
        !_isPickingImage &&
        !_isSettingFlash;
    final isFlashOn = _cameraController?.value.flashMode == FlashMode.torch;

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
                  _ToolButton(
                    icon: Icons.flash_off_rounded,
                    selectedIcon: Icons.flash_on_rounded,
                    isSelected: isFlashOn,
                    label: 'Flash',
                    tooltip: !_supportsFlash
                        ? 'Flash unavailable'
                        : isFlashOn
                            ? 'Turn flash off'
                            : 'Turn flash on',
                    onPressed: isCameraReady && _supportsFlash
                        ? () => unawaited(_toggleFlash())
                        : null,
                  ),
                  _CaptureButton(
                    isCapturing: _isCapturing,
                    onPressed:
                        isCameraReady ? () => unawaited(_capturePhoto()) : null,
                  ),
                  _ToolButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onPressed: _isCapturing ||
                            _isPickingImage ||
                            _isUploading ||
                            _isSettingFlash
                        ? null
                        : () => unawaited(_pickGalleryImage()),
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

class _UploadLocationException implements Exception {
  const _UploadLocationException(this.message);

  final String message;
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.tooltip,
    this.isSelected,
    this.selectedIcon,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool? isSelected;
  final IconData? selectedIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: tooltip ?? label,
          onPressed: onPressed,
          icon: Icon(icon),
          isSelected: isSelected,
          selectedIcon: selectedIcon == null ? null : Icon(selectedIcon),
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
    required this.isUploading,
    required this.isLocating,
    required this.onRetake,
    required this.onContinue,
  });

  final Uint8List photoBytes;
  final bool isUploading;
  final bool isLocating;
  final VoidCallback? onRetake;
  final VoidCallback? onContinue;

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
                      label: 'PHOTO READY',
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
                    'Review your photo, then upload it to UrbanEye AI for processing.',
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
                    label: isLocating
                        ? 'Getting location...'
                        : isUploading
                            ? 'Uploading...'
                            : 'Continue',
                    icon: isUploading ? null : Icons.arrow_forward_rounded,
                    onPressed: onContinue,
                  ),
                ],
              ),
            ),
          ),
          if (isUploading)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x990F172A),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isLocating
                            ? 'Getting your location...'
                            : 'Uploading image...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
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
