// Writes assets/tdff_2026.geojson from tool/waypoints.json (design D116):
// routes each stage through its waypoints with the FOSSGIS OSRM bicycle
// profile, simplifies the line and rounds the coordinates, so that the asset
// is small and a second run writes the same file. Run it by hand from
// packages/demo:
//
//   dart run tool/route_stages.dart
//
// The service allows at most one request per second and requires a user agent
// (https://routing.openstreetmap.de/about.html).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _service =
    'https://routing.openstreetmap.de/routed-bike/route/v1/driving';
const _userAgent =
    'mapigrade-demo-route-stages/1.0 (https://github.com/greensopinion/mapigrade)';

/// The Douglas–Peucker tolerance in metres.
const _tolerance = 10.0;

typedef Point = (double lon, double lat);

Future<void> main() async {
  final input = jsonDecode(
    await File('tool/waypoints.json').readAsString(),
  ) as Map<String, dynamic>;
  final client = HttpClient()..userAgent = _userAgent;
  final features = <Map<String, dynamic>>[];
  try {
    for (final stage
        in (input['stages'] as List).cast<Map<String, dynamic>>()) {
      if (features.isNotEmpty) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final waypoints = [
        for (final w
            in (stage['waypoints'] as List).cast<Map<String, dynamic>>())
          ((w['lon'] as num).toDouble(), (w['lat'] as num).toDouble()),
      ];
      final route = _withoutSpurs(await _route(client, waypoints));
      final line = _simplify(route, _tolerance);
      stdout.writeln(
        'stage ${stage['stage']}: ${route.length} points, ${line.length} '
        'after simplification',
      );
      features.add({
        'type': 'Feature',
        'properties': {
          for (final key in const [
            'stage',
            'date',
            'start',
            'finish',
            'distanceKm',
            'type',
            'winner',
            'team',
            'source',
          ])
            key: stage[key],
          'startPoint': _rounded(waypoints.first),
          'finishPoint': _rounded(waypoints.last),
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [for (final p in line) _rounded(p)],
        },
      });
    }
  } finally {
    client.close();
  }
  // One feature per line, so that a change to one stage changes one line.
  final out = StringBuffer('{"type":"FeatureCollection","features":[\n')
    ..write(features.map(jsonEncode).join(',\n'))
    ..write('\n]}\n');
  await File('assets/tdff_2026.geojson').writeAsString(out.toString());
}

Future<List<Point>> _route(HttpClient client, List<Point> waypoints) async {
  final coordinates = waypoints.map((p) => '${p.$1},${p.$2}').join(';');
  final uri = Uri.parse(
    '$_service/$coordinates?overview=full&geometries=geojson',
  );
  final response = await (await client.getUrl(uri)).close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode}: $body', uri: uri);
  }
  final json = jsonDecode(body) as Map<String, dynamic>;
  final geometry =
      (json['routes'] as List).first['geometry'] as Map<String, dynamic>;
  return [
    for (final c in geometry['coordinates'] as List)
      ((c[0] as num).toDouble(), (c[1] as num).toDouble()),
  ];
}

/// [points] without out-and-back spurs: where a waypoint lies off the race
/// route, the router goes to it and back along the same road, which the race
/// doesn't ride. A point that returns to the point before the previous one
/// cancels the previous one.
List<Point> _withoutSpurs(List<Point> points) {
  bool same(Point a, Point b) =>
      (a.$1 - b.$1).abs() < 1e-6 && (a.$2 - b.$2).abs() < 1e-6;
  final out = <Point>[];
  for (final p in points) {
    if (out.isNotEmpty && same(out.last, p)) continue;
    if (out.length >= 2 && same(out[out.length - 2], p)) {
      out.removeLast();
      continue;
    }
    out.add(p);
  }
  return out;
}

List<double> _rounded(Point p) => [_round5(p.$1), _round5(p.$2)];

double _round5(double v) => (v * 1e5).round() / 1e5;

/// Douglas–Peucker on an equirectangular projection around the line's first
/// point, which is accurate to well under the tolerance over a stage.
List<Point> _simplify(List<Point> points, double tolerance) {
  if (points.length < 3) return points;
  final cosLat = math.cos(points.first.$2 * math.pi / 180);
  const metresPerDegree = 111320.0;
  (double, double) xy(Point p) =>
      (p.$1 * cosLat * metresPerDegree, p.$2 * metresPerDegree);
  final keep = List<bool>.filled(points.length, false)
    ..[0] = true
    ..[points.length - 1] = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    final (ax, ay) = xy(points[first]);
    final (bx, by) = xy(points[last]);
    final dx = bx - ax, dy = by - ay;
    final length2 = dx * dx + dy * dy;
    var farthest = -1;
    var maxDistance = tolerance;
    for (var i = first + 1; i < last; i++) {
      final (px, py) = xy(points[i]);
      final t = length2 == 0
          ? 0.0
          : (((px - ax) * dx + (py - ay) * dy) / length2).clamp(0.0, 1.0);
      final distance = math.sqrt(
        math.pow(px - (ax + t * dx), 2) + math.pow(py - (ay + t * dy), 2),
      );
      if (distance > maxDistance) {
        maxDistance = distance;
        farthest = i;
      }
    }
    if (farthest >= 0) {
      keep[farthest] = true;
      stack
        ..add((first, farthest))
        ..add((farthest, last));
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}
