// The map as the base layer of a FlutterMap, with marker and polyline
// overlays (task 3.3 of the flutter-map-layer change). Open it from the
// control panel, or at launch with `--dart-define=FLUTTER_MAP_PAGE=true`.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

import 'alignment_mode.dart';
import 'benchmark.dart' show copyFree;

const flutterMapPageAtLaunch = bool.fromEnvironment('FLUTTER_MAP_PAGE');

/// Charing Cross, St Paul's Cathedral and the Tower of London.
const landmarks = [
  LatLng(51.5080, -0.1247),
  LatLng(51.5138, -0.0984),
  LatLng(51.5081, -0.0759),
];

class FlutterMapPage extends StatefulWidget {
  const FlutterMapPage({super.key, required this.styleUrl});

  final String styleUrl;

  @override
  State<FlutterMapPage> createState() => _FlutterMapPageState();
}

class _FlutterMapPageState extends State<FlutterMapPage> {
  final _mapController = MapController();
  String _camera = '';
  FrameCamera? _frame;
  AlignmentMode _mode = AlignmentMode.transform;

  void _onController(MapTextureController controller) {
    controller.frames.listen((f) {
      if (mounted) setState(() => _frame = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(51.5110, -0.1000),
              initialZoom: 14,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, _) => setState(
                () => _camera =
                    '${camera.center.latitude.toStringAsFixed(4)}, '
                    '${camera.center.longitude.toStringAsFixed(4)} '
                    'z${camera.zoom.toStringAsFixed(2)} '
                    'r${camera.rotation.toStringAsFixed(0)}',
              ),
            ),
            children: [
              MapLibreTextureLayer(
                styleUrl: widget.styleUrl,
                copyFree: copyFree,
                compensatingTransform: _mode.compensatingTransform,
                cameraPrediction: _mode.cameraPrediction,
                onController: _onController,
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: landmarks,
                    strokeWidth: 6,
                    color: Colors.deepPurple.withValues(alpha: 0.8),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final point in landmarks)
                    Marker(
                      point: point,
                      width: 24,
                      height: 24,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: Card(
                key: const Key('flutter-map-panel'),
                color: Colors.white.withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              key: const Key('flutter-map-back'),
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                            ),
                          IconButton(
                            key: const Key('flutter-map-north'),
                            icon: const Icon(Icons.navigation),
                            tooltip: 'Reset rotation',
                            onPressed: () => _mapController.rotate(0),
                          ),
                        ],
                      ),
                      SegmentedButton<AlignmentMode>(
                        key: const Key('flutter-map-mode'),
                        showSelectedIcon: false,
                        segments: [
                          for (final mode in const [
                            AlignmentMode.transform,
                            AlignmentMode.none,
                            AlignmentMode.predict1,
                            AlignmentMode.predict2,
                          ])
                            ButtonSegment(value: mode, label: Text(mode.label)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) =>
                            setState(() => _mode = s.single),
                      ),
                      Text('flutter_map: $_camera'),
                      Text(
                        frame == null
                            ? 'Displayed: -'
                            : 'Displayed #${frame.frameId}: '
                                  'z${frame.camera.zoom.toStringAsFixed(2)} '
                                  'b${frame.camera.bearing.toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
