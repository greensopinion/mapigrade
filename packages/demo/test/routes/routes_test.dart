import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade_demo/src/routes/routes.dart';

/// Downtown New York, south of Canal Street, and the water beside it.
bool _inDowntown(LatLng p) =>
    p.latitude > 40.695 &&
    p.latitude < 40.720 &&
    p.longitude > -74.020 &&
    p.longitude < -74.000;

void main() {
  test('the routes are in draw order', () {
    expect(
      [for (final r in demoRoutes) r.name],
      ['Broadway', 'Staten Island Ferry', 'West Street', 'Wall Street'],
    );
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

  test('each route has an opaque pin at its start and its end', () {
    expect(demoRoutePins, hasLength(2 * demoRoutes.length));
    for (final (i, r) in demoRoutes.indexed) {
      final start = demoRoutePins[2 * i];
      final end = demoRoutePins[2 * i + 1];
      expect(start.point, r.polyline.points.first, reason: r.name);
      expect(end.point, r.polyline.points.last, reason: r.name);
      expect(start.color.a, 1.0, reason: r.name);
      expect(end.color.a, 1.0, reason: r.name);
    }
  });

  test('the gradient route has pins in its first and last colors', () {
    final i = demoRoutes.indexWhere((r) => r.polyline.gradientColors != null);
    final colors = demoRoutes[i].polyline.gradientColors!;
    expect(demoRoutePins[2 * i].color, colors.first);
    expect(demoRoutePins[2 * i + 1].color, colors.last);
  });

  test('the translucent route has a pin in its color, opaque', () {
    final wall = demoRoutes.indexWhere((r) => r.name == 'Wall Street');
    expect(
      demoRoutePins[2 * wall].color,
      demoRoutes[wall].polyline.color.withAlpha(255),
    );
  });
}
