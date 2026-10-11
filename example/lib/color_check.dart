// Color check (task 3.5): a map with a style of known colors, and Flutter
// swatches of the same colors beside it. Compare pixels of a screenshot:
// the map's left half (fill), the map's right half (background), and the two
// swatches in the bottom strip must match within 2/255 per channel.
//
//   flutter run -d macos -t lib/color_check.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

const backgroundColor = Color(0xFF3366CC);
const fillColor = Color(0xFFE6B31A);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

final style = jsonEncode({
  'version': 8,
  'sources': {
    'west': {
      'type': 'geojson',
      'data': {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [-179, -80],
              [0, -80],
              [0, 80],
              [-179, 80],
              [-179, -80],
            ]
          ],
        },
      },
    },
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': _hex(backgroundColor)},
    },
    {
      'id': 'west',
      'type': 'fill',
      'source': 'west',
      'paint': {'fill-color': _hex(fillColor), 'fill-antialias': false},
    },
  ],
});

void main() => runApp(const MaterialApp(home: ColorCheck()));

class ColorCheck extends StatefulWidget {
  const ColorCheck({super.key});

  @override
  State<ColorCheck> createState() => _ColorCheckState();
}

class _ColorCheckState extends State<ColorCheck> {
  MapTextureController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = MapTextureController.create(
        pixelRatio: MediaQuery.devicePixelRatioOf(context));
    controller.events.listen((event) => debugPrint('map event: $event'));
    controller.loadStyleJson(style);
    controller.setCamera(
        const MapCamera(latitude: 0, longitude: 0, zoom: 2));
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Expanded(child: MapTextureView(controller: _controller!)),
          const SizedBox(
            height: 100,
            child: Row(children: [
              Expanded(child: ColoredBox(color: fillColor, child: SizedBox.expand())),
              Expanded(child: ColoredBox(color: backgroundColor, child: SizedBox.expand())),
            ]),
          ),
        ]),
      );
}
