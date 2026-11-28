import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/panel.dart';
import '../common/style_picker.dart';
import '../common/styles.dart';

/// The valley of Chamonix, below the Mont Blanc massif.
const _pitched = MapigradeCamera(
  center: LatLng(45.9000, 6.8900),
  zoom: 12.5,
  bearing: 20,
  pitch: 50,
);

const _peaks = [
  ('Mont Blanc', LatLng(45.8326, 6.8652)),
  ('Aiguille du Midi', LatLng(45.8786, 6.8874)),
  ('Aiguille Verte', LatLng(45.9342, 6.9706)),
  ('Le Brévent', LatLng(45.9343, 6.8378)),
  ('Montenvers', LatLng(45.9289, 6.9180)),
];

/// A made-up wind field: at each point, the direction the wind blows toward,
/// in degrees clockwise from north.
final _winds = [
  for (var row = 0; row < 4; row++)
    for (var column = 0; column < 5; column++)
      (
        LatLng(45.86 + row * 0.025, 6.80 + column * 0.045),
        200.0 + 15 * row - 10 * column,
      ),
];

/// The showcase of `MapigradeMap`: pitch and rotation by gesture, upright
/// pins, wind arrows on the ground, taps and long presses.
class PitchScreen extends StatefulWidget {
  const PitchScreen({super.key});

  @override
  State<PitchScreen> createState() => _PitchScreenState();
}

class _PitchScreenState extends State<PitchScreen> {
  final _controller = MapigradeController();
  final _camera = MapigradeCameraController();
  StreamSubscription<CameraChange>? _changes;

  DemoStyle _style = demoStyles.first;
  bool _scalePins = false;
  MapigradeCamera _shown = _pitched;
  String? _tapped;
  final List<LatLng> _dropped = [];

  @override
  void initState() {
    super.initState();
    _changes = _camera.cameraChanges.listen(
      (change) => setState(() => _shown = change.camera),
    );
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  /// Shows [exception] after the frame, because the map can report a
  /// failure while it builds.
  void _showError(MapigradeException exception) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(exception.message)));
    });
  }

  Future<void> _onTap(MapigradeTap tap) async {
    final coordinate = tap.coordinate;
    final where = coordinate == null
        ? 'above the horizon'
        : '${coordinate.latitude.toStringAsFixed(5)}, '
              '${coordinate.longitude.toStringAsFixed(5)}';
    String name;
    try {
      final features = await _controller.queryRenderedFeatures(tap.position);
      final top = features.firstOrNull;
      name = top == null
          ? 'no feature'
          : '${top.properties['name'] ?? 'unnamed feature'}'
                ' (${top.sourceLayerId ?? top.sourceId})';
    } on MapigradeException catch (e) {
      name = e.message;
    } on StateError {
      return;
    }
    if (mounted) setState(() => _tapped = '$where\n$name');
  }

  void _fly(MapigradeCamera camera) {
    _camera.flyTo(camera, duration: const Duration(seconds: 2)).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final c = _shown;
    return Scaffold(
      body: Stack(
        children: [
          MapigradeMap(
            styleUrl: _style.url,
            initialCamera: _pitched,
            controller: _controller,
            cameraController: _camera,
            onError: _showError,
            onTap: _onTap,
            onLongPress: (tap) {
              final coordinate = tap.coordinate;
              if (coordinate != null) {
                setState(() => _dropped.add(coordinate));
              }
            },
            children: [
              MapigradeMarkers(
                markers: [
                  for (final (point, toward) in _winds)
                    MapigradeMarker(
                      coordinate: point,
                      pitchAlignment: MarkerAlignment.map,
                      rotationAlignment: MarkerAlignment.map,
                      child: Transform.rotate(
                        angle: toward * math.pi / 180,
                        child: const Icon(
                          Icons.navigation,
                          size: 36,
                          color: Color(0xCC1565C0),
                        ),
                      ),
                    ),
                  for (final (name, point) in _peaks)
                    MapigradeMarker(
                      coordinate: point,
                      alignment: Alignment.bottomCenter,
                      scaleWithPerspective: _scalePins,
                      child: _Pin(label: name, color: Colors.red),
                    ),
                  for (final point in _dropped)
                    MapigradeMarker(
                      coordinate: point,
                      alignment: Alignment.bottomCenter,
                      scaleWithPerspective: _scalePins,
                      child: const _Pin(color: Colors.deepPurple),
                    ),
                ],
              ),
            ],
          ),
          DemoPanel(
            title: 'Pitch and markers',
            children: [
              StylePicker(
                value: _style,
                onChanged: (style) => setState(() => _style = style),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Scale pins with perspective'),
                value: _scalePins,
                onChanged: (value) => setState(() => _scalePins = value),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        _fly(const MapigradeCamera(bearing: 0, pitch: 0)),
                    child: const Text('Flat'),
                  ),
                  OutlinedButton(
                    onPressed: () => _fly(_pitched),
                    child: const Text('Pitched'),
                  ),
                ],
              ),
              const Divider(),
              Text(
                'Center ${c.center?.latitude.toStringAsFixed(4)}, '
                '${c.center?.longitude.toStringAsFixed(4)}\n'
                'Zoom ${c.zoom?.toStringAsFixed(2)}  '
                'Bearing ${c.bearing?.toStringAsFixed(1)}°  '
                'Pitch ${c.pitch?.toStringAsFixed(1)}°',
                style: small,
              ),
              if (_tapped != null) ...[
                const Divider(),
                Text('Tap: $_tapped', style: small),
              ],
              const Divider(),
              Text(
                'Long-press to drop a pin. The wind arrows show made-up '
                'data.',
                style: small,
              ),
            ],
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: SafeArea(child: _Attribution(_style)),
          ),
        ],
      ),
    );
  }
}

/// A pin whose tip is its bottom center, with an optional label above it.
class _Pin extends StatelessWidget {
  const _Pin({this.label, required this.color});

  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label != null)
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(label!, style: const TextStyle(fontSize: 11)),
          ),
        ),
      Icon(Icons.location_pin, size: 36, color: color),
    ],
  );
}

/// The attribution of [style], as links.
class _Attribution extends StatelessWidget {
  const _Attribution(this.style);

  final DemoStyle style;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Wrap(
      children: [
        for (final (text, url) in attributionEntriesOf(style))
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
            onPressed: () => launchUrl(Uri.parse(url)),
            child: Text(text),
          ),
      ],
    ),
  );
}
