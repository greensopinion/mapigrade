// The stop, fling and reversal motions of the alignment benchmark, and the
// overshoot after each motion change (design D35 of the camera-prediction
// change).
import 'dart:math' as math;

import 'package:flutter/physics.dart';

/// The speed of the pans in these motions, in logical px/s.
const motionSpeed = 1000.0;

/// The time after a motion change, once the camera is at rest or at constant
/// speed again, that the overshoot window still covers, in seconds.
const settleTime = 0.5;

/// The window of one motion change: the overshoot is the largest drawn error
/// over the Flutter frames whose vsync time lies in [start, end], in seconds
/// since the phase started. [east] is the direction of motion before the
/// change: 1 eastwards, -1 westwards.
typedef MotionChange = ({double start, double end, double east});

/// The drawn error of one Flutter frame at [time] seconds since the phase
/// started, and [centerDx], the x offset at the viewport center from where
/// the overlays draw a coordinate to where the map draws it.
typedef FrameError = ({double time, double error, double centerDx});

/// A motion along the pan path: the distance east of the path's start in
/// logical pixels as a function of the time since the phase started, and
/// the windows of its motion changes.
class Motion {
  const Motion(this.east, this.changes);

  final double Function(double t) east;

  /// The motion changes whose windows end by the given phase duration.
  final List<MotionChange> Function(double duration) changes;
}

/// `flutter_map`'s fling after a release at [motionSpeed] (flutter_map 8.3.2,
/// `map_interactive_viewer.dart`): `AnimationController.fling` runs this
/// spring over the controller's value from 0 towards 1.01, starting at
/// [motionSpeed] / 1000 per second, and clamps the value at 1. The camera
/// moves the viewport's shorter side times the value.
class Fling {
  Fling(this.distance)
    : _spring = SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 5),
        0,
        1.01,
        motionSpeed / 1000,
      ) {
    duration = _firstTime((t) => _spring.x(t) >= 1);
    settled = _firstTime((t) => (1 - _spring.x(t)) * distance < 0.5);
  }

  /// The viewport's shorter side, in logical pixels.
  final double distance;
  final SpringSimulation _spring;

  /// The time at which the value reaches 1 and the camera stops, in seconds.
  late final double duration;

  /// The time at which the remaining distance falls below 0.5 px, in
  /// seconds.
  late final double settled;

  /// The distance moved [t] seconds after the release.
  double offset(double t) =>
      t >= duration ? distance : _spring.x(t).clamp(0, 1) * distance;

  /// The speed [t] seconds after the release, in logical px/s.
  double speed(double t) => t >= duration ? 0 : _spring.dx(t) * distance;

  /// The first time at which [done] holds, to within a microsecond; [done]
  /// must hold from that time on.
  double _firstTime(bool Function(double t) done) {
    var lo = 0.0, hi = 10.0;
    while (hi - lo > 1e-6) {
      final mid = (lo + hi) / 2;
      if (done(mid)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }
}

/// Pan for 1 s, rest for 1 s, repeated; the pans go east and west in turn.
/// Each stop is a motion change.
Motion stopMotion() => Motion(
  (t) {
    final cycle = (t / 2).floor();
    final moved = (t - 2 * cycle).clamp(0.0, 1.0) * motionSpeed;
    return cycle.isEven ? moved : motionSpeed - moved;
  },
  (duration) => [
    for (var stop = 1.0; stop + settleTime <= duration; stop += 2)
      (start: stop, end: stop + settleTime, east: _eastIfEven(stop ~/ 2)),
  ],
);

/// Pan for 1 s, then fling, then rest until the 3 s cycle ends, repeated;
/// the cycles go east and west in turn. Each fling is a motion change, from
/// its start until [settleTime] after its remaining distance is below
/// 0.5 px.
Motion flingMotion(Fling fling) {
  const cycle = 3.0;
  assert(1 + fling.settled + settleTime <= cycle);
  return Motion(
    (t) {
      final n = (t / cycle).floor();
      final s = t - n * cycle;
      final moved = s <= 1
          ? s * motionSpeed
          : motionSpeed + fling.offset(s - 1);
      return n.isEven ? moved : motionSpeed + fling.distance - moved;
    },
    (duration) => [
      for (
        var start = 1.0;
        start + fling.settled + settleTime <= duration;
        start += cycle
      )
        (
          start: start,
          end: start + fling.settled + settleTime,
          east: _eastIfEven(start ~/ cycle),
        ),
    ],
  );
}

/// Pan, reversing the direction every 1 s. Each reversal is a motion change.
Motion reverseMotion() => Motion(
  (t) {
    final n = t.floor();
    final moved = (t - n) * motionSpeed;
    return n.isEven ? moved : motionSpeed - moved;
  },
  (duration) => [
    for (var reversal = 1.0; reversal + settleTime <= duration; reversal += 1)
      (
        start: reversal,
        end: reversal + settleTime,
        east: _eastIfEven(reversal.toInt() - 1),
      ),
  ],
);

/// 1 if [n] is even, -1 otherwise: the direction of the motions' n-th leg.
double _eastIfEven(int n) => n.isEven ? 1 : -1;

/// The frames of [frames] in the window of [change].
Iterable<FrameError> _inWindow(List<FrameError> frames, MotionChange change) =>
    frames.where((f) => f.time >= change.start && f.time <= change.end);

/// The overshoot of each change in [changes] that has frames in its window:
/// the largest drawn error over the frames whose time lies in the window.
List<double> overshoots(List<FrameError> frames, List<MotionChange> changes) =>
    [
      for (final change in changes)
        if (_inWindow(frames, change) case final w when w.isNotEmpty)
          w.map((f) => f.error).reduce(math.max),
    ];

/// The overshoot ahead of each change in [changes] that has frames in its
/// window: the largest distance at the viewport center by which the map is
/// ahead of the overlays in the direction of motion before the change, or 0
/// if it isn't ahead in any frame of the window.
List<double> overshootsAhead(
  List<FrameError> frames,
  List<MotionChange> changes,
) => [
  for (final change in changes)
    if (_inWindow(frames, change) case final w when w.isNotEmpty)
      // A map ahead of the overlays draws their center coordinate on the
      // side the camera moves away from.
      w.map((f) => math.max(0.0, -f.centerDx * change.east)).reduce(math.max),
];
