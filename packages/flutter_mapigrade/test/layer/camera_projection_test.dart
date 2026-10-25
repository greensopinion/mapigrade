// Unit tests for the camera conversion (design D22).
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_mapigrade/src/layer/camera_projection.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const viewport = Size(400, 300);

Matcher near(Offset expected, [double tolerance = 1e-6]) =>
    isA<Offset>().having(
      (o) => (o - expected).distance,
      'distance to $expected',
      lessThan(tolerance),
    );

void main() {
  group('the built flutter_map camera converts back to the camera', () {
    for (final (lat, lon, zoom, bearing, pitch) in const [
      (51.5, -0.12, 13.0, 0.0, 0.0),
      (48.85, 2.35, 10.5, 30.0, 0.0),
      (-33.9, 179.9, 8.0, -30.0, 0.0),
      (-33.9, -180.0, 8.0, 30.0, 0.0),
      (12.0, 179.999, 4.25, 0.0, 0.0),
      (48.85, 2.35, 10.5, 30.0, 45.0),
      (-33.9, 179.9, 8.0, -30.0, 60.0),
    ]) {
      test('lat $lat lon $lon zoom $zoom bearing $bearing pitch $pitch', () {
        final live = fm.MapCamera(
          crs: const fm.Epsg3857(),
          center: const LatLng(0, 0),
          zoom: 3,
          rotation: 0,
          nonRotatedSize: viewport,
          minZoom: 2,
          maxZoom: 18,
        );
        final camera = MapCamera(
          latitude: lat,
          longitude: lon,
          zoom: zoom,
          bearing: bearing,
          pitch: pitch,
        );
        final built = flutterMapCameraOf(camera, live);
        expect(built.pitch, pitch);
        expect(viewCameraOf(built), ViewCamera(camera, viewport));
        expect(built.crs, live.crs);
        expect(built.minZoom, 2);
        expect(built.maxZoom, 18);
      });
    }
  });

  group('the converted camera places coordinates where flutter_map does', () {
    for (final (lat, lon, zoom, rotation, pitch) in const [
      (51.5, -0.12, 14.0, 0.0, 0.0),
      (51.5, -0.12, 13.37, 0.0, 0.0),
      (48.85, 2.35, 11.5, 30.0, 0.0),
      (80.0, 15.0, 7.25, -50.0, 0.0),
      (-33.9, 179.6, 9.0, 10.0, 0.0),
      (48.85, 2.35, 11.5, 30.0, 45.0),
      (-33.9, 179.6, 9.0, 10.0, 60.0),
    ]) {
      test('lat $lat lon $lon zoom $zoom rotation $rotation pitch $pitch', () {
        final camera = fm.MapCamera(
          crs: const fm.Epsg3857(),
          center: LatLng(lat, lon),
          zoom: zoom,
          rotation: rotation,
          nonRotatedSize: viewport,
          pitch: pitch,
        );
        final converted = viewCameraOf(camera);
        expect(converted.viewport, viewport);
        for (final (dLat, dLon) in const [
          (0.0, 0.0),
          (0.003, 0.004),
          (-0.002, 0.006),
        ]) {
          final ll = LatLng(lat + dLat, lon + dLon);
          expect(
            screenPosition(converted, mercator(ll.latitude, ll.longitude)),
            near(camera.latLngToScreenOffset(ll), 1e-3),
          );
        }
      });
    }
  });

  group('worldPosition inverts screenPosition', () {
    for (final (lon, bearing, pitch) in const [
      (2.35, 0.0, 0.0),
      (2.35, -30.0, 45.0),
      (2.35, 20.0, 60.0),
      (179.95, -90.0, 60.0),
    ]) {
      test('lon $lon bearing $bearing pitch $pitch', () {
        final view = ViewCamera(
          MapCamera(
            latitude: 48.85,
            longitude: lon,
            zoom: 10,
            bearing: bearing,
            pitch: pitch,
          ),
          viewport,
        );
        for (double x = 0; x <= viewport.width; x += 100) {
          for (double y = 0; y <= viewport.height; y += 75) {
            final screen = Offset(x, y);
            expect(
              screenPosition(view, worldPosition(view, screen)),
              near(screen, 1e-6),
            );
          }
        }
      });
    }

    test('across the antimeridian, the longitude is not limited', () {
      // With bearing 90 (flutter_map rotation -90) and pitch 60, the top of
      // the view is east of the center, across the antimeridian.
      const view = ViewCamera(
        MapCamera(
          latitude: 0,
          longitude: 179.95,
          zoom: 10,
          bearing: 90,
          pitch: 60,
        ),
        viewport,
      );
      final world = worldPosition(view, const Offset(200, 0));
      expect(world.dx, greaterThan(1));
    });
  });
}
