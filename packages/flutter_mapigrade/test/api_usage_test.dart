// The scenario "Application imports without hiding names" of the package-api
// spec (design D70 of the public-api change): this file imports the main
// library with the libraries an application uses with it, without a prefix
// or `hide`, and refers to every exported name. An ambiguous import fails
// compilation, which fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('exported names resolve without hiding names of other libraries', () {
    const layer = MapigradeLayer(
      styleUrl: 'https://example.com/style.json',
      alignment: LayerAlignment.none,
    );
    final map = FlutterMap(
      options: const MapOptions(initialCenter: LatLng(0, 0)),
      children: [
        if (MapigradeLayer.isSupported)
          layer
        else
          TileLayer(urlTemplate: 'https://tile.example.com/{z}/{x}/{y}.png'),
      ],
    );
    final LayerException exception = switch (map.children.length) {
      0 => const LayerLoadException('load'),
      1 => const LayerRenderException('render'),
      _ => const LayerCreateException('create'),
    };
    expect(exception, isA<LayerRenderException>());
    expect(<Type>[
      MapigradeLayer,
      LayerAlignment,
      LayerException,
      LayerLoadException,
      LayerRenderException,
      LayerCreateException,
      MaterialApp,
    ], hasLength(7));
  });
}
