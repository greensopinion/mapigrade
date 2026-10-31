import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

import 'src/flyover/flyover_screen.dart';
import 'src/common/recording.dart';
import 'src/gallery.dart';
import 'src/inspect/inspect_screen.dart';
import 'src/routes/routes_screen.dart';

void main() {
  final recording = Recording.fromEnvironment();
  runApp(DemoApp(recording: recording));
}

final _showcases = [
  Showcase(
    'Flyover',
    'Fly along three stages of the Tour de France Femmes 2026, change the '
        'style, and watch the frame rates.',
    (context) => const FlyoverScreen(),
  ),
  Showcase(
    'Inspect features',
    'Tap a road, building or label to highlight it and see its properties.',
    (context) => const InspectScreen(),
  ),
  Showcase(
    '3D routes',
    'Tilt downtown New York to see routes drawn below its 3D buildings and '
        'labels, with pins that stand upright.',
    (context) => const RoutesScreen(),
  ),
];

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, this.recording});

  final Recording? recording;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mapigrade demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    // Where the native library isn't available, the layer would draw nothing.
    // The recording mode opens its showcase without the gallery (design
    // D190, D213).
    home: !MapigradeLayer.isSupported
        ? const _UnsupportedScreen()
        : switch (recording?.showcase) {
            null => Gallery(showcases: _showcases),
            RecordingShowcase.flyover => FlyoverScreen(recording: recording),
            RecordingShowcase.routes3d => RoutesScreen(recording: recording),
          },
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
