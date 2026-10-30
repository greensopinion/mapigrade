import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade_demo/src/polylines/routes.dart';

/// Downtown New York, south of Canal Street, and the water beside it.
bool _inDowntown(LatLng p) =>
    p.latitude > 40.695 &&
    p.latitude < 40.720 &&
    p.longitude > -74.020 &&
    p.longitude < -74.000;

void main() {
  test('the routes are in draw order', () {
    expect([for (final r in demoRoutes) r.name], [
      'Broadway',
      'Staten Island Ferry',
      'West Street',
      'Wall Street',
    ]);
  });

  test('every route has at least two points in downtown New York', () {
    for (final r in demoRoutes) {
      expect(
        r.polyline.points.where(_inDowntown).length,
        greaterThanOrEqualTo(2),
        reason: r.name,
      );
    }
  });

  test('the polylines are created once', () {
    expect(identical(demoRoutes, demoRoutes), isTrue);
    expect(identical(demoRoutePolylines, demoRoutePolylines), isTrue);
    for (final (i, r) in demoRoutes.indexed) {
      expect(identical(demoRoutePolylines[i], r.polyline), isTrue);
    }
  });
}
