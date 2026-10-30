import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../layer/overlay_host.dart';
import 'mapigrade_polyline.dart';

/// The GeoJSON sources of a polyline layer's overlay. Polylines with a
/// gradient go in a source with line metrics, which `line-gradient` needs,
/// and the others in a source without, because MapLibre measures a dash
/// pattern in the same per-vertex distance that it rescales to a fraction of
/// the line in a source with line metrics (design D197). The source index is
/// [index].
enum PolylineSource {
  /// Polylines without a gradient.
  plain(lineMetrics: false),

  /// Polylines with a gradient.
  gradient(lineMetrics: true);

  const PolylineSource({required this.lineMetrics});

  /// Whether the source has line metrics.
  final bool lineMetrics;
}

/// How a run of polylines is drawn by one pair of style layers. MapLibre can't
/// vary these per feature, so they are style layer properties.
@immutable
final class PolylineRun {
  /// A run of [cap], [dashes] and [gradient].
  const PolylineRun({required this.cap, this.dashes, this.gradient});

  /// The caps of the run's lines.
  final StrokeCap cap;

  /// Null for a solid line and for a gradient.
  final List<double>? dashes;

  /// Null unless the run is one polyline with a gradient.
  final PolylineGradient? gradient;

  @override
  bool operator ==(Object other) =>
      other is PolylineRun &&
      other.cap == cap &&
      other.gradient == gradient &&
      listEquals(other.dashes, dashes);

  @override
  int get hashCode => Object.hash(cap, gradient, Object.hashAll(dashes ?? []));
}

/// The colors of a gradient with a stop for each color.
@immutable
final class PolylineGradient {
  /// A gradient of [colors] at [stops].
  const PolylineGradient({required this.colors, required this.stops});

  /// The colors, from the start of the line.
  final List<Color> colors;

  /// The position of each color along the line, strictly increasing.
  final List<double> stops;

  @override
  bool operator ==(Object other) =>
      other is PolylineGradient &&
      listEquals(other.colors, colors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(colors), Object.hashAll(stops));
}

/// A feature of a source: a polyline with its index in the list, the
/// `line-sort-key`, and the index of its run, the layer filter.
typedef PolylineFeature = ({int index, int run, MapigradePolyline polyline});

/// The GeoJSON and style layers that draw a list of polylines.
final class PolylineTranslation {
  /// A translation of [geoJson] with the style layers of [runs].
  const PolylineTranslation({
    required this.geoJson,
    required this.runs,
    required this.layersJson,
  });

  /// A UTF-8 GeoJSON `FeatureCollection` for each source that the layers
  /// name: [PolylineSource.plain] always, [PolylineSource.gradient] when a
  /// run has a gradient.
  final Map<PolylineSource, Uint8List> geoJson;

  /// The runs, in draw order. Style layers depend only on this list and the
  /// overlay's IDs, so equal runs mean that only [geoJson] needs sending.
  final List<PolylineRun> runs;

  /// A JSON array of style layer objects, two for each run: the border at
  /// index `2 * k` and the line at `2 * k + 1`.
  final String layersJson;
}

/// The runs of [polylines], in draw order. A polyline with fewer than two
/// points gets no run and doesn't break one.
List<PolylineRun> polylineRuns(List<MapigradePolyline> polylines) =>
    _assignRuns(polylines).runs;

/// The sources that the style layers of [runs] name.
Set<PolylineSource> polylineSources(List<PolylineRun> runs) => {
  PolylineSource.plain,
  if (runs.any((r) => r.gradient != null)) PolylineSource.gradient,
};

/// The style layers that draw [runs] from the sources of the overlay [ids],
/// as a JSON array.
String polylineLayersJson(OverlayIds ids, List<PolylineRun> runs) =>
    jsonEncode([
      for (var k = 0; k < runs.length; k++) ...[
        _borderLayer(ids, k, runs[k]),
        _lineLayer(ids, k, runs[k]),
      ],
    ]);

/// The features of [source]: the polylines of [polylines] that belong in it
/// and have a run, with their index in [polylines] and the index of their run
/// in [polylineRuns]. Equal lists encode to the same GeoJSON.
List<PolylineFeature> polylineFeatures(
  List<MapigradePolyline> polylines,
  PolylineSource source,
) {
  final runIndexes = _assignRuns(polylines).runIndexes;
  return [
    for (var i = 0; i < polylines.length; i++)
      if (runIndexes[i] >= 0 && _sourceOf(polylines[i]) == source)
        (index: i, run: runIndexes[i], polyline: polylines[i]),
  ];
}

/// The UTF-8 GeoJSON `FeatureCollection` of [features]. The feature property
/// `i` is the polyline's index and `r` its run index.
Uint8List polylineGeoJson(List<PolylineFeature> features) {
  final buffer = StringBuffer('{"type":"FeatureCollection","features":[');
  for (var n = 0; n < features.length; n++) {
    if (n > 0) buffer.write(',');
    final f = features[n];
    _writeFeature(buffer, f.polyline, f.index, f.run);
  }
  buffer.write(']}');
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

/// Translates [polylines] to GeoJSON features and the style layers that draw
/// them from the sources of the overlay [ids].
PolylineTranslation translatePolylines(
  List<MapigradePolyline> polylines,
  OverlayIds ids,
) {
  final runs = polylineRuns(polylines);
  return PolylineTranslation(
    geoJson: {
      for (final source in polylineSources(runs))
        source: polylineGeoJson(polylineFeatures(polylines, source)),
    },
    runs: List.unmodifiable(runs),
    layersJson: polylineLayersJson(ids, runs),
  );
}

({List<PolylineRun> runs, List<int> runIndexes}) _assignRuns(
  List<MapigradePolyline> polylines,
) {
  final runs = <PolylineRun>[];
  final runIndexes = List.filled(polylines.length, -1);
  for (var i = 0; i < polylines.length; i++) {
    final polyline = polylines[i];
    if (polyline.points.length < 2) continue;
    final run = _runOf(polyline);
    if (runs.isEmpty || run.gradient != null || runs.last != run) {
      runs.add(run);
    }
    runIndexes[i] = runs.length - 1;
  }
  return (runs: runs, runIndexes: runIndexes);
}

const _earthCircumference = 40075016.686;
const _tileSize = 512;

PolylineSource _sourceOf(MapigradePolyline p) => p.gradientColors == null
    ? PolylineSource.plain
    : PolylineSource.gradient;

PolylineSource _sourceOfRun(PolylineRun run) =>
    run.gradient == null ? PolylineSource.plain : PolylineSource.gradient;

PolylineRun _runOf(MapigradePolyline p) {
  final colors = p.gradientColors;
  if (colors == null) {
    return PolylineRun(cap: p.strokeCap, dashes: p.dashes);
  }
  return PolylineRun(
    cap: p.strokeCap,
    gradient: PolylineGradient(colors: colors, stops: _resolveStops(p)),
  );
}

List<double> _resolveStops(MapigradePolyline p) {
  final colors = p.gradientColors!;
  final given = p.gradientStops;
  final stops = [
    for (var i = 0; i < colors.length; i++)
      given?[i] ?? (colors.length == 1 ? 0.0 : i / (colors.length - 1)),
  ];
  // MapLibre's interpolate needs strictly increasing stops.
  for (var i = 1; i < stops.length; i++) {
    if (stops[i] <= stops[i - 1]) stops[i] = stops[i - 1] + 1e-9;
  }
  return stops;
}

void _writeFeature(StringBuffer out, MapigradePolyline p, int index, int run) {
  final w0 = p.useStrokeWidthInMeter
      ? p.strokeWidth *
            _tileSize /
            (_earthCircumference *
                math.max(
                  math.cos(p.points.first.latitude * math.pi / 180),
                  1e-6,
                ))
      : p.strokeWidth;
  final w24 = p.useStrokeWidthInMeter ? w0 * (1 << 24) : w0;
  out.write('{"type":"Feature","properties":{"i":$index,"r":$run,');
  out.write('"c":"${_rgba(p.color)}","bc":"${_rgba(p.borderColor)}",');
  out.write('"w0":$w0,"w24":$w24,"b":${p.borderStrokeWidth / 2},');
  out.write('"j":"${_join(p.strokeJoin)}"},');
  out.write('"geometry":{"type":"LineString","coordinates":[');
  var lon = p.points.first.longitude;
  for (var n = 0; n < p.points.length; n++) {
    final point = p.points[n];
    if (n > 0) {
      out.write(',');
      var next = point.longitude;
      while (next - lon > 180) {
        next -= 360;
      }
      while (next - lon < -180) {
        next += 360;
      }
      lon = next;
    }
    out.write('[$lon,${point.latitude}]');
  }
  out.write(']}}');
}

String _rgba(Color c) =>
    'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a})';

String _join(StrokeJoin join) => switch (join) {
  StrokeJoin.miter => 'miter',
  StrokeJoin.round => 'round',
  StrokeJoin.bevel => 'bevel',
};

String _cap(StrokeCap cap) => switch (cap) {
  StrokeCap.butt => 'butt',
  StrokeCap.round => 'round',
  StrokeCap.square => 'square',
};

const _widthExpression = [
  'interpolate',
  ['exponential', 2],
  ['zoom'],
  0,
  ['get', 'w0'],
  24,
  ['get', 'w24'],
];

Map<String, Object?> _borderLayer(OverlayIds ids, int run, PolylineRun r) => {
  'id': ids.layerId(2 * run),
  'type': 'line',
  'source': ids.sourceId(_sourceOfRun(r).index),
  'filter': _runFilter(run),
  'layout': {
    'line-sort-key': ['get', 'i'],
    'line-cap': _cap(r.cap),
    'line-join': ['get', 'j'],
  },
  'paint': {
    'line-gap-width': _widthExpression,
    'line-width': ['get', 'b'],
    'line-color': ['get', 'bc'],
  },
};

Map<String, Object?> _lineLayer(OverlayIds ids, int run, PolylineRun r) {
  final gradient = r.gradient;
  final dashes = r.dashes;
  return {
    'id': ids.layerId(2 * run + 1),
    'type': 'line',
    'source': ids.sourceId(_sourceOfRun(r).index),
    'filter': _runFilter(run),
    'layout': {
      'line-sort-key': ['get', 'i'],
      'line-cap': _cap(r.cap),
      'line-join': ['get', 'j'],
    },
    'paint': {
      'line-width': _widthExpression,
      if (gradient == null) 'line-color': ['get', 'c'],
      if (gradient != null)
        'line-gradient': [
          'interpolate',
          ['linear'],
          ['line-progress'],
          for (var i = 0; i < gradient.colors.length; i++) ...[
            gradient.stops[i],
            _rgba(gradient.colors[i]),
          ],
        ],
      'line-dasharray': ?dashes,
    },
  };
}

List<Object> _runFilter(int run) => [
  '==',
  ['get', 'r'],
  run,
];
