// Unit tests for ViewCamera and the Web Mercator math that MapigradeController
// uses to convert query positions (design D22). flutter_mapigrade's
// flutter_map_camera_test.dart checks the conversion from and to flutter_map's
// camera.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade/src/camera_projection.dart';
import 'package:mapigrade/src/texture/map_texture_controller.dart';

const viewport = Size(400, 300);

Matcher near(Offset expected, [double tolerance = 1e-9]) =>
    isA<Offset>().having(
      (o) => (o - expected).distance,
      'distance to $expected',
      lessThan(tolerance),
    );

ViewCamera view(double lat, double lon, double zoom, [double bearing = 0]) =>
    ViewCamera(
      MapCamera(latitude: lat, longitude: lon, zoom: zoom, bearing: bearing),
      viewport,
    );

void main() {
  group('mercator', () {
    test('the origin is the center of the world', () {
      expect(mercator(0, 0), near(const Offset(0.5, 0.5)));
    });

    test('longitudes -180 and 180 are the west and east edges', () {
      expect(mercator(0, -180).dx, closeTo(0, 1e-12));
      expect(mercator(0, 180).dx, closeTo(1, 1e-12));
    });

    test('the largest latitude is the north edge, and y increases '
        'southwards', () {
      expect(mercator(maxMercatorLatitude, 0).dy, closeTo(0, 1e-9));
      expect(mercator(-maxMercatorLatitude, 0).dy, closeTo(1, 1e-9));
      expect(mercator(10, 0).dy, lessThan(mercator(-10, 0).dy));
    });

    test('latitudes beyond the largest are clamped', () {
      expect(mercator(89, 0), near(mercator(maxMercatorLatitude, 0)));
      expect(mercator(-89, 0), near(mercator(-maxMercatorLatitude, 0)));
    });
  });

  test('the world is 512 logical pixels wide at zoom 0, and doubles with '
      'each zoom level', () {
    expect(worldSize(0), 512);
    expect(worldSize(1), 1024);
    expect(worldSize(2.5), closeTo(512 * math.pow(2, 2.5), 1e-9));
  });

  group('screenPosition', () {
    test('the camera center is drawn at the viewport center', () {
      final camera = view(48.85, 2.35, 11.5, 30);
      expect(
        screenPosition(camera, mercator(48.85, 2.35)),
        near(viewport.center(Offset.zero), 1e-6),
      );
    });

    test('at bearing 0, a point east of the center is drawn to the right', () {
      const zoom = 10.0;
      const dLon = 0.01;
      expect(
        screenPosition(view(0, 0, zoom), mercator(0, dLon)),
        near(
          viewport.center(Offset.zero) +
              Offset(dLon / 360 * worldSize(zoom), 0),
          1e-6,
        ),
      );
    });

    test('at bearing 90, a point east of the center is drawn above it', () {
      const zoom = 10.0;
      const dLon = 0.01;
      expect(
        screenPosition(view(0, 0, zoom, 90), mercator(0, dLon)),
        near(
          viewport.center(Offset.zero) -
              Offset(0, dLon / 360 * worldSize(zoom)),
          1e-6,
        ),
      );
    });
  });

  group('worldPosition is the inverse of screenPosition', () {
    for (final (lat, lon, zoom, bearing) in const [
      (51.5, -0.12, 13.0, 0.0),
      (48.85, 2.35, 10.5, 30.0),
      (-33.9, 179.9, 8.0, -30.0),
      (80.0, 15.0, 7.25, -50.0),
    ]) {
      test('lat $lat lon $lon zoom $zoom bearing $bearing', () {
        final camera = view(lat, lon, zoom, bearing);
        for (final screen in const [
          Offset.zero,
          Offset(400, 0),
          Offset(123.5, 287.25),
          Offset(400, 300),
        ]) {
          expect(
            screenPosition(camera, worldPosition(camera, screen)),
            near(screen, 1e-6),
          );
        }
      });
    }
  });

  test('ViewCamera.ofFrame has the frame camera and the logical viewport '
      'size', () {
    const camera = MapCamera(latitude: 1, longitude: 2, zoom: 3, bearing: 4);
    final frame = ViewCamera.ofFrame(
      const FrameCamera(
        frameId: 1,
        camera: camera,
        physicalSize: Size(800, 600),
        scaleFactor: 2,
        displayTime: null,
      ),
    );
    expect(frame, ViewCamera(camera, viewport));
  });
}
