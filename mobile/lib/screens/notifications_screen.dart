import 'package:flutter/material.dart';

import '../widgets/urbaneye_design_system.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_NotificationItem> _notifications = List.of(
    const [
      _NotificationItem(
        id: 'bus-arrival',
        icon: Icons.directions_bus_filled_outlined,
        title: 'Bus arriving soon',
        message: 'Route 42 reaches Central Station in 4 minutes.',
        timestamp: '2 min ago',
        status: 'Upcoming',
        statusBackground: Color(0xFFE0F2FE),
        statusForeground: Color(0xFF0369A1),
      ),
      _NotificationItem(
        id: 'route-update',
        icon: Icons.alt_route_rounded,
        title: 'Route update',
        message: 'Your afternoon route now includes Market Square.',
        timestamp: '12 min ago',
        status: 'Info',
        statusBackground: Color(0xFFEDE9FE),
        statusForeground: Color(0xFF5B21B6),
      ),
      _NotificationItem(
        id: 'incident',
        icon: Icons.warning_amber_rounded,
        title: 'Incident detected',
        message: 'A road incident was reported near Central Junction.',
        timestamp: '28 min ago',
        status: 'Attention',
        statusBackground: Color(0xFFFFE4E6),
        statusForeground: Color(0xFFBE123C),
      ),
      _NotificationItem(
        id: 'driver-reminder',
        icon: Icons.assignment_turned_in_outlined,
        title: 'Driver reminder',
        message: 'Complete the end-of-shift vehicle check.',
        timestamp: '1 hr ago',
        status: 'Reminder',
        statusBackground: Color(0xFFFEF3C7),
        statusForeground: Color(0xFF92400E),
      ),
    ],
  );

  void _dismiss(String id) {
    setState(() =>
        _notifications.removeWhere((notification) => notification.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: GradientHeader(
                eyebrow: 'URBANEYE AI  •  DRIVER UPDATES',
                title: 'Notifications',
                subtitle: _notifications.isEmpty
                    ? 'You are all caught up.'
                    : '${_notifications.length} updates from your vehicle and route.',
                leading: _HeaderBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                footer: StatusChip(
                  label: '${_notifications.length} NEW',
                  backgroundColor: const Color(0xFFE0F2FE),
                  foregroundColor: const Color(0xFF0369A1),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _notifications.isEmpty
                  ? const _EmptyNotifications()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
                        return _NotificationCard(
                          notification: notification,
                          onDismiss: () => _dismiss(notification.id),
                        );
                      },
                    ),
            ),
          ],
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onDismiss,
  });

  final _NotificationItem notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PrimaryCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoTile(
            icon: notification.icon,
            iconColor: notification.statusForeground,
            title: notification.title,
            subtitle: notification.message,
            trailing: StatusChip(
              label: notification.status,
              backgroundColor: notification.statusBackground,
              foregroundColor: notification.statusForeground,
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                notification.timestamp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              TextButton.icon(
                key: Key('dismiss-${notification.id}'),
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: PrimaryCard(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 44,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'No notifications',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'New vehicle and route updates will appear here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _NotificationItem {
  const _NotificationItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.status,
    required this.statusBackground,
    required this.statusForeground,
  });

  final String id;
  final IconData icon;
  final String title;
  final String message;
  final String timestamp;
  final String status;
  final Color statusBackground;
  final Color statusForeground;
}
