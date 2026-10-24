import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

import 'src/flyover/flyover_screen.dart';
import 'src/flyover/recording.dart';
import 'src/gallery.dart';
import 'src/inspect/inspect_screen.dart';

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
    // The recording mode opens the flyover without the gallery (design D190).
    home: !MapigradeLayer.isSupported
        ? const _UnsupportedScreen()
        : recording != null
        ? FlyoverScreen(recording: recording)
        : Gallery(showcases: _showcases),
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
