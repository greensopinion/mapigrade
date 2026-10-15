import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

import 'src/map_screen.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mapigrade demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    // Where the native library isn't available, the layer would draw nothing.
    home: MapigradeLayer.isSupported
        ? const MapScreen()
        : const _UnsupportedScreen(),
  );
}

class _UnsupportedScreen extends StatelessWidget {
  const _UnsupportedScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The map isn\'t supported on this device: '
          'flutter_mapigrade\'s native library isn\'t available.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
