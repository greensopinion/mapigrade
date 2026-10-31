import 'dart:ui';

import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

/// A route of the polyline showcase, with the legend's description of how it
/// is drawn.
typedef DemoRoute = ({String name, String drawnAs, MapigradePolyline polyline});

// The points are read from OpenStreetMap's street centerlines, one at each
// bend (design D205).

/// The southbound carriageway, from Bowling Green to City Hall Park.
const _broadway = [
  LatLng(40.70580, -74.01336),
  LatLng(40.71135, -74.00875),
  LatLng(40.71139, -74.00865),
  LatLng(40.71304, -74.00723),
];

/// From the Whitehall Terminal into the Upper Bay.
const _ferry = [
  LatLng(40.70055, -74.01303),
  LatLng(40.69966, -74.01285),
  LatLng(40.69925, -74.01307),
  LatLng(40.69889, -74.01358),
  LatLng(40.69627, -74.02033),
  LatLng(40.69496, -74.02317),
  LatLng(40.69427, -74.02434),
  LatLng(40.69243, -74.02668),
  LatLng(40.69126, -74.02789),
  LatLng(40.68626, -74.03259),
];

/// The northbound carriageway, from the Battery to Chambers Street.
const _westStreet = [
  LatLng(40.70522, -74.01643),
  LatLng(40.70667, -74.01594),
  LatLng(40.70883, -74.01507),
  LatLng(40.70992, -74.01470),
  LatLng(40.71115, -74.01436),
  LatLng(40.71300, -74.01396),
  LatLng(40.71454, -74.01338),
  LatLng(40.71642, -74.01293),
];

/// From Broadway to South Street.
const _wallStreet = [
  LatLng(40.70777, -74.01172),
  LatLng(40.70638, -74.00950),
  LatLng(40.70529, -74.00753),
  LatLng(40.70425, -74.00629),
];

/// The routes in draw order, created once so that rebuilds of the screen
/// pass the same polylines and send nothing to the map (design D205).
final List<DemoRoute> demoRoutes = [
  (
    name: 'Broadway',
    drawnAs: '6 px with a white border',
    polyline: MapigradePolyline(
      points: _broadway,
      strokeWidth: 6,
      color: const Color(0xFF1E5BD8),
      borderStrokeWidth: 3,
      borderColor: const Color(0xFFFFFFFF),
    ),
  ),
  (
    name: 'Staten Island Ferry',
    drawnAs: '4 px, dashed',
    polyline: MapigradePolyline(
      points: _ferry,
      strokeWidth: 4,
      color: const Color(0xFFF57C00),
      strokeCap: StrokeCap.butt,
      dashes: const [2, 2],
    ),
  ),
  (
    name: 'West Street',
    drawnAs: '6 px, from green to red',
    polyline: MapigradePolyline(
      points: _westStreet,
      strokeWidth: 6,
      gradientColors: const [Color(0xFF2E7D32), Color(0xFFD32F2F)],
    ),
  ),
  (
    name: 'Wall Street',
    drawnAs: '12 m, translucent',
    polyline: MapigradePolyline(
      points: _wallStreet,
      strokeWidth: 12,
      useStrokeWidthInMeter: true,
      color: const Color(0x998E24AA),
    ),
  ),
];

/// The polylines of [demoRoutes], created once.
final List<MapigradePolyline> demoRoutePolylines = [
  for (final route in demoRoutes) route.polyline,
];

/// A pin at one end of a route.
typedef DemoPin = ({LatLng point, Color color});

/// A pin at the start and at the end of each of [demoRoutes], in the route's
/// color at that end, opaque so that the translucent route's pins show.
final List<DemoPin> demoRoutePins = [
  for (final route in demoRoutes)
    for (final (point, color) in [
      (
        route.polyline.points.first,
        route.polyline.gradientColors?.first ?? route.polyline.color,
      ),
      (
        route.polyline.points.last,
        route.polyline.gradientColors?.last ?? route.polyline.color,
      ),
    ])
      (point: point, color: color.withAlpha(255)),
];
