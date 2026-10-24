import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// The race of the stages, as its official site names it.
const raceName = 'Tour de France Femmes avec Zwift 2026';

/// The stage data asset, which `tool/route_stages.dart` writes.
const stagesAsset = 'assets/tdff_2026.geojson';

/// A stage closer than this from start to finish starts and finishes at the
/// same place, and has one pin for both.
const loopDistanceMetres = 500.0;

/// A stage of the Tour de France Femmes avec Zwift 2026, with its approximate
/// route.
class Stage {
  const Stage({
    required this.number,
    required this.date,
    required this.start,
    required this.finish,
    required this.distanceKm,
    required this.type,
    required this.winner,
    required this.team,
    required this.source,
    required this.startPoint,
    required this.finishPoint,
    required this.route,
  });

  final int number;
  final DateTime date;
  final String start;
  final String finish;
  final double distanceKm;
  final String type;
  final String winner;
  final String team;

  /// The official stage page the facts come from.
  final Uri source;

  final LatLng startPoint;
  final LatLng finishPoint;
  final List<LatLng> route;

  /// Whether the stage starts and finishes at the same place.
  bool get isLoop =>
      const Distance().distance(startPoint, finishPoint) < loopDistanceMetres;
}

Future<List<Stage>> loadStages(AssetBundle bundle) async =>
    parseStages(await bundle.loadString(stagesAsset));

/// The stages of the GeoJSON FeatureCollection [geojson], in its order.
List<Stage> parseStages(String geojson) {
  final features =
      (jsonDecode(geojson) as Map<String, dynamic>)['features'] as List;
  return [
    for (final feature in features.cast<Map<String, dynamic>>())
      _stage(
        feature['properties'] as Map<String, dynamic>,
        (feature['geometry'] as Map<String, dynamic>)['coordinates'] as List,
      ),
  ];
}

Stage _stage(Map<String, dynamic> p, List coordinates) => Stage(
  number: p['stage'] as int,
  date: DateTime.parse(p['date'] as String),
  start: p['start'] as String,
  finish: p['finish'] as String,
  distanceKm: (p['distanceKm'] as num).toDouble(),
  type: p['type'] as String,
  winner: p['winner'] as String,
  team: p['team'] as String,
  source: Uri.parse(p['source'] as String),
  startPoint: _latLng(p['startPoint'] as List),
  finishPoint: _latLng(p['finishPoint'] as List),
  route: [for (final c in coordinates) _latLng(c as List)],
);

/// A GeoJSON position, `[lon, lat]`.
LatLng _latLng(List position) =>
    LatLng((position[1] as num).toDouble(), (position[0] as num).toDouble());
