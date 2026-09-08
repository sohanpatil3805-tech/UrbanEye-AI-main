import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/urbaneye_design_system.dart';

class LiveGpsScreen extends StatefulWidget {
  const LiveGpsScreen({
    this.locationService = const GeolocatorLocationService(),
    this.apiService,
    super.key,
  });

  final LocationService locationService;
  final ApiService? apiService;

  @override
  State<LiveGpsScreen> createState() => _LiveGpsScreenState();
}

class _LiveGpsScreenState extends State<LiveGpsScreen> {
  static const _trackingInterval = Duration(seconds: 5);
  static const _vehicleId = 'BUS-001';

  late final ApiService _apiService;
  late final bool _ownsApiService;
  Timer? _trackingTimer;
  Position? _position;
  DateTime? _lastUpdated;
  _GpsIssue? _issue;
  bool _isStarting = false;
  bool _isTracking = false;
  bool _isFetchingLocation = false;
  bool _isSendingLocation = false;
  int _trackingSession = 0;
  Completer<void>? _locationUploadAborter;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? ApiService();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _trackingSession += 1;
    _isStarting = false;
    _isTracking = false;
    _isFetchingLocation = false;
    _cancelLocationUpload();
    if (_ownsApiService) {
      _apiService.dispose();
    }
    super.dispose();
  }

  Future<void> _startTracking() async {
    if (_isStarting || _isTracking) {
      return;
    }

    setState(() {
      _isStarting = true;
      _issue = null;
      _position = null;
      _lastUpdated = null;
    });

    try {
      final serviceEnabled =
          await widget.locationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setIssue(_GpsIssue.locationServicesDisabled);
        return;
      }

      var permission = await widget.locationService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await widget.locationService.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _setIssue(_GpsIssue.permissionDenied);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _setIssue(_GpsIssue.permissionDeniedForever);
        return;
      }

      if (!mounted) {
        return;
      }

      _trackingSession += 1;
      setState(() {
        _isStarting = false;
        _isTracking = true;
      });

      _trackingTimer = Timer.periodic(
        _trackingInterval,
        (_) => _refreshPosition(),
      );
      await _refreshPosition();
    } catch (_) {
      _setIssue(_GpsIssue.unavailable);
    }
  }

  Future<void> _refreshPosition() async {
    if (!_isTracking || _isFetchingLocation) {
      return;
    }

    final trackingSession = _trackingSession;
    _isFetchingLocation = true;
    try {
      final serviceEnabled =
          await widget.locationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setIssue(_GpsIssue.locationServicesDisabled);
        return;
      }

      final position = await widget.locationService.getCurrentPosition();
      if (!mounted || !_isTracking || trackingSession != _trackingSession) {
        return;
      }

      LocationStore.latestPosition = position;
      setState(() {
        _position = position;
        _lastUpdated = DateTime.now();
        _issue = null;
      });
      unawaited(_sendLocation(position, trackingSession));
    } on LocationServiceDisabledException {
      if (_isTracking && trackingSession == _trackingSession) {
        _setIssue(_GpsIssue.locationServicesDisabled);
      }
    } catch (_) {
      if (_isTracking && trackingSession == _trackingSession) {
        _setIssue(_GpsIssue.unavailable);
      }
    } finally {
      if (trackingSession == _trackingSession) {
        _isFetchingLocation = false;
      }
    }
  }

  Future<void> _sendLocation(Position position, int trackingSession) async {
    if (!_isTracking ||
        _isSendingLocation ||
        trackingSession != _trackingSession) {
      return;
    }

    final aborter = Completer<void>();
    _locationUploadAborter = aborter;
    _isSendingLocation = true;
    try {
      await _apiService.sendLocation(
        vehicleId: _vehicleId,
        latitude: position.latitude,
        longitude: position.longitude,
        speed: _nonNegativeFiniteValue(position.speed),
        accuracy: _nonNegativeFiniteValue(position.accuracy),
        timestamp: position.timestamp,
        abortTrigger: aborter.future,
      );
    } catch (_) {
      // Keep local tracking active; the next tracking interval retries upload.
    } finally {
      if (identical(_locationUploadAborter, aborter)) {
        _locationUploadAborter = null;
      }
      if (trackingSession == _trackingSession) {
        _isSendingLocation = false;
      }
    }
  }

  static double _nonNegativeFiniteValue(double value) {
    return value.isFinite && value >= 0 ? value : 0;
  }

  void _cancelLocationUpload() {
    final aborter = _locationUploadAborter;
    _locationUploadAborter = null;
    _isSendingLocation = false;
    if (aborter != null && !aborter.isCompleted) {
      aborter.complete();
    }
  }

  void _stopTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _trackingSession += 1;
    _isFetchingLocation = false;
    _cancelLocationUpload();
    if (!mounted) {
      _isStarting = false;
      _isTracking = false;
      return;
    }

    setState(() {
      _isStarting = false;
      _isTracking = false;
      _issue = null;
    });
  }

  void _setIssue(_GpsIssue issue) {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _trackingSession += 1;
    _isFetchingLocation = false;
    _cancelLocationUpload();
    if (!mounted) {
      _isStarting = false;
      _isTracking = false;
      return;
    }

    setState(() {
      _isStarting = false;
      _isTracking = false;
      _issue = issue;
    });
  }

  Future<void> _openLocationSettings() async {
    await _openSettings(
      widget.locationService.openLocationSettings,
      'Unable to open location settings on this device.',
    );
  }

  Future<void> _openAppSettings() async {
    await _openSettings(
      widget.locationService.openAppSettings,
      'Unable to open app settings on this device.',
    );
  }

  Future<void> _openSettings(
    Future<bool> Function() openSettings,
    String failureMessage,
  ) async {
    try {
      final opened = await openSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failureMessage)),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
    }
  }

  String get _coordinatesText {
    final position = _position;
    if (position == null) {
      return 'Waiting for a GPS fix';
    }

    return '${_formatCoordinate(position.latitude, 'N', 'S')}, '
        '${_formatCoordinate(position.longitude, 'E', 'W')}';
  }

  String get _accuracyText {
    final accuracy = _position?.accuracy;
    if (accuracy == null || !accuracy.isFinite || accuracy < 0) {
      return '--';
    }

    return '${accuracy.toStringAsFixed(1)} m';
  }

  String get _speedText {
    final speed = _position?.speed;
    if (speed == null || !speed.isFinite || speed < 0) {
      return '--';
    }

    return '${(speed * 3.6).toStringAsFixed(1)} km/h';
  }

  String get _lastUpdatedText {
    final time = _lastUpdated;
    if (time == null) {
      return 'Not yet updated';
    }

    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    final seconds = time.second.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String get _footerText {
    if (_isStarting) {
      return 'Requesting location access...';
    }
    if (_isTracking) {
      return 'Tracking updates every 5 seconds while this screen is open.';
    }
    if (_issue != null) {
      return 'Resolve the issue above, then try tracking again.';
    }
    return 'Start tracking to request location access.';
  }

  _TrackerStatus get _trackerStatus {
    if (_isTracking) {
      return const _TrackerStatus(
        label: 'TRACKING',
        backgroundColor: Color(0xFFF0FDF4),
        foregroundColor: Color(0xFF15803D),
      );
    }
    if (_isStarting) {
      return const _TrackerStatus(
        label: 'STARTING',
        backgroundColor: Color(0xFFE0F2FE),
        foregroundColor: Color(0xFF0369A1),
      );
    }
    if (_issue == _GpsIssue.locationServicesDisabled) {
      return const _TrackerStatus(
        label: 'GPS OFF',
        backgroundColor: Color(0xFFFFF7ED),
        foregroundColor: Color(0xFFB45309),
      );
    }
    if (_issue != null) {
      return const _TrackerStatus(
        label: 'ACTION NEEDED',
        backgroundColor: Color(0xFFFFE4E6),
        foregroundColor: Color(0xFFBE123C),
      );
    }
    return const _TrackerStatus(
      label: 'READY',
      backgroundColor: Color(0xFFE0F2FE),
      foregroundColor: Color(0xFF0369A1),
    );
  }

  static String _formatCoordinate(
    double coordinate,
    String positiveDirection,
    String negativeDirection,
  ) {
    final direction = coordinate >= 0 ? positiveDirection : negativeDirection;
    return '${coordinate.abs().toStringAsFixed(6)}° $direction';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trackerStatus = _trackerStatus;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientHeader(
                eyebrow: 'URBANEYE AI  •  LIVE MONITORING',
                title: 'Live GPS',
                subtitle:
                    'Track your vehicle location while this screen is open.',
                leading: _HeaderBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                footer: StatusChip(
                  label: trackerStatus.label,
                  backgroundColor: trackerStatus.backgroundColor,
                  foregroundColor: trackerStatus.foregroundColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Vehicle location',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Live values refresh every five seconds after tracking starts.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              PrimaryCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LocationPreview(
                      isTracking: _isTracking,
                      status: trackerStatus,
                    ),
                    const SizedBox(height: 20),
                    InfoTile(
                      icon: Icons.my_location_rounded,
                      title: 'Current coordinates',
                      subtitle: _coordinatesText,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.gps_fixed_rounded,
                            label: 'Accuracy',
                            value: _accuracyText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.speed_rounded,
                            label: 'Speed',
                            value: _speedText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                    const SizedBox(height: 16),
                    _LastUpdatedRow(lastUpdatedText: _lastUpdatedText),
                  ],
                ),
              ),
              if (_issue != null) ...[
                const SizedBox(height: 16),
                _GpsIssueCard(
                  issue: _issue!,
                  onOpenLocationSettings: _openLocationSettings,
                  onOpenAppSettings: _openAppSettings,
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: _isStarting
                    ? 'Requesting Permission...'
                    : _isTracking
                        ? 'Stop Tracking'
                        : 'Start Tracking',
                icon: _isTracking
                    ? Icons.stop_circle_outlined
                    : Icons.navigation_rounded,
                onPressed: _isStarting
                    ? null
                    : _isTracking
                        ? _stopTracking
                        : _startTracking,
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

class _LocationPreview extends StatelessWidget {
  const _LocationPreview({required this.isTracking, required this.status});

  final bool isTracking;
  final _TrackerStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF2FF), Color(0xFFEAEAFF)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFF2563EB),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x552563EB),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              isTracking
                  ? Icons.navigation_rounded
                  : Icons.directions_car_filled_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: StatusChip(
              label: status.label,
              backgroundColor: Colors.white,
              foregroundColor: status.foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary, size: 20),
          const SizedBox(height: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _LastUpdatedRow extends StatelessWidget {
  const _LastUpdatedRow({required this.lastUpdatedText});

  final String lastUpdatedText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          color: colorScheme.onSurfaceVariant,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(
          'Last updated',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const Spacer(),
        Text(
          lastUpdatedText,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _GpsIssueCard extends StatelessWidget {
  const _GpsIssueCard({
    required this.issue,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final _GpsIssue issue;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final useErrorColor = issue != _GpsIssue.locationServicesDisabled;
    final backgroundColor = useErrorColor
        ? colorScheme.errorContainer
        : colorScheme.tertiaryContainer;
    final foregroundColor = useErrorColor
        ? colorScheme.onErrorContainer
        : colorScheme.onTertiaryContainer;

    return PrimaryCard(
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(issue.icon, color: foregroundColor),
          const SizedBox(height: 12),
          Text(
            issue.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            issue.message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                ),
          ),
          if (issue == _GpsIssue.locationServicesDisabled) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpenLocationSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open location settings'),
            ),
          ],
          if (issue == _GpsIssue.permissionDeniedForever) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpenAppSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open app settings'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackerStatus {
  const _TrackerStatus({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

enum _GpsIssue {
  locationServicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable;

  String get title {
    switch (this) {
      case _GpsIssue.locationServicesDisabled:
        return 'Location services are off';
      case _GpsIssue.permissionDenied:
        return 'Location permission denied';
      case _GpsIssue.permissionDeniedForever:
        return 'Location permission is blocked';
      case _GpsIssue.unavailable:
        return 'Unable to get your location';
    }
  }

  String get message {
    switch (this) {
      case _GpsIssue.locationServicesDisabled:
        return 'Turn on GPS or location services, then start tracking again.';
      case _GpsIssue.permissionDenied:
        return 'Allow location access to start tracking this vehicle.';
      case _GpsIssue.permissionDeniedForever:
        return 'Enable location access for UrbanEye AI in app settings.';
      case _GpsIssue.unavailable:
        return 'Check your connection and GPS signal, then try again.';
    }
  }

  IconData get icon {
    switch (this) {
      case _GpsIssue.locationServicesDisabled:
        return Icons.location_off_outlined;
      case _GpsIssue.permissionDenied:
      case _GpsIssue.permissionDeniedForever:
        return Icons.location_disabled_outlined;
      case _GpsIssue.unavailable:
        return Icons.gps_off_rounded;
    }
  }
}
