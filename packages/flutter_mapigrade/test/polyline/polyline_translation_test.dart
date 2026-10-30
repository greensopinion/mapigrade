// Task 2.3 of the add-mapigrade-polyline-layer change.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_mapigrade/src/layer/overlay_host.dart';
import 'package:flutter_mapigrade/src/polyline/mapigrade_polyline.dart';
import 'package:flutter_mapigrade/src/polyline/polyline_translation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _ids = OverlayIds(7);
const _source = 'mapigrade-overlay-7-source-0';
const _gradientSource = 'mapigrade-overlay-7-source-1';

typedef _Json = Map<String, dynamic>;

List<_Json> _features(
  PolylineTranslation t, [
  PolylineSource source = PolylineSource.plain,
]) {
  final json = jsonDecode(utf8.decode(t.geoJson[source]!)) as _Json;
  expect(json['type'], 'FeatureCollection');
  return (json['features'] as List).cast<_Json>();
}

List<_Json> _layers(PolylineTranslation t) =>
    (jsonDecode(t.layersJson) as List).cast<_Json>();

MapigradePolyline _line({
  List<LatLng>? points,
  double strokeWidth = 1,
  Color color = const Color(0xFF00FF00),
  double borderStrokeWidth = 0,
  StrokeCap cap = StrokeCap.round,
  List<double>? dashes,
  List<Color>? gradientColors,
  List<double>? gradientStops,
  bool meters = false,
}) => MapigradePolyline(
  points: points ?? [const LatLng(0, 0), const LatLng(1, 1)],
  strokeWidth: strokeWidth,
  color: color,
  borderStrokeWidth: borderStrokeWidth,
  strokeCap: cap,
  dashes: dashes,
  gradientColors: gradientColors,
  gradientStops: gradientStops,
  useStrokeWidthInMeter: meters,
);

const _widthExpression = [
  'interpolate',
  ['exponential', 2],
  ['zoom'],
  0,
  ['get', 'w0'],
  24,
  ['get', 'w24'],
];

void main() {
  test('a single solid polyline', () {
    final t = translatePolylines([
      _line(
        points: [const LatLng(10, 20), const LatLng(11, 21)],
        strokeWidth: 6,
        color: const Color(0x80FF0000),
        borderStrokeWidth: 4,
      ),
    ], _ids);

    final f = _features(t).single;
    expect(f['geometry'], {
      'type': 'LineString',
      'coordinates': [
        [20, 10],
        [21, 11],
      ],
    });
    final p = f['properties'] as _Json;
    expect(p['i'], 0);
    expect(p['r'], 0);
    expect(p['c'], matches(RegExp(r'^rgba\(255,0,0,0\.50\d*\)$')));
    expect(p['bc'], 'rgba(255,255,0,1.0)');
    expect(p['w0'], 6);
    expect(p['w24'], 6);
    expect(p['b'], 2);
    expect(p['j'], 'round');

    final layers = _layers(t);
    expect(layers.map((l) => l['id']), [
      'mapigrade-overlay-7-0',
      'mapigrade-overlay-7-1',
    ]);
    final [border, line] = layers;
    for (final l in layers) {
      expect(l['type'], 'line');
      expect(l['source'], _source);
      expect(l['filter'], [
        '==',
        ['get', 'r'],
        0,
      ]);
      expect(l['layout']['line-sort-key'], ['get', 'i']);
      expect(l['layout']['line-cap'], 'round');
    }
    expect(border['paint'], {
      'line-gap-width': _widthExpression,
      'line-width': ['get', 'b'],
      'line-color': ['get', 'bc'],
    });
    expect(line['paint'], {
      'line-width': _widthExpression,
      'line-color': ['get', 'c'],
    });
    expect(line['layout']['line-join'], ['get', 'j']);
    expect(t.runs, [const PolylineRun(cap: StrokeCap.round)]);
  });

  group('runs', () {
    test('split by cap and dashes, and merged when equal', () {
      final t = translatePolylines([
        _line(),
        _line(),
        _line(cap: StrokeCap.butt),
        _line(cap: StrokeCap.butt, dashes: [2, 1]),
        _line(cap: StrokeCap.butt, dashes: [2, 1]),
        _line(),
      ], _ids);

      expect(t.runs, [
        const PolylineRun(cap: StrokeCap.round),
        const PolylineRun(cap: StrokeCap.butt),
        const PolylineRun(cap: StrokeCap.butt, dashes: [2, 1]),
        const PolylineRun(cap: StrokeCap.round),
      ]);
      expect(_features(t).map((f) => f['properties']['r']), [0, 0, 1, 2, 2, 3]);
      expect(_features(t).map((f) => f['properties']['i']), [0, 1, 2, 3, 4, 5]);
      final layers = _layers(t);
      expect(layers, hasLength(8));
      expect(layers.map((l) => l['id']), [
        for (var n = 0; n < 8; n++) 'mapigrade-overlay-7-$n',
      ]);
      expect(layers[5]['filter'], [
        '==',
        ['get', 'r'],
        2,
      ]);
      expect(layers[5]['paint']['line-dasharray'], [2, 1]);
      expect(layers[3]['paint'].containsKey('line-dasharray'), isFalse);
      expect(layers[4]['layout']['line-cap'], 'butt');
    });

    test('a gradient polyline is a run of its own', () {
      const colors = [Color(0xFFFF0000), Color(0xFF0000FF)];
      final t = translatePolylines([
        _line(),
        _line(gradientColors: colors),
        _line(gradientColors: colors),
        _line(),
      ], _ids);

      expect(_features(t).map((f) => f['properties']['r']), [0, 3]);
      expect(_features(t).map((f) => f['properties']['i']), [0, 3]);
      expect(
        _features(t, PolylineSource.gradient).map((f) => f['properties']['r']),
        [1, 2],
      );
      expect(
        _features(t, PolylineSource.gradient).map((f) => f['properties']['i']),
        [1, 2],
      );
      expect(t.runs, hasLength(4));
      expect(t.runs[1].gradient, isNotNull);
      expect(_layers(t).map((l) => l['source']), [
        _source,
        _source,
        _gradientSource,
        _gradientSource,
        _gradientSource,
        _gradientSource,
        _source,
        _source,
      ]);
      final line = _layers(t)[3];
      expect(line['paint'].containsKey('line-color'), isFalse);
      expect(line['paint']['line-gradient'], [
        'interpolate',
        ['linear'],
        ['line-progress'],
        0,
        'rgba(255,0,0,1.0)',
        1,
        'rgba(0,0,255,1.0)',
      ]);
    });

    test('gradient stops are used as given', () {
      final t = translatePolylines([
        _line(
          gradientColors: const [
            Color(0xFF000000),
            Color(0xFF808080),
            Color(0xFFFFFFFF),
          ],
          gradientStops: [0, 0.25, 1],
        ),
      ], _ids);
      final paint = _layers(t)[1]['paint'] as _Json;
      expect((paint['line-gradient'] as List).whereType<num>(), [0, 0.25, 1]);
      expect(paint.containsKey('line-dasharray'), isFalse);
      expect(t.runs.single.dashes, isNull);
    });

    test('equal structure compares equal for different data', () {
      final a = translatePolylines([
        _line(),
        _line(dashes: [1, 2]),
      ], _ids);
      final b = translatePolylines([
        _line(points: [const LatLng(5, 5), const LatLng(6, 6)], strokeWidth: 9),
        _line(dashes: [1, 2]),
      ], _ids);
      expect(a.runs, b.runs);
      expect(a.layersJson, b.layersJson);
      expect(
        a.geoJson[PolylineSource.plain],
        isNot(b.geoJson[PolylineSource.plain]),
      );
    });
  });

  test('the gradient source exists only with a gradient polyline', () {
    final plain = translatePolylines([
      _line(),
      _line(dashes: [2, 1]),
    ], _ids);
    expect(plain.geoJson.keys, [PolylineSource.plain]);
    expect(PolylineSource.plain.lineMetrics, isFalse);
    expect(PolylineSource.gradient.lineMetrics, isTrue);
    expect(PolylineSource.plain.index, 0);
    expect(PolylineSource.gradient.index, 1);

    final gradient = translatePolylines([
      _line(gradientColors: const [Color(0xFF000000), Color(0xFFFFFFFF)]),
    ], _ids);
    expect(gradient.geoJson.keys, [
      PolylineSource.plain,
      PolylineSource.gradient,
    ]);
    expect(_features(gradient), isEmpty);
    expect(_features(gradient, PolylineSource.gradient), hasLength(1));
  });

  test('polylines with fewer than two points get no feature', () {
    final t = translatePolylines([
      _line(points: []),
      _line(points: [const LatLng(1, 1)]),
      _line(),
      _line(points: [const LatLng(2, 2)]),
      _line(),
    ], _ids);
    final features = _features(t);
    expect(features.map((f) => f['properties']['i']), [2, 4]);
    expect(features.map((f) => f['properties']['r']), [0, 0]);
    expect(t.runs, hasLength(1));

    final none = translatePolylines([_line(points: [])], _ids);
    expect(_features(none), isEmpty);
    expect(_layers(none), isEmpty);
    expect(none.runs, isEmpty);
  });

  test('width in meters at latitude 45', () {
    final t = translatePolylines([
      _line(
        points: [const LatLng(45, 10), const LatLng(46, 10)],
        strokeWidth: 100,
        meters: true,
      ),
    ], _ids);
    final p = _features(t).single['properties'] as _Json;
    final w0 = 100 * 512 / (40075016.686 * math.cos(45 * math.pi / 180));
    expect(p['w0'], closeTo(w0, 1e-12));
    expect(p['w0'], closeTo(0.00180, 1e-5));
    expect(p['w24'], closeTo(w0 * 16777216, 1e-6));
    expect(p['w24'] / p['w0'], closeTo(16777216, 1e-3));
  });

  group('longitude', () {
    test('179 to -179 crosses the antimeridian', () {
      final t = translatePolylines([
        _line(points: [const LatLng(0, 179), const LatLng(0, -179)]),
      ], _ids);
      expect(_features(t).single['geometry']['coordinates'], [
        [179, 0],
        [181, 0],
      ]);
    });

    test('is unwrapped across several steps in both directions', () {
      final t = translatePolylines([
        _line(
          points: [
            const LatLng(0, 170),
            const LatLng(0, -170),
            const LatLng(0, -10),
            const LatLng(0, 150),
            const LatLng(0, 170),
          ],
        ),
        _line(points: [const LatLng(0, -179), const LatLng(0, 179)]),
      ], _ids);
      final features = _features(t);
      expect(features[0]['geometry']['coordinates'].map((dynamic c) => c[0]), [
        170,
        190,
        350,
        510,
        530,
      ]);
      expect(features[1]['geometry']['coordinates'].map((dynamic c) => c[0]), [
        -179,
        -181,
      ]);
    });

    test('a step of exactly 180 degrees is kept', () {
      final t = translatePolylines([
        _line(points: [const LatLng(0, 0), const LatLng(0, 180)]),
      ], _ids);
      expect(_features(t).single['geometry']['coordinates'].last[0], 180);
    });
  });

  test(
    'no code outside the polyline directory refers to lines outside comments',
    () {
      final lib = Directory('lib/src');
      final pattern = RegExp(r'''["']line-|LineString''');
      final offenders = <String>[
        for (final f in lib.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !f.path.contains(
                '${Platform.pathSeparator}polyline${Platform.pathSeparator}',
              ) &&
              f.readAsLinesSync().any(
                (l) => !l.trimLeft().startsWith('//') && pattern.hasMatch(l),
              ))
            f.path,
      ];
      expect(offenders, isEmpty, reason: 'refer to lines: $offenders');
    },
  );
}
