import 'package:flutter/material.dart';

class LiveGpsScreen extends StatelessWidget {
  const LiveGpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live GPS')),
      body: const Center(
        child: Card(
          margin: EdgeInsets.all(20),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'GPS streaming placeholder\n\nIntegrate geolocator and backend sync here.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
