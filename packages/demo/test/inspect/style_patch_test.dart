import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade_demo/src/common/styles.dart';
import 'package:mapigrade_demo/src/inspect/style_patch.dart';

final _styleUrl = Uri.parse('https://example.com/styles/test/style.json');

Map<String, Object?> _fixture() => {
  'version': 8,
  'sprite': 'sprites/test',
  'glyphs': '../fonts/{fontstack}/{range}.pbf',
  'sources': {
    'tiles': {'type': 'vector', 'url': 'tiles.json'},
    'direct': {
      'type': 'vector',
      'tiles': ['/tiles/{z}/{x}/{y}.pbf', 'https://cdn.example.com/{z}.pbf'],
    },
    'points': {'type': 'geojson', 'data': 'points.geojson'},
    'relief': {'type': 'raster', 'url': 'https://example.com/relief.json'},
  },
  'layers': [
    {'id': 'background', 'type': 'background'},
    {'id': 'relief', 'type': 'raster', 'source': 'relief'},
    {'id': 'water', 'type': 'fill', 'source': 'tiles', 'source-layer': 'water'},
    {
      'id': 'roads',
      'type': 'line',
      'source': 'tiles',
      'source-layer': 'transportation',
    },
    {
      'id': 'road-names',
      'type': 'symbol',
      'source': 'tiles',
      'source-layer': 'transportation',
    },
    {
      'id': 'lakes',
      'type': 'fill',
      'source': 'direct',
      'source-layer': 'water',
    },
    {'id': 'cafes', 'type': 'circle', 'source': 'points'},
  ],
};

List<Map<String, Object?>> _layers(Map<String, Object?> style) =>
    (style['layers']! as List).cast<Map<String, Object?>>();

List<Map<String, Object?>> _highlights(Map<String, Object?> style) => [
  for (final layer in _layers(style))
    if ((layer['id']! as String).startsWith('mapigrade-highlight-')) layer,
];

void main() {
  test('adds four highlight layers per pair of source and source layer', () {
    final style = addHighlightLayers(_fixture(), _styleUrl);
    final pairs = {
      for (final layer in _highlights(style))
        (layer['source'], layer['source-layer']),
    };
    expect(pairs, {
      ('tiles', 'water'),
      ('tiles', 'transportation'),
      ('direct', 'water'),
      ('points', null),
    });
    expect(_highlights(style), hasLength(16));
    for (final (source, sourceLayer) in pairs) {
      final types = [
        for (final layer in _highlights(style))
          if (layer['source'] == source && layer['source-layer'] == sourceLayer)
            layer['type'],
      ];
      expect(types, ['fill', 'line', 'line', 'circle']);
    }
  });

  test('a GeoJSON source has no source layer', () {
    final style = addHighlightLayers(_fixture(), _styleUrl);
    for (final layer in _highlights(style)) {
      if (layer['source'] == 'points') {
        expect(layer.containsKey('source-layer'), isFalse);
      }
    }
  });

  test('appends the highlight layers and keeps the style\'s own', () {
    final fixture = _fixture();
    final style = addHighlightLayers(fixture, _styleUrl);
    final own = _layers(fixture);
    expect(_layers(style).take(own.length), own);
    expect(_layers(style).skip(own.length), _highlights(style));
    expect(_highlights(style).any((l) => l['source'] == 'relief'), isFalse);
  });

  test('filters by geometry type', () {
    final style = addHighlightLayers(_fixture(), _styleUrl);
    final byId = {for (final l in _highlights(style)) l['id']: l['filter']};
    List<Object> match(List<String> types) => [
      'match',
      ['geometry-type'],
      types,
      true,
      false,
    ];
    expect(
      byId['mapigrade-highlight-0-fill'],
      match(['Polygon', 'MultiPolygon']),
    );
    expect(
      byId['mapigrade-highlight-0-outline'],
      match(['Polygon', 'MultiPolygon']),
    );
    expect(
      byId['mapigrade-highlight-0-line'],
      match(['LineString', 'MultiLineString']),
    );
    expect(
      byId['mapigrade-highlight-0-circle'],
      match(['Point', 'MultiPoint']),
    );
  });

  test('reads opacity from the selected feature state', () {
    final style = addHighlightLayers(_fixture(), _styleUrl);
    const selected = [
      'boolean',
      ['feature-state', 'selected'],
      false,
    ];
    for (final layer in _highlights(style)) {
      final paint = layer['paint']! as Map<String, Object?>;
      final opacities = [
        for (final MapEntry(:key, :value) in paint.entries)
          if (key.endsWith('opacity')) value,
      ];
      expect(opacities, isNotEmpty);
      for (final opacity in opacities) {
        expect(opacity, isA<List<Object?>>());
        expect((opacity! as List)[0], 'case');
        expect((opacity as List)[1], selected);
        expect(opacity.last, 0);
      }
    }
  });

  test('resolves relative URLs against the style URL', () {
    final style = addHighlightLayers(_fixture(), _styleUrl);
    final sources = style['sources']! as Map<String, Object?>;
    expect(style['sprite'], 'https://example.com/styles/test/sprites/test');
    expect(
      style['glyphs'],
      'https://example.com/styles/fonts/{fontstack}/{range}.pbf',
    );
    expect(
      (sources['tiles']! as Map)['url'],
      'https://example.com/styles/test/tiles.json',
    );
    expect((sources['direct']! as Map)['tiles'], [
      'https://example.com/tiles/{z}/{x}/{y}.pbf',
      'https://cdn.example.com/{z}.pbf',
    ]);
    expect(
      (sources['points']! as Map)['data'],
      'https://example.com/styles/test/points.geojson',
    );
    expect(
      (sources['relief']! as Map)['url'],
      'https://example.com/relief.json',
    );
  });

  test('resolves the URLs of a sprite list', () {
    final style = addHighlightLayers({
      ..._fixture(),
      'sprite': [
        {'id': 'default', 'url': 'sprites/a'},
        {'id': 'other', 'url': 'asset://sprites/b'},
      ],
    }, _styleUrl);
    expect(style['sprite'], [
      {'id': 'default', 'url': 'https://example.com/styles/test/sprites/a'},
      {'id': 'other', 'url': 'asset://sprites/b'},
    ]);
  });

  test('lists the layers that draw features, topmost first', () {
    expect(featureLayerIds(_fixture()), [
      'cafes',
      'lakes',
      'road-names',
      'roads',
      'water',
    ]);
  });

  test('lists the symbol layers', () {
    expect(symbolLayerIds(_fixture()), {'road-names'});
  });

  group('the demo\'s styles', () {
    for (final demoStyle in demoStyles) {
      test(demoStyle.name, () async {
        final url = Uri.parse(demoStyle.url);
        final String json;
        try {
          json = (await fetchHighlightStyle(url)).json;
        } on SocketException catch (e) {
          markTestSkipped('no network connection: $e');
          return;
        }
        final style = jsonDecode(json) as Map<String, Object?>;
        final sources = style['sources']! as Map<String, Object?>;
        final drawn = {
          for (final layer in _layers(style))
            if (layer['source'] case final String source
                when (sources[source]! as Map)['type'] == 'vector' &&
                    !(layer['id']! as String).startsWith('mapigrade-'))
              (source, layer['source-layer']),
        };
        final highlighted = {
          for (final layer in _highlights(style))
            (layer['source'], layer['source-layer']),
        };
        expect(drawn, isNotEmpty);
        expect(highlighted, containsAll(drawn));
      });
    }
  });
}
