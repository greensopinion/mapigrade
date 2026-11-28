import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';

void main() => runApp(const ExampleApp());

const _vancouver = LatLng(49.2827, -123.1207);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'mapigrade example',
    scaffoldMessengerKey: _messenger,
    home: Scaffold(
      body: MapigradeMap(
        styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
        initialCamera: const MapigradeCamera(
          center: _vancouver,
          zoom: 14,
          bearing: 30,
          pitch: 50,
        ),
        onError: _showError,
        children: [
          MapigradeMarkers(
            markers: const [
              MapigradeMarker(
                coordinate: _vancouver,
                alignment: Alignment.bottomCenter,
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

void _showError(MapigradeException exception) {
  _messenger.currentState?.showSnackBar(
    SnackBar(content: Text(exception.message)),
  );
}
