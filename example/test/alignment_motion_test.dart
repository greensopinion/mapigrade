// Unit tests for the stop, fling and reversal motions and the overshoot
// windows (design D35 of the camera-prediction change).
//
//   cd example && flutter test test/alignment_motion_test.dart
import 'package:flutter_mapigrade_example/alignment_motion.dart';
import 'package:flutter_test/flutter_test.dart';

/// The speed of [motion] at [t] from a central difference, in px/s.
double speedAt(Motion motion, double t) =>
    (motion.east(t + 1e-6) - motion.east(t - 1e-6)) / 2e-6;

void main() {
  group('fling', () {
    for (final distance in [1000.0, 402.0]) {
      test('follows flutter_map\'s spring over $distance px', () {
        final fling = Fling(distance);
        // The controller starts at 1,000 / 1,000 per second, so the camera
        // starts at the shorter side per second.
        expect(fling.speed(0), closeTo(distance, 1e-9));
        expect(fling.offset(0), 0);
        // It stops when the value reaches 1, after the shorter side.
        expect(fling.duration, closeTo(1.447, 0.001));
        expect(fling.offset(fling.duration), distance);
        expect(fling.offset(fling.duration + 1), distance);
        expect(fling.speed(fling.duration + 0.01), 0);
        // Just before the stop it is still moving, at 0.032 x the shorter
        // side per second.
        expect(
          fling.speed(fling.duration - 1e-6) / distance,
          closeTo(0.032, 0.001),
        );
        // The spring pulls towards 1.01 from 0, so the speed first rises to
        // 3.08 x the shorter side per second after 13.6 ms, then decreases
        // monotonically.
        expect(fling.speed(0.0136) / distance, closeTo(3.079, 0.001));
        expect(fling.speed(0.0126), lessThan(fling.speed(0.0136)));
        var last = double.infinity;
        for (var t = 0.0146; t < fling.duration; t += 0.01) {
          final v = fling.speed(t);
          expect(v, lessThan(last));
          expect(v, greaterThan(0));
          last = v;
        }
        // The remaining distance falls below 0.5 px at `settled`.
        expect(distance - fling.offset(fling.settled), lessThan(0.5));
        expect(
          distance - fling.offset(fling.settled - 0.001),
          greaterThanOrEqualTo(0.5),
        );
      });
    }

    test('the motion pans for 1 s, flings and rests in a 3 s cycle', () {
      final fling = Fling(1000);
      final motion = flingMotion(fling);
      expect(motion.east(0), 0);
      expect(speedAt(motion, 0.5), closeTo(1000, 1e-3));
      expect(motion.east(1), closeTo(1000, 1e-9));
      // The fling starts at the same speed at 1600x1000.
      expect(speedAt(motion, 1.00001), closeTo(1000, 10));
      expect(motion.east(1 + fling.duration), closeTo(2000, 1e-9));
      expect(motion.east(2.9), closeTo(2000, 1e-9));
      // The next cycle goes back west.
      expect(speedAt(motion, 3.5), closeTo(-1000, 1e-3));
      expect(motion.east(6), closeTo(0, 1e-9));
    });

    test('each window starts at the fling and ends 0.5 s after it settles', () {
      final fling = Fling(1000);
      final changes = flingMotion(fling).changes(30);
      expect(changes, hasLength(10));
      for (final (i, c) in changes.indexed) {
        expect(c.start, closeTo(1 + 3.0 * i, 1e-9));
        expect(c.end, closeTo(c.start + fling.settled + 0.5, 1e-9));
        // The window ends before the next pan starts.
        expect(c.end, lessThan(3.0 * (i + 1)));
      }
      expect(flingMotion(Fling(402)).changes(30), hasLength(10));
    });
  });

  group('stop', () {
    test('pans for 1 s and rests for 1 s, east and west in turn', () {
      final motion = stopMotion();
      expect(speedAt(motion, 0.5), closeTo(1000, 1e-3));
      expect(motion.east(1), closeTo(1000, 1e-9));
      expect(speedAt(motion, 1.5), 0);
      expect(speedAt(motion, 2.5), closeTo(-1000, 1e-3));
      expect(motion.east(3.5), closeTo(0, 1e-9));
    });

    test('each window starts at the stop and ends 0.5 s later', () {
      final changes = stopMotion().changes(20);
      expect(changes, hasLength(10));
      for (final (i, c) in changes.indexed) {
        expect(c.start, 1 + 2.0 * i);
        expect(c.end, c.start + 0.5);
      }
    });
  });

  group('reverse', () {
    test('reverses the direction every 1 s', () {
      final motion = reverseMotion();
      expect(speedAt(motion, 0.5), closeTo(1000, 1e-3));
      expect(motion.east(1), closeTo(1000, 1e-9));
      expect(speedAt(motion, 1.5), closeTo(-1000, 1e-3));
      expect(motion.east(2), closeTo(0, 1e-9));
      expect(speedAt(motion, 2.5), closeTo(1000, 1e-3));
    });

    test('each window starts at the reversal and ends 0.5 s later', () {
      final changes = reverseMotion().changes(20);
      expect(changes, hasLength(19));
      for (final (i, c) in changes.indexed) {
        expect(c.start, 1.0 + i);
        expect(c.end, c.start + 0.5);
      }
    });
  });

  test('the overshoot is the largest error in each window', () {
    final frames = [
      (time: 0.9, error: 50.0, centerDx: 0.0),
      (time: 1.0, error: 3.0, centerDx: 0.0),
      (time: 1.2, error: 7.0, centerDx: 0.0),
      (time: 1.5, error: 4.0, centerDx: 0.0),
      (time: 1.6, error: 40.0, centerDx: 0.0),
      (time: 3.1, error: 2.0, centerDx: 0.0),
    ];
    expect(
      overshoots(frames, [
        (start: 1.0, end: 1.5, east: 1),
        (start: 3.0, end: 3.5, east: 1),
        (start: 5.0, end: 5.5, east: 1),
      ]),
      [7.0, 2.0],
    );
  });

  test('the overshoot ahead counts only the map ahead of the overlays', () {
    // Moving east, a map behind the overlays draws their center coordinate
    // east of the center (positive dx), a map ahead draws it west.
    final frames = [
      (time: 1.0, error: 9.0, centerDx: 9.0),
      (time: 1.1, error: 4.0, centerDx: -4.0),
      (time: 1.2, error: 2.0, centerDx: -2.0),
      (time: 3.0, error: 8.0, centerDx: 8.0),
      (time: 3.1, error: 1.0, centerDx: 1.0),
      (time: 5.0, error: 6.0, centerDx: 6.0),
    ];
    expect(
      overshootsAhead(frames, [
        (start: 1.0, end: 1.5, east: 1),
        // Behind in every frame: 0.
        (start: 3.0, end: 3.5, east: 1),
        // Moving west, positive dx is ahead.
        (start: 5.0, end: 5.5, east: -1),
      ]),
      [4.0, 0.0, 6.0],
    );
  });

  test('each window has the direction of motion before the change', () {
    for (final (motion, duration) in [
      (stopMotion(), 20.0),
      (flingMotion(Fling(1000)), 30.0),
      (reverseMotion(), 20.0),
    ]) {
      for (final c in motion.changes(duration)) {
        expect(
          speedAt(motion, c.start - 0.01).sign,
          c.east,
          reason: 'change at ${c.start}',
        );
      }
    }
  });
}
