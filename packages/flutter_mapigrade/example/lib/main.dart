import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const ExampleApp());

const _vancouver = LatLng(49.2827, -123.1207);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_mapigrade example',
    scaffoldMessengerKey: _messenger,
    home: Scaffold(
      body: FlutterMap(
        options: const MapOptions(initialCenter: _vancouver, initialZoom: 12),
        children: [
          // The base layer: first among the children, so that the layers
          // after it are drawn above it.
          MapigradeLayer(
            styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
            onError: _showError,
          ),
          const MarkerLayer(
            markers: [
              Marker(
                point: _vancouver,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: Icon(Icons.location_pin, size: 40, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

final _messenger = GlobalKey<ScaffoldMessengerState>();

void _showError(LayerException exception) {
  _messenger.currentState?.showSnackBar(
    SnackBar(content: Text(exception.message)),
  );
}
