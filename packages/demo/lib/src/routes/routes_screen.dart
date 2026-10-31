import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

import '../common/panel.dart';
import '../common/recording.dart';
import '../common/style_picker.dart';
import '../common/styles.dart';
import 'routes.dart';

/// The Financial District, between Broadway, Wall Street and West Street.
const _initialCenter = LatLng(40.7075, -74.0110);
const _initialZoom = 16.0;
const _initialPitch = 45.0;

const _orbitZoom = 16.0;
const _orbitPitch = 62.0;

/// A full turn every 30 s.
const _orbitDegreesPerSecond = 12.0;

/// The 3D routes showcase: routes through downtown New York drawn by
/// `MapigradePolylineLayer`, below the 3D buildings and labels or on top, with
/// upright pins at their ends, on a map that tilts and orbits downtown
/// (design D209, D210, D212).
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key, this.recording});

  /// The recording mode, or null (design D213).
  final Recording? recording;

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  final _metrics = LayerMetrics();
  late final Ticker _orbit = createTicker(_turn);
  double _orbitStartRotation = 0;
  late final _recording = widget.recording;
  bool _recordingStarted = false;
  bool _warmingUp = false;
  DemoStyle _style = demoStyles.first;
  double _pitch = _initialPitch;
  LayerPlacement _placement = const LayerPlacement.belowLabels();

  @override
  void dispose() {
    _orbit.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _playOrStopOrbit() {
    if (_orbit.isActive) {
      _stopOrbit();
    } else {
      _startOrbit(_mapController.camera.rotation);
    }
  }

  void _moveToOrbitStart(double rotation) {
    _mapController.moveAndRotate(_initialCenter, _orbitZoom, rotation);
    _mapController.pitch(_orbitPitch);
  }

  void _startOrbit(double rotation) {
    _moveToOrbitStart(rotation);
    _orbitStartRotation = rotation;
    setState(_orbit.start);
  }

  void _stopOrbit() {
    if (_orbit.isActive) setState(_orbit.stop);
  }

  void _turn(Duration elapsed) {
    _mapController.rotate(
      _orbitStartRotation +
          _orbitDegreesPerSecond *
              elapsed.inMicroseconds /
              Duration.microsecondsPerSecond,
    );
    final recording = _recording;
    if (recording != null && _warmingUp && elapsed >= recording.warmUp) {
      _warmingUp = false;
      _stopOrbit();
      _moveToOrbitStart(0);
      recording.ready(_metrics).then((_) {
        if (mounted) _startOrbit(0);
      });
    }
  }

  /// In the recording mode, plays the orbit as the warm-up pass once the
  /// style has loaded, facing north (design D213).
  void _onStyleLoaded() {
    final recording = _recording;
    if (recording == null || _recordingStarted) return;
    _recordingStarted = true;
    _warmingUp = true;
    recording.log('warm-up ${recording.warmUp.inSeconds} s');
    _startOrbit(0);
  }

  /// Any camera change that isn't the screen's own stops the orbit, as on
  /// the flyover screen (design D119).
  void _onMapEvent(MapEvent event) {
    if (event.source != MapEventSource.mapController &&
        event.source != MapEventSource.nonRotatedSizeChange) {
      _stopOrbit();
    }
    if (event.camera.pitch != _pitch) {
      setState(() => _pitch = event.camera.pitch);
    }
  }

  /// Shows [exception] after the frame, because the layer can report a
  /// failure while it builds.
  void _showError(LayerException exception) {
    if (_recording != null) Recording.fail(exception.message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(exception.message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              initialPitch: _initialPitch,
              maxPitch: MapOptions.pitchLimit,
              onMapEvent: _onMapEvent,
              onPointerDown: (_, _) => _stopOrbit(),
            ),
            children: [
              MapigradeLayer(
                styleUrl: _style.url,
                onError: _showError,
                onStyleLoaded: _onStyleLoaded,
                metrics: _metrics,
                children: [
                  MapigradePolylineLayer(
                    polylines: demoRoutePolylines,
                    placement: _placement,
                  ),
                  // Pins stand upright, rather than turning with the map.
                  MarkerLayer(
                    rotate: true,
                    markers: [
                      for (final pin in demoRoutePins)
                        Marker(
                          point: pin.point,
                          width: 36,
                          height: 36,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.location_pin,
                            size: 36,
                            color: pin.color,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              attributionOf(_style),
            ],
          ),
          DemoPanel(
            title: '3D routes',
            actions: [
              IconButton(
                tooltip: _orbit.isActive ? 'Stop orbit' : 'Play orbit',
                icon: Icon(_orbit.isActive ? Icons.stop : Icons.play_arrow),
                onPressed: _playOrStopOrbit,
              ),
            ],
            children: [
              StylePicker(
                value: _style,
                onChanged: (style) => setState(() => _style = style),
              ),
              const SizedBox(height: 8),
              Text('Pitch ${_pitch.round()}°'),
              Slider(
                value: _pitch,
                max: MapOptions.pitchLimit,
                onChanged: (value) => _mapController.pitch(value),
              ),
              const SizedBox(height: 8),
              SegmentedButton<LayerPlacement>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LayerPlacement.belowLabels(),
                    label: Text('Below buildings and labels'),
                  ),
                  ButtonSegment(
                    value: LayerPlacement.top(),
                    label: Text('On top'),
                  ),
                ],
                selected: {_placement},
                onSelectionChanged: (selected) =>
                    setState(() => _placement = selected.single),
              ),
              const Divider(),
              for (final route in demoRoutes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _Swatch(route.polyline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${route.name}: ${route.drawnAs}',
                          style: small,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short sample of how [polyline] is drawn, for the legend.
class _Swatch extends StatelessWidget {
  const _Swatch(this.polyline);

  final MapigradePolyline polyline;

  @override
  Widget build(BuildContext context) {
    final gradient = polyline.gradientColors;
    return Container(
      width: 24,
      height: 6,
      decoration: BoxDecoration(
        color: gradient == null ? polyline.color : null,
        gradient: gradient == null ? null : LinearGradient(colors: gradient),
        border: polyline.borderStrokeWidth > 0
            ? Border.all(color: polyline.borderColor)
            : null,
      ),
    );
  }
}
