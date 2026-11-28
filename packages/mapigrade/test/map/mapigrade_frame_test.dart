import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'test_matrix.dart';

void main() {
  test('the center projects to the middle of the frame', () {
    final frame = testFrame(pitch: 45, bearing: 30);
    final p = frame.project(const LatLng(48.2, 16.37))!;
    expect(p.dx, closeTo(200, 1e-6));
    expect(p.dy, closeTo(300, 1e-6));
  });

  for (final pitch in [0.0, 45.0, 80.0]) {
    test('a coordinate round-trips within 0.5 pixels at pitch $pitch', () {
      final frame = testFrame(pitch: pitch, bearing: 20);
      for (final position in [
        const Offset(200, 300),
        const Offset(10, 590),
        const Offset(390, 400),
        const Offset(50, 320),
      ]) {
        final coordinate = frame.unproject(position);
        expect(coordinate, isNotNull, reason: '$position');
        final back = frame.project(coordinate!)!;
        expect((back - position).distance, lessThan(0.5), reason: '$position');
      }
    });
  }

  test('a scale of 512 * 2^zoom pixels per world at pitch 0', () {
    final frame = testFrame(center: const LatLng(0, 0), zoom: 2);
    // 90 degrees of longitude is a quarter of a 2048-pixel world.
    final p = frame.project(const LatLng(0, 90))!;
    expect(p.dx - 200, closeTo(512, 1e-6));
  });

  test('a coordinate behind the camera has no position', () {
    final frame = testFrame(pitch: 80);
    // At pitch 80 the camera is south of the center; far south of it is
    // behind the camera.
    expect(frame.project(const LatLng(40, 16.37)), isNull);
    expect(frame.project(const LatLng(48.21, 16.37)), isNotNull);
  });

  test('a position above the horizon has no coordinate', () {
    final frame = testFrame(pitch: 80);
    expect(frame.unproject(const Offset(200, 0)), isNull);
    expect(frame.unproject(const Offset(200, 599)), isNotNull);
  });

  test('the copy of the world nearest the center is chosen', () {
    final frame = testFrame(center: const LatLng(0, 179), zoom: 6);
    final east = frame.project(const LatLng(0, -179))!;
    final west = frame.project(const LatLng(0, 177))!;
    // -179 is 2 degrees east of the center, across the antimeridian.
    expect(east.dx - 200, closeTo(200 - west.dx, 1e-6));
    expect(east.dx, greaterThan(200));
    final back = frame.unproject(east)!;
    expect(back.longitude, closeTo(-179, 1e-9));
  });
}
