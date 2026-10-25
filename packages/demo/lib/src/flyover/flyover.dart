import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'stages.dart';

/// The zoom at a stage's start and finish, and between stages.
const streetZoom = 14.0;

/// The zoom while the flyover follows a route.
const followZoom = 16.0;

/// The pitch while the flyover follows a route, in degrees, so that the
/// drone looks ahead of the rider. The flyover is north up and unpitched at a
/// stage's start and finish, and between stages.
const followPitch = 50.0;

/// The speed along a route, in logical pixels per second at [followZoom]:
/// about 0.85 km/s on the ground at the latitude of the stages.
const followSpeed = 500.0;

/// The fastest the map turns while following a route, in degrees per second.
/// Where the road turns faster, the camera slows down.
const maxTurnRate = 25.0;

/// How far ahead of the rider the camera's center is, as a fraction of the
/// viewport height, so that the view shows where the rider is going.
const lookAhead = 0.2;

/// How far the rider may drift from its place below the center while the
/// drone cuts a corner, as a fraction of the viewport's shorter side. Where
/// the drone would drift further, the rider slows down.
const maxDrift = 0.2;

// The slowdown aims for this fraction of [maxDrift], and is planned again at
// most this many times.
const _driftTarget = 0.85;
const _driftPasses = 8;

// The direction of the road at a point is from [_behind] to [_ahead] of it,
// in pixels at [followZoom] (1 px is about 1.7 m). The course, which sets the
// speed, is that direction smoothed with a Gaussian of [_courseSigma].
const _behind = 80.0;
const _ahead = 320.0;
const _courseSigma = 480.0;

/// How fast the rider speeds up and slows down, in pixels per second squared
/// at [followZoom]; from [_minSpeedFactor] of [followSpeed] at the ends.
const _acceleration = 100.0;
const _minSpeedFactor = 0.15;

// The drone smooths the rider's track over time, with Gaussians of these
// widths in seconds: its position, so that it cuts corners, and its heading,
// so that the map turns gradually and its turn rate changes gradually.
const _positionSigma = 1.2;
const _headingSigma = 1.5;

/// The spacing of the precomputed samples, in pixels at [followZoom].
const _sampleSpacing = 16.0;

/// The interval of the drone's precomputed frames, in seconds.
const _frameInterval = 1 / 60;

/// The space around both ends of a move between stages.
const _movePadding = EdgeInsets.all(64);

const _crs = Epsg3857();
final _followScale = math.pow(2, followZoom).toDouble();

/// A position of the flyover's camera. [rotation] is in degrees, from -180
/// to 180, and [pitch] in degrees.
typedef FlyoverCamera = ({
  LatLng center,
  double zoom,
  double rotation,
  double pitch,
});

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
        (center: center, zoom: streetZoom, rotation: 0, pitch: 0);

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

    // The rider's place and drift are given on screen; the follow camera
    // places the rider on the ground, which the pitch shows foreshortened.
    final follower = MapCamera(
      crs: _crs,
      center: const LatLng(0, 0),
      zoom: followZoom,
      rotation: 0,
      nonRotatedSize: size,
      pitch: followPitch,
    );
    Offset ground(Offset screen) =>
        follower.projectAtZoom(follower.screenOffsetToLatLng(screen)) -
        follower.projectAtZoom(follower.center);
    final rider = size.center(Offset.zero) + Offset(0, size.height * lookAhead);
    final lookAheadPixels = ground(rider).dy;
    // The pitched map is shown largest sideways and towards the viewer, so the
    // smaller of those ground distances keeps a drift in any direction within
    // maxDrift on screen.
    final drift = size.shortestSide * maxDrift;
    final maxDriftPixels = math.min(
      (ground(rider + Offset(drift, 0)) - ground(rider)).distance,
      (ground(rider + Offset(0, drift)) - ground(rider)).distance,
    );

    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final follow = _Follow(
        stage.route,
        lookAheadPixels: lookAheadPixels,
        maxDriftPixels: maxDriftPixels,
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
/// shorter angle, and the pitch linearly.
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
    pitch: _lerp(from.pitch, to.pitch, e),
  );
}

/// The camera that follows a route like a drone ahead of a rider, at
/// [followZoom].
///
/// The rider keeps strictly to the route. The drone doesn't: it flies a
/// smoothed version of the rider's track, so that it cuts tight corners and
/// turns gradually, with the map turned so that the course points up. The
/// rider therefore drifts a little around its place below the center on
/// bends, by at most [maxDrift].
///
/// Everything is precomputed: the rider's position and time at samples a
/// fixed distance apart along the route, and the drone's frames at a fixed
/// interval in time, so the camera at a time is a lookup.
class _Follow {
  _Follow(
    List<LatLng> route, {
    required double lookAheadPixels,
    required double maxDriftPixels,
  }) : _lookAhead = lookAheadPixels / _followScale,
       _maxDrift = maxDriftPixels / _followScale {
    final path = _Path(route);
    final step = _sampleSpacing / _followScale;
    final count = math.max(1, (path.length / step).ceil());
    final distances = <double>[];
    for (var i = 0; i <= count; i++) {
      final d = math.min(i * step, path.length);
      distances.add(d);
      _positions.add(path.at(d));
    }

    // The course: the direction of the road, unwrapped so that it doesn't
    // jump at ±180°, and smoothed so that a hairpin's 180° doesn't spin the
    // map. It is the heading the drone aims for.
    final raw = <double>[];
    for (final d in distances) {
      final behind = path.at(d - _behind / _followScale);
      final ahead = path.at(d + _ahead / _followScale);
      final h = _bearing(ahead - behind);
      raw.add(raw.isEmpty ? h : raw.last + _normalized(h - raw.last));
    }
    final course = _gaussian(raw, _courseSigma / _sampleSpacing);

    // The rider's speed: [followSpeed], lower where the course turns faster
    // than [maxTurnRate] at that speed, from and to [_minSpeedFactor] of it
    // at the ends.
    final n = distances.length;
    final limit = List<double>.filled(n, followSpeed);
    for (var i = 0; i < n; i++) {
      final lo = math.max(0, i - 1), hi = math.min(n - 1, i + 1);
      if (hi == lo) continue;
      final degreesPerPixel =
          (course[hi] - course[lo]).abs() / ((hi - lo) * _sampleSpacing);
      if (degreesPerPixel > 0) {
        limit[i] = math.min(followSpeed, maxTurnRate / degreesPerPixel);
      }
    }
    final endSpeed = followSpeed * _minSpeedFactor;
    limit[0] = math.min(limit[0], endSpeed);
    limit[n - 1] = math.min(limit[n - 1], endSpeed);

    // The drone drifts further from the rider on a bend the faster the rider
    // takes it, so where it drifts more than [_maxDrift], the rider slows
    // down there, and the flight is planned again.
    final window = (_positionSigma / _frameInterval).ceil();
    var flight = _fly(distances, course, limit);
    for (var pass = 0; pass < _driftPasses; pass++) {
      final factor = List<double>.filled(n, 1);
      var over = false;
      for (var k = 0; k < flight.drifts.length; k++) {
        final d = flight.drifts[k].distance;
        if (d <= _maxDrift * _driftTarget) continue;
        over = over || d > _maxDrift;
        final r = _maxDrift * _driftTarget / d;
        // Every frame within the smoothing window contributes to the drift.
        final lo = math.max(0, k - window);
        final hi = math.min(flight.samples.length - 1, k + window);
        for (var m = lo; m <= hi; m++) {
          final i = flight.samples[m];
          factor[i] = math.min(factor[i], r);
        }
      }
      if (!over) break;
      for (var i = 0; i < n; i++) {
        limit[i] *= factor[i];
      }
      flight = _fly(distances, course, limit);
    }

    duration = Duration(milliseconds: (_times.last * 1000).round());
    for (var k = 0; k < flight.drifts.length; k++) {
      // A last guard that keeps the rider on screen; with the slowdown above
      // the drone stays within [_maxDrift] and this doesn't change it.
      var drift = flight.drifts[k];
      if (drift.distance > _maxDrift) {
        drift = drift * (_maxDrift / drift.distance);
      }
      final radians = _headings[k] * math.pi / 180;
      // Mercator y grows southward, so north is -y.
      _centers.add(
        flight.riders[k] +
            drift +
            Offset(math.sin(radians), -math.cos(radians)) * _lookAhead,
      );
    }
  }

  /// Plans the rider's times for the speed [limit], changing by no more than
  /// [_acceleration], and the drone's frames over them. Sets [_times],
  /// [_frameTimes] and [_headings].
  ({List<Offset> riders, List<Offset> drifts, List<int> samples}) _fly(
    List<double> distances,
    List<double> course,
    List<double> limit,
  ) {
    final n = distances.length;
    final speed = List<double>.of(limit);
    for (var i = 1; i < n; i++) {
      final ds = (distances[i] - distances[i - 1]) * _followScale;
      speed[i] = math.min(
        speed[i],
        math.sqrt(speed[i - 1] * speed[i - 1] + 2 * _acceleration * ds),
      );
    }
    for (var i = n - 2; i >= 0; i--) {
      final ds = (distances[i + 1] - distances[i]) * _followScale;
      speed[i] = math.min(
        speed[i],
        math.sqrt(speed[i + 1] * speed[i + 1] + 2 * _acceleration * ds),
      );
    }
    _times
      ..clear()
      ..add(0);
    for (var i = 1; i < n; i++) {
      final ds = (distances[i] - distances[i - 1]) * _followScale;
      _times.add(_times.last + 2 * ds / (speed[i - 1] + speed[i]));
    }
    final total = _times.last;

    // The rider's track and course at a fixed interval in time, smoothed over
    // time into the drone's flight. A symmetric smoothing of a straight track
    // at a steady speed is the track itself, so the drone doesn't lag the
    // rider; it only rounds the corners.
    final frames = math.max(1, (total / _frameInterval).ceil());
    final riders = <Offset>[];
    final courses = <double>[];
    final samples = <int>[];
    _frameTimes.clear();
    for (var k = 0; k <= frames; k++) {
      _frameTimes.add(math.min(k * _frameInterval, total));
      final (i, f) = _sampleAt(_frameTimes.last);
      riders.add(_rider(i, f));
      samples.add(f < 0.5 ? i : math.min(i + 1, n - 1));
      final j = math.min(i + 1, n - 1);
      courses.add(_lerp(course[i], course[j], f));
    }
    final xs = _gaussian([
      for (final p in riders) p.dx,
    ], _positionSigma / _frameInterval);
    final ys = _gaussian([
      for (final p in riders) p.dy,
    ], _positionSigma / _frameInterval);
    _headings
      ..clear()
      ..addAll(_gaussian(courses, _headingSigma / _frameInterval));
    return (
      riders: riders,
      drifts: [
        for (var k = 0; k <= frames; k++) Offset(xs[k], ys[k]) - riders[k],
      ],
      samples: samples,
    );
  }

  final double _lookAhead;
  final double _maxDrift;
  final _positions = <Offset>[];
  final _times = <double>[];
  final _frameTimes = <double>[];
  final _centers = <Offset>[];
  final _headings = <double>[];
  late final Duration duration;

  FlyoverCamera get first => _frame(0, 0);
  FlyoverCamera get last => _frame(_centers.length - 1, 0);

  FlyoverCamera cameraAt(Duration t) {
    final seconds = _seconds(t);
    final total = _frameTimes.last;
    if (seconds >= total) return last;
    final k = math.min((seconds / _frameInterval).floor(), _centers.length - 2);
    final span = _frameTimes[k + 1] - _frameTimes[k];
    return _frame(k, span == 0 ? 0 : (seconds - _frameTimes[k]) / span);
  }

  /// The rider's position on the route at [t] since the segment's start.
  LatLng riderAt(Duration t) {
    final (i, f) = _sampleAt(_seconds(t));
    return _crs.offsetToLatLng(_rider(i, f), 0);
  }

  /// [t] in seconds, scaled so that the end of [duration] is the last sample.
  double _seconds(Duration t) {
    if (duration == Duration.zero) return _times.last;
    return t.inMicroseconds / duration.inMicroseconds * _times.last;
  }

  /// The sample before [seconds], and the fraction of the way to the next one.
  (int, double) _sampleAt(double seconds) {
    final end = (math.max(0, _times.length - 2), 1.0);
    if (_times.length == 1 || seconds >= _times.last) return end;
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
    final j = math.min(i + 1, _positions.length - 1);
    return Offset.lerp(_positions[i], _positions[j], f)!;
  }

  /// The drone's camera between frames [k] and `k + 1`, at the fraction [f].
  FlyoverCamera _frame(int k, double f) {
    final j = math.min(k + 1, _centers.length - 1);
    final heading = _lerp(_headings[k], _headings[j], f);
    return (
      center: _crs.offsetToLatLng(Offset.lerp(_centers[k], _centers[j], f)!, 0),
      zoom: followZoom,
      // The map turns the other way from the heading, so that it points up.
      rotation: _normalized(-heading),
      pitch: followPitch,
    );
  }
}

/// [values] smoothed with a Gaussian of [sigma] samples, with the first and
/// last values held beyond the ends.
List<double> _gaussian(List<double> values, double sigma) {
  if (sigma <= 0 || values.length < 2) return List.of(values);
  final radius = (3 * sigma).ceil();
  final weights = [
    for (var o = -radius; o <= radius; o++)
      math.exp(-o * o / (2 * sigma * sigma)),
  ];
  final norm = weights.fold(0.0, (a, b) => a + b);
  final last = values.length - 1;
  return [
    for (var i = 0; i <= last; i++)
      () {
        var sum = 0.0;
        for (var o = -radius; o <= radius; o++) {
          sum += weights[o + radius] * values[(i + o).clamp(0, last)];
        }
        return sum / norm;
      }(),
  ];
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
