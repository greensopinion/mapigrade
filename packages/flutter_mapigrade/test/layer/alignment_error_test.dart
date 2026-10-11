// Unit tests for the alignment error computation (design D26).
import 'dart:ui';

import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/src/layer/alignment_error.dart';
import 'package:flutter_mapigrade/src/layer/camera_transform.dart';
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
  test('with the transform the error is 0 when the shown frame is the used '
      'frame', () {
    for (final (used, target) in [
      (panned(-30), panned(0)),
      (panned(0, bearing: 10), panned(5, bearing: -20)),
      (panned(-12, size: const Size(380, 290)), panned(0)),
      (
        ViewCamera(const MapCamera(latitude: 60, longitude: 20, zoom: 9.2),
            const Size(400, 300)),
        ViewCamera(const MapCamera(latitude: 60.1, longitude: 20, zoom: 9.7),
            const Size(400, 300)),
      ),
    ]) {
      final error = alignmentError(target: target, used: used, shown: used);
      expect(error.withTransform, closeTo(0, 1e-6));
    }
  });

  test('a shown frame newer than the used frame gives the camera difference',
      () {
    // The overlays are at C; the transform was built for a frame 30 px behind
    // C, and Flutter shows a frame 10 px behind C. Without a transform the
    // shown frame is 10 px off. The transform shifts it by the 30 px it
    // expected, 20 px too far.
    final error = alignmentError(
        target: panned(0), used: panned(-30), shown: panned(-10));
    expect(error.withoutTransform, closeTo(10, 1e-6));
    expect(error.withTransform, closeTo(20, 1e-6));
  });

  test('without a used frame the layer draws no transform', () {
    final error =
        alignmentError(target: panned(0), used: null, shown: panned(-10));
    expect(error.withTransform, closeTo(10, 1e-6));
    expect(error.withoutTransform, closeTo(10, 1e-6));
  });

  test('a used frame that the transform would move out of view counts as '
      'drawn without the transform', () {
    // The transform would move the frame 500 px, beyond the 400 px wide
    // viewport, so the layer draws it in place.
    final error = alignmentError(
        target: panned(0), used: panned(-500), shown: panned(-500));
    expect(error.withTransform, closeTo(500, 1e-6));
    expect(error.withoutTransform, closeTo(500, 1e-6));
  });

  test('a rotation difference is largest at the corners', () {
    // 90 degrees about the center of a 400x300 viewport moves a corner by
    // sqrt(2) times its distance to the center, 250 px.
    final error = alignmentError(
        target: panned(0, bearing: 90), used: null, shown: panned(0));
    expect(error.withoutTransform, closeTo(250 * 1.4142135623730951, 1e-6));
  });

  test('worldPosition inverts screenPosition', () {
    final view = panned(7, bearing: 33);
    for (final q in const [Offset(0, 0), Offset(400, 300), Offset(123, 45)]) {
      expect(
          (screenPosition(view, worldPosition(view, q)) - q).distance,
          lessThan(1e-6));
    }
  });
}
