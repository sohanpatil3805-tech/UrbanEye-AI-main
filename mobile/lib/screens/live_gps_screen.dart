import 'package:flutter/material.dart';

import '../widgets/urbaneye_design_system.dart';

class LiveGpsScreen extends StatelessWidget {
  const LiveGpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                subtitle: 'Current vehicle location and connection status.',
                leading: _HeaderBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                footer: const StatusChip(
                  label: 'ONLINE',
                  backgroundColor: Color(0xFFF0FDF4),
                  foregroundColor: Color(0xFF15803D),
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
                'A preview of your latest reported position.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              const PrimaryCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LocationPreview(),
                    SizedBox(height: 20),
                    InfoTile(
                      icon: Icons.my_location_rounded,
                      title: 'Current coordinates',
                      subtitle: '28.6139° N, 77.2090° E',
                    ),
                    SizedBox(height: 16),
                    Divider(height: 1),
                    SizedBox(height: 16),
                    _LastUpdatedRow(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Start Tracking',
                icon: Icons.navigation_rounded,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'GPS tracking controls will be available soon.',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Tracking is not active in this preview.',
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
  const _LocationPreview();

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
            child: const Icon(
              Icons.directions_car_filled_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const Positioned(
            top: 16,
            right: 16,
            child: StatusChip(
              label: 'GPS READY',
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastUpdatedRow extends StatelessWidget {
  const _LastUpdatedRow();

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
          'Just now',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
