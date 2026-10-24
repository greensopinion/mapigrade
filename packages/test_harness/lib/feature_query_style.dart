// The style of the feature query tests (task 3.1 of the add-feature-queries
// change). Every source is inline GeoJSON, so the map renders without network
// access. All features are near the equator and the prime meridian; the tests
// place them on screen with the flutter_map camera.
import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// The longitude of the thin route with ID 1 and class `primary`, drawn 1
/// logical pixel wide.
const primaryRouteLongitude = 0.0;

/// The longitude of the thin route with ID 2 and class `minor`.
const minorRouteLongitude = 0.02;

/// The longitude of the thin route with ID 3 and class `far`, just west of
/// the antimeridian.
const antimeridianRouteLongitude = 179.995;

/// The longitude of the thin line without an ID.
const unnamedLineLongitude = -0.02;

/// The latitude of the two highlight lines, 6 logical pixels wide, which run
/// east to west: ID 10 west of the prime meridian, ID 11 east of it.
const highlightLatitude = 0.01;

/// The cafe with ID 20, drawn as a circle.
const cafe = LatLng(-0.01, 0.01);

/// The colors of the highlight lines: [selectedColor] when their feature
/// state has `selected: true`, otherwise the default color of the variant.
const selectedColor = [255, 0, 0];
const lightDefaultColor = [0, 0, 255];
const darkDefaultColor = [0, 255, 0];

String _hex(List<int> c) =>
    '#${c.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';

Map<String, Object?> _line(
  Object? id,
  List<List<double>> coordinates,
  Map<String, Object?> properties,
) => {
  'type': 'Feature',
  'id': ?id,
  'properties': properties,
  'geometry': {'type': 'LineString', 'coordinates': coordinates},
};

/// The style, in its light or [dark] variant. The variants have the same
/// sources and layers, and differ only in colors.
String featureQueryStyle({bool dark = false}) => jsonEncode({
  'version': 8,
  'sources': {
    'routes': {
      'type': 'geojson',
      'data': {
        'type': 'FeatureCollection',
        'features': [
          _line(
            1,
            [
              [primaryRouteLongitude, -1],
              [primaryRouteLongitude, 1],
            ],
            {'class': 'primary', 'name': 'Primary route'},
          ),
          _line(
            2,
            [
              [minorRouteLongitude, -1],
              [minorRouteLongitude, 1],
            ],
            {'class': 'minor', 'name': 'Minor route'},
          ),
          _line(
            3,
            [
              [antimeridianRouteLongitude, -1],
              [antimeridianRouteLongitude, 1],
            ],
            {'class': 'far', 'name': 'Antimeridian route'},
          ),
        ],
      },
    },
    'unnamed': {
      'type': 'geojson',
      'data': _line(
        null,
        [
          [unnamedLineLongitude, -1],
          [unnamedLineLongitude, 1],
        ],
        {'class': 'primary'},
      ),
    },
    'highlights': {
      'type': 'geojson',
      'data': {
        'type': 'FeatureCollection',
        'features': [
          _line(
            10,
            [
              [-1, highlightLatitude],
              [-0.005, highlightLatitude],
            ],
            {'name': 'West'},
          ),
          _line(
            11,
            [
              [0.005, highlightLatitude],
              [1, highlightLatitude],
            ],
            {'name': 'East'},
          ),
        ],
      },
    },
    'pois': {
      'type': 'geojson',
      'data': {
        'type': 'Feature',
        'id': 20,
        'properties': {'class': 'cafe'},
        'geometry': {
          'type': 'Point',
          'coordinates': [cafe.longitude, cafe.latitude],
        },
      },
    },
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': dark ? '#202020' : '#ffffff'},
    },
    {
      'id': 'routes',
      'type': 'line',
      'source': 'routes',
      'paint': {'line-width': 1, 'line-color': dark ? '#c0c0c0' : '#404040'},
    },
    {
      'id': 'unnamed',
      'type': 'line',
      'source': 'unnamed',
      'paint': {'line-width': 1, 'line-color': dark ? '#c0c0c0' : '#404040'},
    },
    {
      'id': 'highlights',
      'type': 'line',
      'source': 'highlights',
      'paint': {
        'line-width': 6,
        'line-color': [
          'case',
          [
            'boolean',
            ['feature-state', 'selected'],
            false,
          ],
          _hex(selectedColor),
          _hex(dark ? darkDefaultColor : lightDefaultColor),
        ],
      },
    },
    {
      'id': 'poi',
      'type': 'circle',
      'source': 'pois',
      'paint': {'circle-radius': 6, 'circle-color': '#ff9900'},
    },
  ],
});
