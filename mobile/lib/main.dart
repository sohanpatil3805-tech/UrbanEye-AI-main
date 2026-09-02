import 'package:flutter/material.dart';

import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_gps_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  runApp(const UrbanEyeApp());
}

class UrbanEyeApp extends StatefulWidget {
  const UrbanEyeApp({super.key});

  @override
  State<UrbanEyeApp> createState() => _UrbanEyeAppState();
}

class _UrbanEyeAppState extends State<UrbanEyeApp> {
  bool _darkModeEnabled = false;

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UrbanEye AI',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _darkModeEnabled ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/gps': (context) => const LiveGpsScreen(),
        '/camera': (context) => const CameraScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/profile': (context) => ProfileScreen(
              darkModeEnabled: _darkModeEnabled,
              onDarkModeChanged: (enabled) {
                setState(() => _darkModeEnabled = enabled);
              },
            ),
      },
    );
  }
}
