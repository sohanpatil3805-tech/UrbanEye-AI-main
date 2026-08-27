import 'package:flutter/material.dart';

import 'screens/camera_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_gps_screen.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const UrbanEyeApp());
}

class UrbanEyeApp extends StatelessWidget {
  const UrbanEyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UrbanEye AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/gps': (context) => const LiveGpsScreen(),
        '/camera': (context) => const CameraScreen(),
      },
    );
  }
}
