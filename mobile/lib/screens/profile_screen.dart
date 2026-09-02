import 'package:flutter/material.dart';

import '../widgets/urbaneye_design_system.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.darkModeEnabled,
    required this.onDarkModeChanged,
    super.key,
  });

  final bool darkModeEnabled;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _routeUpdatesEnabled = true;
  bool _safetyAlertsEnabled = true;
  bool _driverRemindersEnabled = true;
  late bool _darkModeEnabled;

  @override
  void initState() {
    super.initState();
    _darkModeEnabled = widget.darkModeEnabled;
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.darkModeEnabled != widget.darkModeEnabled) {
      _darkModeEnabled = widget.darkModeEnabled;
    }
  }

  void _updateDarkMode(bool enabled) {
    setState(() => _darkModeEnabled = enabled);
    widget.onDarkModeChanged(enabled);
  }

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
                eyebrow: 'URBANEYE AI  •  DRIVER ACCOUNT',
                title: 'Profile',
                subtitle: 'Driver account and app settings.',
                leading: _HeaderBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                footer: const StatusChip(
                  label: 'DRIVER',
                  backgroundColor: Color(0xFFE0F2FE),
                  foregroundColor: Color(0xFF0369A1),
                ),
              ),
              const SizedBox(height: 28),
              const _DriverIdentity(),
              const SizedBox(height: 28),
              const _SectionLabel('Vehicle'),
              const SizedBox(height: 12),
              const PrimaryCard(
                child: InfoTile(
                  icon: Icons.directions_bus_filled_outlined,
                  title: 'Assigned Bus',
                  subtitle: 'UE-1024',
                  trailing: StatusChip(
                    label: 'ACTIVE',
                    backgroundColor: Color(0xFFF0FDF4),
                    foregroundColor: Color(0xFF15803D),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Preferences'),
              const SizedBox(height: 12),
              PrimaryCard(
                child: Column(
                  children: [
                    const InfoTile(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Choose which updates you receive.',
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.alt_route_rounded),
                      title: const Text('Route updates'),
                      subtitle: const Text('Changes to your assigned route.'),
                      value: _routeUpdatesEnabled,
                      onChanged: (value) {
                        setState(() => _routeUpdatesEnabled = value);
                      },
                    ),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.health_and_safety_outlined),
                      title: const Text('Safety alerts'),
                      subtitle:
                          const Text('Important vehicle and route alerts.'),
                      value: _safetyAlertsEnabled,
                      onChanged: (value) {
                        setState(() => _safetyAlertsEnabled = value);
                      },
                    ),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.event_note_outlined),
                      title: const Text('Driver reminders'),
                      subtitle:
                          const Text('Shift and vehicle check reminders.'),
                      value: _driverRemindersEnabled,
                      onChanged: (value) {
                        setState(() => _driverRemindersEnabled = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Appearance'),
              const SizedBox(height: 12),
              PrimaryCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Use a darker color theme.'),
                  value: _darkModeEnabled,
                  onChanged: _updateDarkMode,
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('About'),
              const SizedBox(height: 12),
              const PrimaryCard(
                child: InfoTile(
                  icon: Icons.info_outline_rounded,
                  title: 'App Version',
                  subtitle: '1.0.0',
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

class _DriverIdentity extends StatelessWidget {
  const _DriverIdentity();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2563EB), Color(0xFF4338CA)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'AM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Alex Morgan',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Driver ID',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        const StatusChip(
          label: 'UE-DR-1024',
          backgroundColor: Color(0xFFEFF6FF),
          foregroundColor: Color(0xFF1D4ED8),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}
