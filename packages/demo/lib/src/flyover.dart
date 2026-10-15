import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'stages.dart';

/// The zoom at a stage's start and finish, and between stages.
const streetZoom = 14.0;

/// The zoom while the flyover follows a route.
const followZoom = 16.0;

/// The speed along a route, in logical pixels per second at [followZoom]:
/// about 0.85 km/s on the ground at the latitude of the stages.
const followSpeed = 500.0;

/// The fastest the map turns while following a route, in degrees per second.
/// Where the road turns faster, the camera slows down.
const maxTurnRate = 45.0;

/// How far ahead of the rider the camera's center is, as a fraction of the
/// viewport height, so that the view shows where the rider is going.
const lookAhead = 0.2;

// The heading at a point is the direction from [_behind] to [_ahead] of it,
// averaged over [_smoothing] on either side; in pixels at [followZoom]
// (1 px is about 1.7 m).
const _behind = 80.0;
const _ahead = 320.0;
const _smoothing = 320.0;

/// The distance over which the camera speeds up after the start and slows
/// down before the finish, in pixels at [followZoom].
const _ramp = 1200.0;
const _minSpeedFactor = 0.15;

/// The spacing of the precomputed samples, in pixels at [followZoom].
const _sampleSpacing = 16.0;

/// The space around both ends of a move between stages.
const _movePadding = EdgeInsets.all(64);

const _crs = Epsg3857();
final _followScale = math.pow(2, followZoom).toDouble();

/// A position of the flyover's camera. [rotation] is in degrees, from -180
/// to 180.
typedef FlyoverCamera = ({LatLng center, double zoom, double rotation});

/// What a segment of the flyover shows (design D118).
enum SegmentKind {
  holdAtStart,
  turnToRoute,
  followRoute,
  turnToNorth,
  holdAtFinish,
  toNextStart,
}

/// A part of the flyover that moves the camera from [from] to [to].
class Segment {
  Segment._({
    required this.stage,
    required this.kind,
    required this.duration,
    required this.from,
    required this.to,
    this.zoomDip = 0,
    this._follow,
  });

  /// The number of the stage the segment shows; for [SegmentKind.toNextStart],
  /// the stage it leaves.
  final int stage;
  final SegmentKind kind;
  final Duration duration;
  final FlyoverCamera from;
  final FlyoverCamera to;

  /// How far the zoom drops below the linear zoom at mid-way.
  final double zoomDip;

  /// The camera along the route, for [SegmentKind.followRoute].
  final _Follow? _follow;
}

/// The flyover over [Stage]s: a fixed list of segments, and the camera as a
/// function of the time since the start (design D118). It depends only on
/// the stages and the viewport size it was built for, so two flyovers built
/// for the same viewport show the same camera at the same time.
class Flyover {
  Flyover._(this.segments)
    : duration = segments.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// The flyover over [stages], in their order, for the viewport of [camera].
  factory Flyover.build(List<Stage> stages, MapCamera camera) {
    // Only the viewport size of [camera] is used, so the camera's current
    // position doesn't change the sequence.
    final size = camera.nonRotatedSize;
    final viewport = MapCamera(
      crs: _crs,
      center: const LatLng(0, 0),
      zoom: 0,
      rotation: 0,
      nonRotatedSize: size,
    );
    FlyoverCamera northUp(LatLng center) =>
        (center: center, zoom: streetZoom, rotation: 0);

    final segments = <Segment>[];
    void add(
      Stage stage,
      SegmentKind kind,
      Duration duration,
      FlyoverCamera from,
      FlyoverCamera to, {
      double zoomDip = 0,
      _Follow? follow,
    }) => segments.add(
      Segment._(
        stage: stage.number,
        kind: kind,
        duration: duration,
        from: from,
        to: to,
        zoomDip: zoomDip,
        follow: follow,
      ),
    );
    const s2 = Duration(seconds: 2);
    const s3 = Duration(seconds: 3);

    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final follow = _Follow(
        stage.route,
        lookAheadPixels: size.height * lookAhead,
      );
      final start = northUp(stage.startPoint);
      // A loop's finish is its start: the flyover turns north up where the
      // route ends and moves on.
      final end = northUp(stage.isLoop ? stage.route.last : stage.finishPoint);

      add(stage, SegmentKind.holdAtStart, s3, start, start);
      // The turns also zoom between [streetZoom] and [followZoom].
      add(stage, SegmentKind.turnToRoute, s3, start, follow.first);
      add(
        stage,
        SegmentKind.followRoute,
        follow.duration,
        follow.first,
        follow.last,
        follow: follow,
      );
      add(stage, SegmentKind.turnToNorth, s3, follow.last, end);
      if (!stage.isLoop) {
        add(stage, SegmentKind.holdAtFinish, s2, end, end);
      }
      if (i + 1 < stages.length) {
        final next = northUp(stages[i + 1].startPoint);
        add(
          stage,
          SegmentKind.toNextStart,
          const Duration(seconds: 6),
          end,
          next,
          zoomDip: _zoomDip(viewport, end, next),
        );
      }
    }
    return Flyover._(List.unmodifiable(segments));
  }

  final List<Segment> segments;

  /// The time from the start to the end.
  final Duration duration;

  /// The camera at [elapsed] since the start; before the start it is the
  /// first camera, after the end the last.
  FlyoverCamera cameraAt(Duration elapsed) {
    final (segment, t) = _segmentAt(elapsed);
    final follow = segment._follow;
    if (follow != null) return follow.cameraAt(t);
    return _interpolate(
      segment,
      _easeInOut(t.inMicroseconds / segment.duration.inMicroseconds),
    );
  }

  /// The segment at [elapsed] since the start.
  Segment segmentAt(Duration elapsed) => _segmentAt(elapsed).$1;

  /// Where the rider is at [elapsed] while the flyover follows a route, or
  /// null outside a [SegmentKind.followRoute].
  LatLng? riderAt(Duration elapsed) {
    final (segment, t) = _segmentAt(elapsed);
    return segment._follow?.riderAt(t);
  }

  /// The start time of [segments][index].
  Duration startOf(int index) =>
      segments.take(index).fold(Duration.zero, (sum, s) => sum + s.duration);

  /// The segment at [elapsed], and the time since the segment's start.
  (Segment, Duration) _segmentAt(Duration elapsed) {
    var t = elapsed < Duration.zero ? Duration.zero : elapsed;
    for (final segment in segments) {
      if (t < segment.duration) return (segment, t);
      t -= segment.duration;
    }
    return (segments.last, segments.last.duration);
  }
}

/// How far the zoom of a move from [a] to [b] must drop at mid-way so that
/// both centers fit in the viewport there.
double _zoomDip(MapCamera viewport, FlyoverCamera a, FlyoverCamera b) {
  final both = CameraFit.coordinates(
    coordinates: [a.center, b.center],
    padding: _movePadding,
  ).fit(viewport);
  return math.max(0, (a.zoom + b.zoom) / 2 - both.zoom);
}

/// The camera of [segment] at the eased progress [e]: the center in Web
/// Mercator coordinates, the zoom linearly minus the dip, the rotation by the
/// shorter angle.
FlyoverCamera _interpolate(Segment segment, double e) {
  final from = segment.from;
  final to = segment.to;
  final a = _crs.latLngToOffset(from.center, 0);
  final b = _crs.latLngToOffset(to.center, 0);
  return (
    center: _crs.offsetToLatLng(Offset.lerp(a, b, e)!, 0),
    zoom:
        _lerp(from.zoom, to.zoom, e) - segment.zoomDip * math.sin(math.pi * e),
    rotation: _normalized(
      from.rotation + _normalized(to.rotation - from.rotation) * e,
    ),
  );
}

/// The camera that follows a route like a drone ahead of a rider: at
/// [followZoom], with the map turned so that the rider's direction points up.
/// The rider's position, heading and time are precomputed at fixed spacing
/// along the route, so the camera at a time is a lookup.
class _Follow {
  _Follow(List<LatLng> route, {required double lookAheadPixels})
    : _lookAhead = lookAheadPixels / _followScale {
    final path = _Path(route);
    final step = _sampleSpacing / _followScale;
    final count = math.max(1, (path.length / step).ceil());
    for (var i = 0; i <= count; i++) {
      final d = math.min(i * step, path.length);
      _distances.add(d);
      _positions.add(path.at(d));
    }

    // The direction of travel, unwrapped so that it doesn't jump at ±180°.
    final raw = <double>[];
    for (final d in _distances) {
      final behind = path.at(d - _behind / _followScale);
      final ahead = path.at(d + _ahead / _followScale);
      final h = _bearing(ahead - behind);
      raw.add(raw.isEmpty ? h : raw.last + _normalized(h - raw.last));
    }
    final window = (_smoothing / _sampleSpacing).round();
    for (var i = 0; i < raw.length; i++) {
      final lo = math.max(0, i - window);
      final hi = math.min(raw.length - 1, i + window);
      var sum = 0.0;
      for (var j = lo; j <= hi; j++) {
        sum += raw[j];
      }
      _headings.add(sum / (hi - lo + 1));
    }

    // The time at each sample: at [followSpeed], slower near the ends, and
    // slower where the heading turns faster than [maxTurnRate].
    final length = path.length * _followScale;
    _times.add(0);
    for (var i = 1; i < _distances.length; i++) {
      final ds = (_distances[i] - _distances[i - 1]) * _followScale;
      final d = _distances[i] * _followScale;
      final factor = (math.min(d, length - d) / _ramp).clamp(
        _minSpeedFactor,
        1.0,
      );
      final move = ds / (followSpeed * factor);
      final turn = (_headings[i] - _headings[i - 1]).abs() / maxTurnRate;
      _times.add(_times.last + math.max(move, turn));
    }
    duration = Duration(milliseconds: (_times.last * 1000).round());
  }

  final double _lookAhead;
  final _distances = <double>[];
  final _positions = <Offset>[];
  final _headings = <double>[];
  final _times = <double>[];
  late final Duration duration;

  FlyoverCamera get first => _camera(0, 0);
  FlyoverCamera get last => _camera(_times.length - 2, 1);

  FlyoverCamera cameraAt(Duration t) {
    final (i, f) = _sampleAt(t);
    return _camera(i, f);
  }

  /// The rider's position on the route at [t] since the segment's start.
  LatLng riderAt(Duration t) {
    final (i, f) = _sampleAt(t);
    return _crs.offsetToLatLng(_rider(i, f), 0);
  }

  /// The sample before [t], and the fraction of the way to the next one.
  (int, double) _sampleAt(Duration t) {
    final end = (_times.length - 2, 1.0);
    // Scaled so that the end of [duration] is the last sample.
    final seconds =
        t.inMicroseconds / 1e6 * _times.last / (duration.inMicroseconds / 1e6);
    if (seconds >= _times.last) return end;
    // The last sample whose time is at most [seconds].
    var lo = 0, hi = _times.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_times[mid] <= seconds) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo >= _times.length - 1) return end;
    final span = _times[lo + 1] - _times[lo];
    return (lo, span == 0 ? 0.0 : (seconds - _times[lo]) / span);
  }

  Offset _rider(int i, double f) {
    if (_positions.length == 1) i = 0;
    final j = math.min(i + 1, _positions.length - 1);
    return Offset.lerp(_positions[i], _positions[j], f)!;
  }

  /// The camera between samples [i] and `i + 1`, at the fraction [f].
  FlyoverCamera _camera(int i, double f) {
    if (_positions.length == 1) i = 0;
    final j = math.min(i + 1, _positions.length - 1);
    final rider = _rider(i, f);
    final heading = _lerp(_headings[i], _headings[j], f);
    final radians = heading * math.pi / 180;
    // Mercator y grows southward, so north is -y.
    final center =
        rider + Offset(math.sin(radians), -math.cos(radians)) * _lookAhead;
    return (
      center: _crs.offsetToLatLng(center, 0),
      zoom: followZoom,
      // The map turns the other way from the heading, so that it points up.
      rotation: _normalized(-heading),
    );
  }
}

/// A polyline in Web Mercator coordinates at zoom 0, with the distance along
/// it at each point.
class _Path {
  _Path(List<LatLng> points)
    : _points = [for (final p in points) _crs.latLngToOffset(p, 0)] {
    var total = 0.0;
    _distances.add(0);
    for (var i = 1; i < _points.length; i++) {
      total += (_points[i] - _points[i - 1]).distance;
      _distances.add(total);
    }
  }

  final List<Offset> _points;
  final _distances = <double>[];

  /// The length at zoom 0, in pixels.
  double get length => _distances.last;

  /// The point at the distance [d] along the path, clamped to its ends.
  Offset at(double d) {
    d = d.clamp(0.0, length);
    // The last point whose distance is at most d.
    var lo = 0, hi = _points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_distances[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo == _points.length - 1) return _points.last;
    final span = _distances[lo + 1] - _distances[lo];
    final t = span == 0 ? 0.0 : (d - _distances[lo]) / span;
    return Offset.lerp(_points[lo], _points[lo + 1], t)!;
  }
}

/// The compass bearing of [v] in Mercator coordinates, in degrees clockwise
/// from north.
double _bearing(Offset v) => math.atan2(v.dx, -v.dy) * 180 / math.pi;

/// [degrees] in the range -180 to 180.
double _normalized(double degrees) {
  final r = (degrees + 180) % 360 - 180;
  return r == -180 ? 180 : r;
}

double _lerp(double a, double b, double s) => a + (b - a) * s;

/// Cubic ease-in-out.
double _easeInOut(double s) =>
    s < 0.5 ? 4 * s * s * s : 1 - math.pow(-2 * s + 2, 3) / 2;
