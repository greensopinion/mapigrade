// The scenario "Application imports without hiding names" of the package-api
// spec for mapigrade: this file imports the main library with the libraries
// an application uses with it, without a prefix or `hide`, and refers to
// every exported name. An ambiguous import fails compilation, which fails the
// test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/mapigrade.dart';

void main() {
  test('exported names resolve without hiding names of other libraries', () {
    final metrics = MapigradeMetrics();
    final controller = MapigradeController();
    final MapigradeException exception = switch (controller.hashCode % 4) {
      0 => const MapigradeLoadException('load'),
      1 => const MapigradeRenderException('render'),
      2 => const MapigradeQueryException('query'),
      _ => const MapigradeCreateException('create'),
    };
    expect(exception.message, isNotEmpty);
    const feature = QueriedFeature(sourceId: 'roads', id: 1);
    expect(feature.sourceLayerId, isNull);
    const placement = OverlayPlacement.belowLabels();
    final polyline = MapigradePolyline(points: const [LatLng(0, 0)]);
    final polylineLayer = MapigradePolylineLayer(
      polylines: [polyline],
      placement: placement,
    );
    expect(polylineLayer.polylines, [polyline]);
    final MapigradeMetricsSnapshot snapshot = metrics.snapshot();
    expect(snapshot.renderedFrames, 0);
    final rule = HttpHeaderRule(
      url: 'https://example.com/**',
      headers: const {'Authorization': 'Bearer token'},
    );
    expect(<Object>[rule, MaterialApp], hasLength(2));
  });
}
