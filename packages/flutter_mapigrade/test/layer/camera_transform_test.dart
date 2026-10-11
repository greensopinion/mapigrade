// Unit tests for the camera conversion (design D22) and the compensating
// transform (design D23).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show MatrixUtils;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/src/layer/camera_transform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const viewport = Size(400, 300);
const center = Offset(200, 150);

ViewCamera view(double latitude, double longitude, double zoom,
        {double bearing = 0, Size size = viewport}) =>
    ViewCamera(
      MapCamera(
          latitude: latitude,
          longitude: longitude,
          zoom: zoom,
          bearing: bearing),
      size,
    );

/// The latitude and longitude of normalized Mercator coordinates.
(double, double) latLon(Offset world) => (
      math.atan((math.exp(math.pi * (1 - 2 * world.dy)) -
                  math.exp(-math.pi * (1 - 2 * world.dy))) /
              2) *
          180 /
          math.pi,
      world.dx * 360 - 180,
    );

Offset apply(ViewCamera from, ViewCamera to, Offset p) =>
    MatrixUtils.transformPoint(frameTransform(from, to), p);

Matcher near(Offset expected, [double tolerance = 1e-6]) => isA<Offset>()
    .having((o) => (o - expected).distance, 'distance to $expected',
        lessThan(tolerance));

const points = [
  Offset(0, 0),
  Offset(400, 0),
  Offset(0, 300),
  Offset(400, 300),
  center,
  Offset(123.4, 56.7),
];

void main() {
  test('equal cameras give the identity', () {
    final camera = view(51.5, -0.1, 14.3, bearing: 20);
    for (final p in points) {
      expect(apply(camera, camera, p), near(p));
    }
  });

  test('a pure pan moves points by the pan offset', () {
    // 10 logical px east at zoom 3.
    final dLon = 10 / worldSize(3) * 360;
    final from = view(0, 5, 3);
    final to = view(0, 5 + dLon, 3);
    for (final p in points) {
      expect(apply(from, to, p), near(p - const Offset(10, 0)));
    }
  });

  test('a zoom difference of 1 scales by 2 about the viewport center', () {
    final from = view(40, 10, 6);
    final to = view(40, 10, 7);
    expect(apply(from, to, center), near(center));
    for (final p in points) {
      expect(apply(from, to, p), near(center + (p - center) * 2));
    }
  });

  test('a bearing difference rotates as MapLibre bearing does', () {
    // MapLibre bearing 90 puts east at the top: a point east of the center
    // in a north-up frame appears above the center.
    final from = view(0, 0, 4);
    final to = view(0, 0, 4, bearing: 90);
    expect(apply(from, to, center + const Offset(10, 0)),
        near(center + const Offset(0, -10)));
    // flutter_map rotation -90 is MapLibre bearing 90 (D22).
    final fmCamera = fm.MapCamera(
      crs: const fm.Epsg3857(),
      center: const LatLng(0, 0),
      zoom: 5,
      rotation: -90,
      nonRotatedSize: viewport,
    );
    expect(viewCameraOf(fmCamera).camera.bearing, 90);
  });

  test('a pan across the antimeridian takes the shorter way', () {
    final from = view(10, 179.99, 8);
    final to = view(10, -179.99, 8);
    // 0.02 degrees east.
    final shift = 0.02 / 360 * worldSize(8);
    for (final p in points) {
      expect(apply(from, to, p), near(p - Offset(shift, 0), 1e-4));
    }
  });

  test('a frame with another viewport size is placed by its own center', () {
    final from = view(30, 30, 10, size: const Size(200, 100));
    final to = view(30, 30, 10);
    expect(apply(from, to, const Offset(100, 50)), near(center));
    expect(apply(from, to, Offset.zero), near(const Offset(100, 100)));
  });

  test('the transform maps where the frame draws a point to where the target '
      'camera draws it', () {
    final from = view(60, 20, 9.4, bearing: -35, size: const Size(380, 320));
    final to = view(60.01, 20.03, 9.9, bearing: 12);
    for (final ll in const [Offset(60.02, 20.05), Offset(59.99, 19.98)]) {
      final world = mercator(ll.dx, ll.dy);
      expect(apply(from, to, screenPosition(from, world)),
          near(screenPosition(to, world), 1e-6));
    }
  });

  group('layerTransform', () {
    final dLon = 1 / worldSize(3) * 360;
    test('keeps the transform while part of the frame is in view', () {
      // 350 px east: 50 px of the 400 px wide frame stay in view.
      expect(layerTransform(view(0, 5, 3), view(0, 5 + 350 * dLon, 3)),
          isNotNull);
    });

    test('drops the transform when the frame would be entirely out of view',
        () {
      expect(layerTransform(view(0, 5, 3), view(0, 5 + 450 * dLon, 3)),
          isNull);
      expect(layerTransform(view(0, 5, 3), view(0, 5 - 450 * dLon, 3)),
          isNull);
    });

    test('tests the rotated frame, not its bounding box', () {
      // The frame, rotated by 45 degrees, is centered at (-200, -200): its
      // bounding box reaches 247.5 px from its center and overlaps the
      // viewport, but along the diagonal it ends 83 px short of it.
      final to = view(20, 10, 6);
      final (lat, lon) = latLon(worldPosition(to, const Offset(-200, -200)));
      final from = view(lat, lon, 6, bearing: 45);
      final m = frameTransform(from, to);
      expect(MatrixUtils.transformPoint(m, center),
          near(const Offset(-200, -200), 1e-6));
      final box = MatrixUtils.transformRect(m, Offset.zero & viewport);
      expect(box.overlaps(Offset.zero & viewport), isTrue);
      expect(layerTransform(from, to), isNull);
      // Moved 100 px towards the viewport along the diagonal, it overlaps.
      final (lat2, lon2) =
          latLon(worldPosition(to, const Offset(-130, -130)));
      expect(layerTransform(view(lat2, lon2, 6, bearing: 45), to), isNotNull);
    });
  });

  group('the converted camera places coordinates where flutter_map does', () {
    for (final (lat, lon, zoom, rotation) in const [
      (51.5, -0.12, 14.0, 0.0),
      (51.5, -0.12, 13.37, 0.0),
      (48.85, 2.35, 11.5, 30.0),
      (80.0, 15.0, 7.25, -50.0),
      (-33.9, 179.6, 9.0, 10.0),
    ]) {
      test('lat $lat lon $lon zoom $zoom rotation $rotation', () {
        final camera = fm.MapCamera(
          crs: const fm.Epsg3857(),
          center: LatLng(lat, lon),
          zoom: zoom,
          rotation: rotation,
          nonRotatedSize: viewport,
        );
        final converted = viewCameraOf(camera);
        expect(converted.viewport, viewport);
        for (final (dLat, dLon) in const [
          (0.0, 0.0),
          (0.003, 0.004),
          (-0.002, 0.006),
        ]) {
          final ll = LatLng(lat + dLat, lon + dLon);
          expect(screenPosition(converted, mercator(ll.latitude, ll.longitude)),
              near(camera.latLngToScreenOffset(ll), 1e-3));
        }
      });
    }
  });
}
