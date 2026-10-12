// Unit tests for the alignment error computation (design D26).
import 'dart:ui';

import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/src/layer/alignment_error.dart';
import 'package:flutter_mapigrade/src/layer/camera_projection.dart';
import 'package:flutter_test/flutter_test.dart';

const zoom = 14.0;

/// A camera at London panned [east] logical pixels east.
ViewCamera panned(double east,
        {double bearing = 0, Size size = const Size(400, 300)}) =>
    ViewCamera(
      MapCamera(
          latitude: 51.5,
          longitude: -0.12 + east / worldSize(zoom) * 360,
          zoom: zoom,
          bearing: bearing),
      size,
    );

void main() {
  test('the error is 0 when the shown frame has the overlays\' camera', () {
    for (final target in [
      panned(0),
      panned(5, bearing: -20),
      ViewCamera(const MapCamera(latitude: 60.1, longitude: 20, zoom: 9.7),
          const Size(400, 300)),
    ]) {
      final error = alignmentError(target: target, shown: target);
      expect(error.error, closeTo(0, 1e-6));
    }
  });

  test('a shown frame behind the overlays gives the camera difference', () {
    expect(alignmentError(target: panned(0), shown: panned(-10)).error,
        closeTo(10, 1e-6));
    expect(alignmentError(target: panned(0), shown: panned(-500)).error,
        closeTo(500, 1e-6));
  });

  test('a rotation difference is largest at the corners', () {
    // 90 degrees about the center of a 400x300 viewport moves a corner by
    // sqrt(2) times its distance to the center, 250 px.
    final error =
        alignmentError(target: panned(0, bearing: 90), shown: panned(0));
    expect(error.error, closeTo(250 * 1.4142135623730951, 1e-6));
  });

  test('worldPosition inverts screenPosition', () {
    final view = panned(7, bearing: 33);
    for (final q in const [Offset(0, 0), Offset(400, 300), Offset(123, 45)]) {
      expect(
          (screenPosition(view, worldPosition(view, q)) - q).distance,
          lessThan(1e-6));
    }
  });

  test('the center offset points where the map draws the center coordinate',
      () {
    // The shown frame is 10 px west of C, so it draws C's center coordinate
    // 10 px east of the center.
    final error = alignmentError(target: panned(0), shown: panned(-10));
    expect(error.center.dx, closeTo(10, 1e-6));
    expect(error.center.dy, closeTo(0, 1e-6));
  });
}
