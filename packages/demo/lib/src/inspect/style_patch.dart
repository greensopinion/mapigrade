import 'dart:convert';
import 'dart:io';

/// The color of the highlight; it differs from the flyover's magenta route
/// and from the main colors of the demo's styles.
const highlightColor = '#00b8d4';

const _selected = [
  'boolean',
  ['feature-state', 'selected'],
  false,
];

const _polygons = ['Polygon', 'MultiPolygon'];
const _lines = ['LineString', 'MultiLineString'];
const _points = ['Point', 'MultiPoint'];

/// Layer types that draw the features of a source layer.
const _featureLayerTypes = {
  'fill',
  'line',
  'circle',
  'symbol',
  'fill-extrusion',
  'heatmap',
};

const _featureSourceTypes = {'vector', 'geojson'};

/// A style with highlight layers, and the IDs of its own layers that draw
/// features, topmost first (design D193).
class HighlightStyle {
  HighlightStyle(this.json, this.layerIds, this.symbolLayerIds);

  /// The style as JSON for `MapigradeLayer.styleJson`.
  final String json;
  final List<String> layerIds;

  /// The layers of [layerIds] that are symbol layers, whose features MapLibre
  /// Native returns without feature state.
  final Set<String> symbolLayerIds;
}

/// Fetches the style at [url] and adds highlight layers to it. Throws a
/// [StyleFetchException] when the response isn't a style.
Future<HighlightStyle> fetchHighlightStyle(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StyleFetchException('$url: HTTP ${response.statusCode}');
    }
    final Object? style;
    try {
      style = jsonDecode(body);
    } on FormatException catch (e) {
      throw StyleFetchException('$url isn\'t JSON: ${e.message}');
    }
    if (style is! Map<String, Object?> ||
        style['sources'] is! Map ||
        style['layers'] is! List) {
      throw StyleFetchException('$url isn\'t a MapLibre style');
    }
    return HighlightStyle(
      jsonEncode(addHighlightLayers(style, url)),
      featureLayerIds(style),
      symbolLayerIds(style),
    );
  } finally {
    client.close();
  }
}

class StyleFetchException implements Exception {
  StyleFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [style] with highlight layers above its own layers, and its relative URLs
/// resolved against [styleUrl], because a style given as JSON has no base URL
/// (design D192).
///
/// For each pair of source and source layer that the style's layers draw
/// from, four layers draw a feature whose feature state has `selected: true`:
/// a fill and an outline for polygons, a wide line for lines, and a circle
/// for points. Filters can't read feature state, so opacity carries it.
Map<String, Object?> addHighlightLayers(
  Map<String, Object?> style,
  Uri styleUrl,
) {
  final sources = {
    for (final MapEntry(:key, :value)
        in (style['sources']! as Map<String, Object?>).entries)
      key: _resolveSource(value! as Map<String, Object?>, styleUrl),
  };
  final layers = (style['layers']! as List).cast<Map<String, Object?>>();
  final pairs = {
    for (final layer in _featureLayers(style))
      (layer['source']! as String, layer['source-layer'] as String?),
  };
  final sprite = style['sprite'];
  final glyphs = style['glyphs'];
  return {
    ...style,
    'sources': sources,
    if (sprite is String) 'sprite': _resolve(sprite, styleUrl),
    if (sprite is List)
      'sprite': [
        for (final entry in sprite.cast<Map<String, Object?>>())
          {...entry, 'url': _resolve(entry['url']! as String, styleUrl)},
      ],
    if (glyphs is String) 'glyphs': _resolve(glyphs, styleUrl),
    'layers': [
      ...layers,
      for (final (i, (source, sourceLayer)) in pairs.indexed)
        ..._highlightLayers('mapigrade-highlight-$i', source, sourceLayer),
    ],
  };
}

/// The IDs of the layers of [style] that draw features of a source, topmost
/// first.
List<String> featureLayerIds(Map<String, Object?> style) => [
  for (final layer in _featureLayers(style).toList().reversed)
    layer['id']! as String,
];

/// The IDs of the symbol layers among [featureLayerIds].
Set<String> symbolLayerIds(Map<String, Object?> style) => {
  for (final layer in _featureLayers(style))
    if (layer['type'] == 'symbol') layer['id']! as String,
};

Iterable<Map<String, Object?>> _featureLayers(
  Map<String, Object?> style,
) sync* {
  final sources = style['sources']! as Map<String, Object?>;
  for (final layer in (style['layers']! as List).cast<Map<String, Object?>>()) {
    final source = layer['source'];
    if (source is! String || !_featureLayerTypes.contains(layer['type'])) {
      continue;
    }
    if (!_featureSourceTypes.contains((sources[source] as Map?)?['type'])) {
      continue;
    }
    yield layer;
  }
}

Map<String, Object?> _resolveSource(Map<String, Object?> source, Uri base) {
  final url = source['url'];
  final tiles = source['tiles'];
  final data = source['data'];
  return {
    ...source,
    if (url is String) 'url': _resolve(url, base),
    if (tiles is List)
      'tiles': [for (final t in tiles.cast<String>()) _resolve(t, base)],
    if (data is String) 'data': _resolve(data, base),
  };
}

/// [url] resolved against [base] when it is relative. The braces of URL
/// templates such as `{z}` and `{fontstack}` stay as they are.
String _resolve(String url, Uri base) {
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(url)) return url;
  return base
      .resolve(url)
      .toString()
      .replaceAll('%7B', '{')
      .replaceAll('%7D', '}');
}

List<Object> _geometryIn(List<String> types) => [
  'match',
  ['geometry-type'],
  types,
  true,
  false,
];

List<Object> _whenSelected(num opacity) => ['case', _selected, opacity, 0];

List<Map<String, Object?>> _highlightLayers(
  String id,
  String source,
  String? sourceLayer,
) {
  Map<String, Object?> layer(
    String suffix,
    String type,
    List<String> geometry,
    Map<String, Object?> paint, [
    Map<String, Object?>? layout,
  ]) => {
    'id': '$id-$suffix',
    'type': type,
    'source': source,
    'source-layer': ?sourceLayer,
    'filter': _geometryIn(geometry),
    'layout': ?layout,
    'paint': paint,
  };
  const roundLine = {'line-cap': 'round', 'line-join': 'round'};
  return [
    layer('fill', 'fill', _polygons, {
      'fill-color': highlightColor,
      'fill-opacity': _whenSelected(0.35),
    }),
    layer('outline', 'line', _polygons, {
      'line-color': highlightColor,
      'line-width': 3,
      'line-opacity': _whenSelected(1),
    }, roundLine),
    layer('line', 'line', _lines, {
      'line-color': highlightColor,
      'line-width': [
        'interpolate',
        ['exponential', 1.2],
        ['zoom'],
        10,
        6,
        20,
        30,
      ],
      'line-opacity': _whenSelected(0.7),
    }, roundLine),
    layer('circle', 'circle', _points, {
      'circle-color': highlightColor,
      'circle-radius': 10,
      'circle-opacity': _whenSelected(0.9),
      'circle-stroke-color': '#ffffff',
      'circle-stroke-width': 2,
      'circle-stroke-opacity': _whenSelected(1),
    }),
  ];
}
