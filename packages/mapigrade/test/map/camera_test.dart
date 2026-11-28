import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/src/map/camera.dart';

void main() {
  group('MapigradeCamera', () {
    test('cameras with equal fields are equal', () {
      const a = MapigradeCamera(
        center: LatLng(48.2, 16.37),
        centerAltitude: 200,
        zoom: 12,
        bearing: 30,
        pitch: 45,
        roll: 5,
        fieldOfView: 40,
        padding: EdgeInsets.only(top: 10),
      );
      const b = MapigradeCamera(
        center: LatLng(48.2, 16.37),
        centerAltitude: 200,
        zoom: 12,
        bearing: 30,
        pitch: 45,
        roll: 5,
        fieldOfView: 40,
        padding: EdgeInsets.only(top: 10),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const MapigradeCamera(zoom: 12)));
    });

    test('each field takes part in equality', () {
      const base = MapigradeCamera(
        center: LatLng(0, 0),
        centerAltitude: 0,
        zoom: 1,
        bearing: 0,
        pitch: 0,
        roll: 0,
        fieldOfView: 36.87,
        padding: EdgeInsets.zero,
      );
      final variants = [
        base.merge(const MapigradeCamera(center: LatLng(1, 0))),
        base.merge(const MapigradeCamera(centerAltitude: 1)),
        base.merge(const MapigradeCamera(zoom: 2)),
        base.merge(const MapigradeCamera(bearing: 1)),
        base.merge(const MapigradeCamera(pitch: 1)),
        base.merge(const MapigradeCamera(roll: 1)),
        base.merge(const MapigradeCamera(fieldOfView: 50)),
        base.merge(const MapigradeCamera(padding: EdgeInsets.all(1))),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base));
      }
    });

    test('a command camera may set only the padding', () {
      const camera = MapigradeCamera(padding: EdgeInsets.only(bottom: 80));
      expect(camera.center, isNull);
      expect(camera.zoom, isNull);
      expect(camera.bearing, isNull);
      expect(camera.pitch, isNull);
      expect(camera.padding, const EdgeInsets.only(bottom: 80));
      const current = MapigradeCamera(
        center: LatLng(1, 2),
        zoom: 3,
        bearing: 4,
        pitch: 5,
      );
      expect(
        current.merge(camera),
        const MapigradeCamera(
          center: LatLng(1, 2),
          zoom: 3,
          bearing: 4,
          pitch: 5,
          padding: EdgeInsets.only(bottom: 80),
        ),
      );
    });
  });

  group('GeoBounds', () {
    test('fromPoints contains every point', () {
      final bounds = GeoBounds.fromPoints(const [
        LatLng(1, 5),
        LatLng(-2, 3),
        LatLng(4, -1),
      ]);
      expect(bounds, GeoBounds(const LatLng(-2, -1), const LatLng(4, 5)));
    });

    test('a south-west corner north of the north-east corner is refused', () {
      expect(
        () => GeoBounds(const LatLng(5, 0), const LatLng(4, 1)),
        throwsArgumentError,
      );
      expect(() => GeoBounds.fromPoints(const []), throwsArgumentError);
    });
  });

  group('CameraLimits', () {
    test('defaults', () {
      final limits = CameraLimits();
      expect(limits.minZoom, 0);
      expect(limits.maxZoom, 22);
      expect(limits.minPitch, 0);
      expect(limits.maxPitch, 60);
      expect(limits.bounds, isNull);
      expect(limits, CameraLimits());
    });

    test('invalid limits are refused', () {
      expect(() => CameraLimits(minZoom: 5, maxZoom: 4), throwsArgumentError);
      expect(
        () => CameraLimits(minPitch: 50, maxPitch: 40),
        throwsArgumentError,
      );
      expect(() => CameraLimits(minPitch: -1), throwsArgumentError);
      expect(() => CameraLimits(maxPitch: 90), throwsArgumentError);
      expect(() => CameraLimits(maxZoom: double.nan), throwsArgumentError);
    });
  });

  test('CameraChange equality', () {
    const camera = MapigradeCamera(zoom: 3);
    expect(
      const CameraChange(camera, CameraChangeSource.gesture),
      const CameraChange(camera, CameraChangeSource.gesture),
    );
    expect(
      const CameraChange(camera, CameraChangeSource.gesture),
      isNot(const CameraChange(camera, CameraChangeSource.command)),
    );
  });
}
