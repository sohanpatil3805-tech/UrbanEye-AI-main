import 'package:flutter/material.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: const Center(
        child: Card(
          margin: EdgeInsets.all(20),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Camera upload placeholder\n\nIntegrate camera plugin and /upload endpoint here.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
