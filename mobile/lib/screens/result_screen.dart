import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/detection_result.dart';
import '../widgets/urbaneye_design_system.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    required this.photoBytes,
    required this.result,
    this.position,
    super.key,
  });

  final Uint8List photoBytes;
  final DetectionResult result;
  final Position? position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetections = result.detections.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: result.detections.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GradientHeader(
                    eyebrow: 'URBANEYE AI',
                    title: 'AI Result',
                    subtitle: 'Your road hazard analysis is complete.',
                    leading: Material(
                      color: const Color(0x33FFFFFF),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        color: Colors.white,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _DetectionImage(
                    photoBytes: photoBytes,
                    detections: result.detections,
                  ),
                  const SizedBox(height: 16),
                  const _ReportedConfirmation(),
                  const SizedBox(height: 16),
                  PrimaryCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfoTile(
                          icon: Icons.location_on_outlined,
                          title: 'GPS coordinates',
                          subtitle: _coordinatesText,
                        ),
                        const SizedBox(height: 20),
                        InfoTile(
                          icon: Icons.schedule_rounded,
                          title: 'Detection timestamp',
                          subtitle: _timestampText(context),
                        ),
                      ],
                    ),
                  ),
                  if (hasDetections) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Detections (${result.detections.length})',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              );
            }

            if (index <= result.detections.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _DetectionCard(detection: result.detections[index - 1]),
              );
            }

            return Padding(
              padding: EdgeInsets.only(top: hasDetections ? 0 : 16),
              child: _AiRecommendationCard(
                detections: result.detections,
              ),
            );
          },
        ),
      ),
    );
  }

  String get _coordinatesText {
    final coordinates = position;
    if (coordinates == null ||
        !coordinates.latitude.isFinite ||
        !coordinates.longitude.isFinite) {
      return 'GPS coordinates unavailable';
    }
    return 'Latitude: ${coordinates.latitude.toStringAsFixed(6)}\n'
        'Longitude: ${coordinates.longitude.toStringAsFixed(6)}';
  }

  String _timestampText(BuildContext context) {
    final localTime = result.timestamp.toLocal();
    final date = MaterialLocalizations.of(context).formatFullDate(localTime);
    final hours = localTime.hour.toString().padLeft(2, '0');
    final minutes = localTime.minute.toString().padLeft(2, '0');
    final seconds = localTime.second.toString().padLeft(2, '0');
    return '$date\n$hours:$minutes:$seconds (${localTime.timeZoneName})';
  }
}

class _DetectionImage extends StatefulWidget {
  const _DetectionImage({required this.photoBytes, required this.detections});

  final Uint8List photoBytes;
  final List<HazardDetection> detections;

  @override
  State<_DetectionImage> createState() => _DetectionImageState();
}

class _DetectionImageState extends State<_DetectionImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _sourceSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(covariant _DetectionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoBytes != widget.photoBytes) {
      _removeImageListener();
      _sourceSize = null;
      _resolveImageSize();
    }
  }

  void _resolveImageSize() {
    if (_imageListener != null) {
      return;
    }
    final imageStream = MemoryImage(widget.photoBytes).resolve(
      createLocalImageConfiguration(context),
    );
    final imageListener = ImageStreamListener(
      (imageInfo, _) {
        if (!mounted) {
          return;
        }
        setState(() {
          _sourceSize = Size(
            imageInfo.image.width.toDouble(),
            imageInfo.image.height.toDouble(),
          );
        });
      },
      onError: (exception, stackTrace) {},
    );
    _imageStream = imageStream;
    _imageListener = imageListener;
    imageStream.addListener(imageListener);
  }

  void _removeImageListener() {
    final imageStream = _imageStream;
    final imageListener = _imageListener;
    if (imageStream != null && imageListener != null) {
      imageStream.removeListener(imageListener);
    }
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceSize = _sourceSize;
    final aspectRatio =
        sourceSize == null ? 4 / 3 : sourceSize.width / sourceSize.height;
    final colorScheme = Theme.of(context).colorScheme;

    return PrimaryCard(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: colorScheme.surfaceContainerLow,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  widget.photoBytes,
                  fit: BoxFit.contain,
                  semanticLabel: 'Captured image',
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Text('Captured image unavailable')),
                ),
                if (widget.detections.isEmpty)
                  const Center(child: _NoHazardsPill())
                else if (sourceSize != null)
                  RepaintBoundary(
                    child: _DetectionOverlay(
                      detections: widget.detections,
                      sourceSize: sourceSize,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectionOverlay extends StatelessWidget {
  const _DetectionOverlay({
    required this.detections,
    required this.sourceSize,
  });

  final List<HazardDetection> detections;
  final Size sourceSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final renderedSize = constraints.biggest;

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              key: const ValueKey('detection-bounding-box-overlay'),
              painter: _BoundingBoxPainter(
                detections: detections,
                sourceSize: sourceSize,
              ),
            ),
            for (final entry in detections.indexed)
              _DetectionLabel(
                index: entry.$1,
                detection: entry.$2,
                renderedSize: renderedSize,
                sourceSize: sourceSize,
              ),
          ],
        );
      },
    );
  }
}

class _DetectionLabel extends StatelessWidget {
  const _DetectionLabel({
    required this.index,
    required this.detection,
    required this.renderedSize,
    required this.sourceSize,
  });

  final int index;
  final HazardDetection detection;
  final Size renderedSize;
  final Size sourceSize;

  @override
  Widget build(BuildContext context) {
    final box = detection.boundingBox
        .scaledTo(renderedSize, sourceSize: sourceSize)
        .intersect(Offset.zero & renderedSize);
    if (box.isEmpty) {
      return const SizedBox.shrink();
    }

    final color = _boxColor(detection.severity);
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    final maxWidth = (renderedSize.width - box.left)
        .clamp(0.0, renderedSize.width)
        .toDouble();

    return Positioned(
      left: box.left,
      top: box.top,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          key: ValueKey('detection-overlay-label-$index'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '${detection.label} '
            '${(detection.confidence * 100).toStringAsFixed(1)}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _NoHazardsPill extends StatelessWidget {
  const _NoHazardsPill();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey('no-hazards-image-message'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              color: colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            'No hazards detected',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  const _BoundingBoxPainter({
    required this.detections,
    required this.sourceSize,
  });

  final List<HazardDetection> detections;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final color = _boxColor(detection.severity);
      final box = detection.boundingBox
          .scaledTo(size, sourceSize: sourceSize)
          .intersect(Offset.zero & size);
      if (box.isEmpty) {
        continue;
      }
      canvas.drawRect(
        box,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sourceSize != sourceSize;
  }
}

Color _boxColor(HazardSeverity severity) => switch (severity) {
      HazardSeverity.critical => Colors.red,
      HazardSeverity.high => Colors.orange,
      HazardSeverity.medium => Colors.yellow,
      HazardSeverity.low => Colors.green,
    };

class _ReportedConfirmation extends StatelessWidget {
  const _ReportedConfirmation();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = isDark ? Colors.green.shade200 : Colors.green.shade800;

    return PrimaryCard(
      color: isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Reported to Dashboard',
              style: theme.textTheme.titleSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiRecommendationCard extends StatelessWidget {
  const _AiRecommendationCard({required this.detections});

  final List<HazardDetection> detections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (detections.isEmpty) {
      final isDark = theme.brightness == Brightness.dark;
      final foreground = isDark ? Colors.green.shade200 : Colors.green.shade800;

      return PrimaryCard(
        key: const ValueKey('ai-recommendation-card'),
        color: isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: foreground, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Road appears safe',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final highestSeverityDetection = _highestSeverityDetection(detections);
    final recommendations = _recommendationsFor(highestSeverityDetection);

    return PrimaryCard(
      key: const ValueKey('ai-recommendation-card'),
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Recommendation',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Based on ${highestSeverityDetection.severity.label.toLowerCase()} '
                      '${highestSeverityDetection.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final recommendation in recommendations) ...[
            _RecommendationRow(recommendation: recommendation),
            if (recommendation != recommendations.last)
              const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({required this.recommendation});

  final _Recommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.72),
            shape: BoxShape.circle,
          ),
          child: Icon(
            recommendation.icon,
            size: 19,
            color: colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            recommendation.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _Recommendation {
  const _Recommendation(this.icon, this.label);

  final IconData icon;
  final String label;
}

HazardDetection _highestSeverityDetection(List<HazardDetection> detections) {
  var highest = detections.first;
  for (final detection in detections.skip(1)) {
    final detectionRank = _severityRank(detection.severity);
    final highestRank = _severityRank(highest.severity);
    if (detectionRank > highestRank) {
      highest = detection;
    }
  }
  return highest;
}

int _severityRank(HazardSeverity severity) => switch (severity) {
      HazardSeverity.critical => 4,
      HazardSeverity.high => 3,
      HazardSeverity.medium => 2,
      HazardSeverity.low => 1,
    };

List<_Recommendation> _recommendationsFor(HazardDetection detection) {
  final label = detection.label.toLowerCase();
  if (label.contains('pothole') &&
      (detection.severity == HazardSeverity.critical ||
          detection.severity == HazardSeverity.high)) {
    return const [
      _Recommendation(Icons.speed_rounded, 'Reduce speed immediately'),
      _Recommendation(Icons.cloud_upload_outlined, 'Report queued'),
      _Recommendation(Icons.dashboard_outlined, 'Dashboard notified'),
    ];
  }
  if (label.contains('alligator crack')) {
    return const [
      _Recommendation(Icons.directions_car_filled_rounded, 'Drive cautiously'),
      _Recommendation(Icons.fact_check_outlined, 'Road requires inspection'),
    ];
  }
  if (label.contains('longitudinal crack') ||
      label.contains('transverse crack')) {
    return const [
      _Recommendation(Icons.visibility_outlined, 'Monitor road condition'),
    ];
  }
  return const [
    _Recommendation(Icons.visibility_outlined, 'Monitor road condition'),
  ];
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.detection});

  final HazardDetection detection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = switch (detection.severity) {
      HazardSeverity.critical => Colors.red,
      HazardSeverity.high => Colors.deepOrange,
      HazardSeverity.medium => Colors.amber,
      HazardSeverity.low => Colors.green,
    };
    final foreground = isDark ? palette.shade200 : palette.shade900;

    return PrimaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detection.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Confidence: ${(detection.confidence * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              StatusChip(
                label: detection.severity.label,
                icon: Icons.warning_rounded,
                backgroundColor: isDark
                    ? palette.shade900.withValues(alpha: 0.35)
                    : palette.shade50,
                foregroundColor: foreground,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
