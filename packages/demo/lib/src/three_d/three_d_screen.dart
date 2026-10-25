import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

import '../common/panel.dart';
import '../common/styles.dart';

/// Midtown Manhattan pitched, with the Liberty style's 3D buildings, a route
/// along Fifth Avenue and markers that face the viewer.
class ThreeDScreen extends StatefulWidget {
  const ThreeDScreen({super.key});

  @override
  State<ThreeDScreen> createState() => _ThreeDScreenState();
}

/// Fifth Avenue from the Empire State Building to Grand Army Plaza.
const _route = [
  LatLng(40.74844, -73.98566),
  LatLng(40.75305, -73.98236),
  LatLng(40.75852, -73.97817),
  LatLng(40.76450, -73.97380),
];

class _ThreeDScreenState extends State<ThreeDScreen> {
  static const _initialPitch = 45.0;

  final _mapController = MapController();
  final _style = demoStyles.firstWhere((s) => s.name == 'Liberty');
  double _pitch = _initialPitch;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(40.7536, -73.9832),
            initialZoom: 16,
            initialPitch: _initialPitch,
            maxPitch: MapOptions.pitchLimit,
            onMapEvent: (event) {
              if (event.camera.pitch != _pitch) {
                setState(() => _pitch = event.camera.pitch);
              }
            },
          ),
          children: [
            MapigradeLayer(
              styleUrl: _style.url,
              children: [
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      strokeWidth: 6,
                      color: Color(0xff1e88e5),
                    ),
                  ],
                ),
                // Pins stand upright, rather than turning with the map.
                MarkerLayer(
                  rotate: true,
                  markers: [
                    for (final point in _route)
                      Marker(
                        point: point,
                        width: 36,
                        height: 36,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_pin,
                          size: 36,
                          color: Color(0xffe53935),
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
          title: '3D view',
          children: [
            Text('Pitch ${_pitch.round()}°'),
            Slider(
              value: _pitch,
              max: MapOptions.pitchLimit,
              onChanged: (value) => _mapController.pitch(value),
            ),
          ],
        ),
      ],
    ),
  );
}
