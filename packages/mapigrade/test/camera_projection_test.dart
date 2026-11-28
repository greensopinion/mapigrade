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
    for (final (lat, lon, zoom, bearing) in const [
      (51.5, -0.12, 13.0, 0.0),
      (48.85, 2.35, 10.5, 30.0),
      (-33.9, 179.9, 8.0, -30.0),
      (-33.9, -180.0, 8.0, 30.0),
      (12.0, 179.999, 4.25, 0.0),
    ]) {
      test('lat $lat lon $lon zoom $zoom bearing $bearing', () {
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
        );
        final built = flutterMapCameraOf(camera, live);
        expect(viewCameraOf(built), ViewCamera(camera, viewport));
        expect(built.crs, live.crs);
        expect(built.minZoom, 2);
        expect(built.maxZoom, 18);
      });
    }
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
          expect(
            screenPosition(converted, mercator(ll.latitude, ll.longitude)),
            near(camera.latLngToScreenOffset(ll), 1e-3),
          );
        }
      });
    }
  });
}
