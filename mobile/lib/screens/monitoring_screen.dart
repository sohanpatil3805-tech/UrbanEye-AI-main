import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/monitoring_controller.dart';
import '../widgets/urbaneye_design_system.dart';

/// Live monitoring owns its camera independently of the manual capture screen.
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({this.controller, super.key});

  final MonitoringController? controller;

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  late final MonitoringController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MonitoringController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      unawaited(_controller.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final state = _controller.state;
            final active = state == MonitoringState.active;
            final canStart =
                state == MonitoringState.idle || state == MonitoringState.error;
            final canStop = active || state == MonitoringState.starting;
            final status = switch (state) {
              MonitoringState.idle => 'Ready to Monitor',
              MonitoringState.starting => 'Starting Monitoring',
              MonitoringState.active => 'Monitoring Active',
              MonitoringState.stopping => 'Stopping Monitoring',
              MonitoringState.error => 'Monitoring Unavailable',
            };

            return LayoutBuilder(builder: (context, constraints) {
              final previewHeight =
                  (constraints.maxHeight * 0.45).clamp(220.0, 480.0).toDouble();
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GradientHeader(
                      eyebrow: 'URBANEYE AI',
                      title: 'Monitoring Mode',
                      subtitle: 'A live view of the road ahead.',
                      leading: IconButton(
                        tooltip: 'Back',
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          liveRegion: true,
                          child: StatusChip(
                            label: status,
                            icon: active
                                ? Icons.radio_button_checked_rounded
                                : Icons.circle_outlined,
                            backgroundColor: active
                                ? colorScheme.tertiaryContainer
                                : colorScheme.secondaryContainer,
                            foregroundColor: active
                                ? colorScheme.onTertiaryContainer
                                : colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryCard(
                      padding: EdgeInsets.zero,
                      color: colorScheme.surfaceContainerHighest,
                      child: SizedBox(
                        height: previewHeight,
                        child: _MonitoringPreview(controller: _controller),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Start Monitoring',
                      icon: Icons.play_arrow_rounded,
                      onPressed: canStart
                          ? () => unawaited(_controller.start())
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          canStop ? () => unawaited(_controller.stop()) : null,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop Monitoring'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      active
                          ? 'Keep the camera pointed at the road while monitoring.'
                          : 'Tap Start Monitoring to open the road camera.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              );
            });
          },
        ),
      ),
    );
  }
}

class _MonitoringPreview extends StatelessWidget {
  const _MonitoringPreview({required this.controller});

  final MonitoringController controller;

  @override
  Widget build(BuildContext context) {
    final camera = controller.cameraController;
    if (controller.state == MonitoringState.active &&
        camera?.value.isInitialized == true) {
      return ColoredBox(
        color: Colors.black,
        child: Center(child: CameraPreview(camera!)),
      );
    }

    final busy = controller.state == MonitoringState.starting ||
        controller.state == MonitoringState.stopping;
    final message = controller.errorMessage ??
        switch (controller.state) {
          MonitoringState.starting => 'Preparing the road camera...',
          MonitoringState.stopping => 'Closing the road camera...',
          _ => 'Camera preview will appear here.',
        };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const CircularProgressIndicator()
            else
              Icon(
                controller.state == MonitoringState.error
                    ? Icons.videocam_off_outlined
                    : Icons.videocam_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
