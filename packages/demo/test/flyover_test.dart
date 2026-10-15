// The flyover's camera (design D118) and the scenarios "Deterministic camera"
// and "Stage order" of the demo-app spec, requirement "Flyover".
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade_demo/src/flyover.dart';
import 'package:mapigrade_demo/src/stages.dart';

const _viewport = Size(1200, 800);

MapCamera _camera({
  LatLng center = const LatLng(43.7, 7.27),
  double zoom = 12,
  double rotation = 0,
  Size size = _viewport,
}) => MapCamera(
  crs: const Epsg3857(),
  center: center,
  zoom: zoom,
  rotation: rotation,
  nonRotatedSize: size,
);

MapCamera _view(FlyoverCamera c) =>
    _camera(center: c.center, zoom: c.zoom, rotation: c.rotation);

/// Where the rider is on screen: below the center by the look-ahead.
const _riderOnScreen = Offset(600, 400 + 800 * lookAhead);

/// The distance in metres from [p] to the polyline [route].
double _distanceToRoute(LatLng p, List<LatLng> route) {
  final cosLat = math.cos(p.latitudeInRad);
  Offset xy(LatLng q) => Offset(
    (q.longitude - p.longitude) * cosLat * 111320,
    (q.latitude - p.latitude) * 111320,
  );
  var best = double.infinity;
  for (var i = 1; i < route.length; i++) {
    final a = xy(route[i - 1]), b = xy(route[i]);
    final ab = b - a;
    final l2 = ab.distanceSquared;
    final t = l2 == 0
        ? 0.0
        : ((-a.dx * ab.dx - a.dy * ab.dy) / l2).clamp(0.0, 1.0);
    best = math.min(best, (a + ab * t).distance);
  }
  return best;
}

double _turn(double a, double b) {
  final d = (b - a + 180) % 360 - 180;
  return d.abs();
}

void main() {
  final stages = parseStages(File(stagesAsset).readAsStringSync());
  final flyover = Flyover.build(stages, _camera());
  const distance = Distance();

  Iterable<(int, Segment)> indexed() => flyover.segments.indexed;
  Duration mid(int i) => flyover.startOf(i) + flyover.segments[i].duration ~/ 2;
  Duration end(int i) => flyover.startOf(i) + flyover.segments[i].duration;
  List<int> follows() => [
    for (final (i, s) in indexed())
      if (s.kind == SegmentKind.followRoute) i,
  ];

  test('the same time and viewport give the same camera', () {
    // Built again from another camera position in the same viewport.
    final again = Flyover.build(
      stages,
      _camera(center: const LatLng(47.3, 5.0), zoom: 5, rotation: 45),
    );
    for (var ms = 0; ms <= flyover.duration.inMilliseconds; ms += 250) {
      final t = Duration(milliseconds: ms);
      expect(again.cameraAt(t), flyover.cameraAt(t), reason: '$t');
    }
  });

  test('the stages come in the order of the data and end at Dijon', () {
    final order = <int>[];
    for (final s in flyover.segments) {
      if (order.isEmpty || order.last != s.stage) order.add(s.stage);
    }
    expect(order, [9, 7, 4]);

    final first = flyover.cameraAt(Duration.zero);
    expect(
      distance.distance(first.center, stages.first.startPoint),
      lessThan(1),
    );
    expect(first.zoom, streetZoom);
    expect(first.rotation, 0);

    final last = flyover.cameraAt(flyover.duration);
    expect(flyover.segments.last.kind, SegmentKind.holdAtFinish);
    expect(flyover.segments.last.stage, 4);
    expect(
      distance.distance(last.center, stages.last.finishPoint),
      lessThan(1),
    );
    expect(last.zoom, streetZoom);
    expect(last.rotation, 0);
    expect(
      flyover.cameraAt(flyover.duration + const Duration(seconds: 5)),
      last,
    );
  });

  test(
    'each stage shows its start, its route and, unless a loop, its finish',
    () {
      List<SegmentKind> kinds(int stage) => [
        for (final s in flyover.segments)
          if (s.stage == stage && s.kind != SegmentKind.toNextStart) s.kind,
      ];
      const route = [
        SegmentKind.holdAtStart,
        SegmentKind.turnToRoute,
        SegmentKind.followRoute,
        SegmentKind.turnToNorth,
      ];
      // Stage 9 is Nice to Nice: its finish is skipped.
      expect(kinds(9), route);
      expect(kinds(7), [...route, SegmentKind.holdAtFinish]);
      expect(kinds(4), [...route, SegmentKind.holdAtFinish]);
    },
  );

  test('the camera follows each route at z16 with the rider ahead of it', () {
    expect(followZoom, 16);
    expect(follows(), hasLength(stages.length));
    for (final (n, i) in follows().indexed) {
      final stage = stages[n];
      final s = flyover.segments[i];
      expect(s.stage, stage.number);
      LatLng rider(Duration t) =>
          _view(flyover.cameraAt(t)).screenOffsetToLatLng(_riderOnScreen);

      expect(
        distance.distance(rider(flyover.startOf(i)), stage.route.first),
        lessThan(5),
      );
      expect(
        distance.distance(
          rider(end(i) - const Duration(milliseconds: 1)),
          stage.route.last,
        ),
        lessThan(5),
      );
      for (var ms = 0; ms < s.duration.inMilliseconds; ms += 200) {
        final t = flyover.startOf(i) + Duration(milliseconds: ms);
        expect(flyover.cameraAt(t).zoom, followZoom);
        // The rider moves on chords between samples 16 px (about 28 m)
        // apart, which cut a hairpin's corner by a few metres.
        expect(
          _distanceToRoute(rider(t), stage.route),
          lessThan(10),
          reason: 'stage ${stage.number} at $ms ms',
        );
      }
    }
  });

  test('the rider is shown only while the flyover follows a route', () {
    for (final (i, s) in indexed()) {
      for (final t in [flyover.startOf(i), mid(i)]) {
        final rider = flyover.riderAt(t);
        if (s.kind != SegmentKind.followRoute) {
          expect(rider, isNull, reason: '${s.stage} ${s.kind}');
          continue;
        }
        // At the point below the screen's center by the look-ahead.
        final onScreen = _view(flyover.cameraAt(t))
            .latLngToScreenOffset(rider!);
        expect((onScreen - _riderOnScreen).distance, lessThan(0.5));
      }
    }
  });

  test('the rider travels up the screen', () {
    for (final (n, i) in follows().indexed) {
      final s = flyover.segments[i];
      var up = 0, samples = 0;
      for (var ms = 0; ms + 500 < s.duration.inMilliseconds; ms += 200) {
        final t = flyover.startOf(i) + Duration(milliseconds: ms);
        final view = _view(flyover.cameraAt(t));
        final later = _view(
          flyover.cameraAt(t + const Duration(milliseconds: 500)),
        ).screenOffsetToLatLng(_riderOnScreen);
        // Where the rider will be in 0.5 s, seen from the camera now.
        final move = view.latLngToScreenOffset(later) - _riderOnScreen;
        if (move.distance < 1) continue;
        samples++;
        // Within 45° of straight up.
        if (-move.dy > move.dx.abs()) up++;
      }
      expect(samples, greaterThan(0));
      expect(
        up / samples,
        greaterThan(0.9),
        reason: 'stage ${stages[n].number}: $up of $samples',
      );
    }
  });

  test('the map turns no faster than the maximum turn rate', () {
    for (final i in follows()) {
      final s = flyover.segments[i];
      const dt = Duration(milliseconds: 100);
      for (var t = flyover.startOf(i); t + dt <= end(i); t += dt) {
        final turn = _turn(
          flyover.cameraAt(t).rotation,
          flyover.cameraAt(t + dt).rotation,
        );
        expect(
          turn,
          lessThanOrEqualTo(maxTurnRate * 0.1 + 0.5),
          reason: 'stage ${s.stage} at $t',
        );
      }
    }
  });

  test('the map is north up before it moves on', () {
    for (final (i, s) in indexed()) {
      if (s.kind == SegmentKind.turnToNorth) {
        expect(flyover.cameraAt(end(i)).rotation, closeTo(0, 1e-9));
      }
      if (s.kind == SegmentKind.toNextStart ||
          s.kind == SegmentKind.holdAtFinish) {
        for (final t in [flyover.startOf(i), mid(i), end(i)]) {
          expect(flyover.cameraAt(t).rotation, closeTo(0, 1e-9), reason: '$t');
        }
      }
    }
  });

  test('a move between stages dips the zoom so both ends fit mid-way', () {
    final moves = [
      for (final (i, s) in indexed())
        if (s.kind == SegmentKind.toNextStart) i,
    ];
    expect(moves, hasLength(2));
    for (final i in moves) {
      final s = flyover.segments[i];
      final camera = flyover.cameraAt(mid(i));
      expect(s.zoomDip, greaterThan(0));
      expect(camera.zoom, lessThan(s.from.zoom - 1));
      expect(camera.zoom, lessThan(s.to.zoom - 1));

      // At mid-way both the place it leaves and the next start are on screen.
      final view = _view(camera);
      for (final point in [s.from.center, s.to.center]) {
        final offset = view.latLngToScreenOffset(point);
        expect(offset.dx, inInclusiveRange(0, _viewport.width), reason: '$i');
        expect(offset.dy, inInclusiveRange(0, _viewport.height), reason: '$i');
      }
    }
  });

  test('the camera is continuous between segments', () {
    for (final (i, s) in indexed().skip(1)) {
      final previous = flyover.segments[i - 1];
      expect(s.from, previous.to, reason: '$i');
      final t = flyover.startOf(i);
      final before = flyover.cameraAt(t - const Duration(milliseconds: 1));
      final after = flyover.cameraAt(t);
      expect(
        distance.distance(before.center, after.center),
        lessThan(50),
        reason: '$i ${s.kind}',
      );
      expect(_turn(before.rotation, after.rotation), lessThan(1), reason: '$i');
    }
  });
}
