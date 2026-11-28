// The scenarios "Application imports without hiding names" and "Both
// packages imported" of the package-api spec (design D70 of the public-api
// change): this file imports the main library with the libraries an
// application uses with it, and with mapigrade's main library, without a
// prefix or `hide`, and refers to every exported name. An ambiguous import fails
// compilation, which fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
// The scenario imports both libraries; the unused second import is the test.
// ignore: unnecessary_import
import 'package:mapigrade/mapigrade.dart';

void main() {
  test('exported names resolve without hiding names of other libraries', () {
    final metrics = MapigradeMetrics();
    final controller = MapigradeController();
    final layer = MapigradeLayer(
      styleUrl: 'https://example.com/style.json',
      alignment: LayerAlignment.none,
      metrics: metrics,
      controller: controller,
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
    final MapigradeException exception = switch (map.children.length) {
      0 => const MapigradeLoadException('load'),
      1 => const MapigradeRenderException('render'),
      2 => const MapigradeQueryException('query'),
      _ => const MapigradeCreateException('create'),
    };
    const feature = QueriedFeature(sourceId: 'roads', id: 1);
    expect(feature.sourceLayerId, isNull);
    expect(exception, isA<MapigradeRenderException>());
    const placement = OverlayPlacement.belowLabels();
    final polyline = MapigradePolyline(points: const [LatLng(0, 0)]);
    final polylineLayer = MapigradePolylineLayer(
      polylines: [polyline],
      placement: placement,
    );
    expect(polylineLayer.polylines, [polyline]);
    final MapigradeMetricsSnapshot snapshot = metrics.snapshot();
    expect(snapshot.renderedFrames, 0);
    expect(<Type>[
      MapigradeLayer,
      LayerAlignment,
      MapigradeException,
      MapigradeLoadException,
      MapigradeRenderException,
      MapigradeCreateException,
      MapigradeQueryException,
      MapigradeController,
      QueriedFeature,
      MapigradePolyline,
      MapigradePolylineLayer,
      OverlayPlacement,
      MaterialApp,
      HttpHeaderRule,
    ], hasLength(14));
  });
}
