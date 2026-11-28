// Task 2.2 of the add-mapigrade-polyline-layer change.
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/src/polyline/mapigrade_polyline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final _points = [const LatLng(0, 0), const LatLng(1, 1)];

Matcher _assertionNaming(String name) => throwsA(
  isA<AssertionError>().having(
    (e) => '${e.message}',
    'message',
    contains(name),
  ),
);

void main() {
  group('defaults', () {
    test('equal those of flutter_map Polyline', () {
      final p = MapigradePolyline(points: _points);
      final f = Polyline(points: _points);
      expect(p.strokeWidth, f.strokeWidth);
      expect(p.color, f.color);
      expect(p.useStrokeWidthInMeter, f.useStrokeWidthInMeter);
      expect(p.borderStrokeWidth, f.borderStrokeWidth);
      expect(p.borderColor, f.borderColor);
      expect(p.strokeCap, f.strokeCap);
      expect(p.strokeJoin, f.strokeJoin);
      expect(p.dashes, isNull);
      expect(p.gradientColors, isNull);
      expect(p.gradientStops, isNull);
    });
  });

  group('equality', () {
    test('equal properties and equal points are equal with one hash code', () {
      final a = MapigradePolyline(points: [..._points], dashes: [1, 2]);
      final b = MapigradePolyline(points: [..._points], dashes: [1, 2]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('identical points list is equal', () {
      expect(
        MapigradePolyline(points: _points),
        MapigradePolyline(points: _points),
      );
    });

    test('each property is compared', () {
      final base = MapigradePolyline(points: _points);
      final others = [
        MapigradePolyline(points: [const LatLng(0, 0), const LatLng(1, 2)]),
        MapigradePolyline(points: _points, strokeWidth: 2),
        MapigradePolyline(points: _points, color: const Color(0xFF000000)),
        MapigradePolyline(points: _points, borderStrokeWidth: 1),
        MapigradePolyline(
          points: _points,
          borderColor: const Color(0xFF000000),
        ),
        MapigradePolyline(points: _points, strokeCap: StrokeCap.butt),
        MapigradePolyline(points: _points, strokeJoin: StrokeJoin.bevel),
        MapigradePolyline(points: _points, useStrokeWidthInMeter: true),
        MapigradePolyline(points: _points, dashes: [1, 1]),
        MapigradePolyline(
          points: _points,
          gradientColors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
        ),
        MapigradePolyline(
          points: _points,
          gradientColors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
          gradientStops: [0, 0.5],
        ),
      ];
      for (final o in others) {
        expect(base, isNot(o));
      }
    });
  });

  group('assertions', () {
    test('negative widths', () {
      expect(
        () => MapigradePolyline(points: _points, strokeWidth: -1),
        _assertionNaming('strokeWidth'),
      );
      expect(
        () => MapigradePolyline(points: _points, borderStrokeWidth: -1),
        _assertionNaming('borderStrokeWidth'),
      );
    });

    test('invalid dashes', () {
      for (final dashes in <List<double>>[
        [1, 2, 3],
        [1, -1],
        [0, 0],
        [],
      ]) {
        expect(
          () => MapigradePolyline(points: _points, dashes: dashes),
          _assertionNaming('dashes'),
          reason: '$dashes',
        );
      }
      expect(MapigradePolyline(points: _points, dashes: [0, 1.5]).dashes, [
        0,
        1.5,
      ]);
    });

    test('gradient colors with dashes', () {
      expect(
        () => MapigradePolyline(
          points: _points,
          gradientColors: const [Color(0xFF000000), Color(0xFFFFFFFF)],
          dashes: [1, 1],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('gradientColors'), contains('dashes')),
          ),
        ),
      );
    });

    test('invalid gradient stops', () {
      const colors = [Color(0xFF000000), Color(0xFF111111), Color(0xFFFFFFFF)];
      expect(
        () => MapigradePolyline(points: _points, gradientStops: [0, 1]),
        _assertionNaming('gradientStops'),
      );
      for (final stops in <List<double>>[
        [0, 1],
        [0, 0.8, 0.5],
        [-0.1, 0.5, 1],
        [0, 0.5, 1.1],
      ]) {
        expect(
          () => MapigradePolyline(
            points: _points,
            gradientColors: colors,
            gradientStops: stops,
          ),
          _assertionNaming('gradientStops'),
          reason: '$stops',
        );
      }
      MapigradePolyline(
        points: _points,
        gradientColors: colors,
        gradientStops: [0, 0.5, 1],
      );
    });
  });
}
