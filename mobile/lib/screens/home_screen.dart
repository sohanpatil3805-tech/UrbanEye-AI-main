import 'package:flutter/material.dart';

import '../widgets/urbaneye_design_system.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientHeader(
                eyebrow: 'URBANEYE AI  •  DRIVER DASHBOARD',
                title: 'Good afternoon, Alex Morgan',
                subtitle: 'Vehicle UE-1024 • Your route is ready.',
                leading: _ProfileAvatar(
                  onTap: () => Navigator.pushNamed(context, '/profile'),
                ),
                footer: const StatusChip(
                  label: 'Vehicle Online',
                  backgroundColor: Color(0xFFF0FDF4),
                  foregroundColor: Color(0xFF15803D),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'System readiness',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'A quick check before you begin monitoring.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth >= 900
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth >= 600
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: PrimaryCard(
                          onTap: () => Navigator.pushNamed(context, '/gps'),
                          child: const InfoTile(
                            icon: Icons.location_on_outlined,
                            title: 'GPS Ready',
                            subtitle: 'Location service connected',
                            trailing: StatusChip(label: 'Ready'),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: PrimaryCard(
                          onTap: () => Navigator.pushNamed(context, '/camera'),
                          child: const InfoTile(
                            icon: Icons.videocam_outlined,
                            title: 'Camera Ready',
                            subtitle: 'Front camera available',
                            trailing: StatusChip(label: 'Ready'),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: PrimaryCard(
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/notifications',
                          ),
                          child: const InfoTile(
                            icon: Icons.notifications_none_rounded,
                            title: '0 Active Alerts',
                            subtitle: 'No issues need attention',
                            trailing: StatusChip(label: 'Clear'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              PrimaryCard(
                color: const Color(0xFFF0F5FF),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const InfoTile(
                      icon: Icons.route_outlined,
                      title: 'Ready for your route?',
                      subtitle: 'Start monitoring when you are ready to drive.',
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Start Monitoring',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Monitoring controls will be available soon.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open profile',
      child: Semantics(
        label: 'Open profile',
        button: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const CircleAvatar(
              radius: 25,
              backgroundColor: Color(0x33FFFFFF),
              foregroundColor: Colors.white,
              child: Text(
                'AM',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
