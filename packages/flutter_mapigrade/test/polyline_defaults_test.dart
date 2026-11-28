// The flutter_mapigrade README states that MapigradePolyline keeps the
// defaults of flutter_map's Polyline.
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final _points = [const LatLng(0, 0), const LatLng(1, 1)];

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
}
