// Unit tests for the camera prediction (designs D32 and D33 of the
// camera-prediction change).
import 'dart:ui';

import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/src/layer/camera_prediction.dart';
import 'package:flutter_mapigrade/src/layer/camera_projection.dart';
import 'package:flutter_test/flutter_test.dart';

const viewport = Size(400, 300);

/// One refresh interval at 60 Hz.
const interval = Duration(microseconds: 16667);
const intervalSeconds = 16667 / 1e6;

ViewCamera view(
  double latitude,
  double longitude,
  double zoom, {
  double bearing = 0,
}) => ViewCamera(
  MapCamera(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    bearing: bearing,
  ),
  viewport,
);

Matcher closeCamera(ViewCamera expected, [double tolerance = 1e-9]) =>
    isA<ViewCamera>()
        .having(
          (v) => v.camera.latitude,
          'latitude',
          closeTo(expected.camera.latitude, tolerance),
        )
        .having(
          (v) => v.camera.longitude,
          'longitude',
          closeTo(expected.camera.longitude, tolerance),
        )
        .having(
          (v) => v.camera.zoom,
          'zoom',
          closeTo(expected.camera.zoom, tolerance),
        )
        .having(
          (v) => v.camera.bearing,
          'bearing',
          closeTo(expected.camera.bearing, tolerance),
        )
        .having((v) => v.viewport, 'viewport', expected.viewport);

/// Feeds [cameras] to a new predictor, one per refresh interval, and returns
/// the prediction for the last one with a lead of [lead] intervals.
ViewCamera predictLast(List<ViewCamera> cameras, {double lead = 2}) {
  final predictor = CameraPredictor();
  late ViewCamera predicted;
  for (var i = 0; i < cameras.length; i++) {
    predicted = predictor.predict(
      cameras[i],
      interval * (i + 1),
      lead * intervalSeconds,
    );
  }
  return predicted;
}

void main() {
  test('a steady pan is predicted ahead by velocity x lead / refresh rate', () {
    // 0.01 degrees of longitude per interval at the equator, where latitude
    // stays 0.
    final cameras = [for (var i = 0; i < 5; i++) view(0, 10 + 0.01 * i, 12)];
    for (final lead in [1.0, 2.0, 3.0]) {
      expect(
        predictLast(cameras, lead: lead),
        closeCamera(view(0, 10.04 + 0.01 * lead, 12)),
      );
    }
  });

  test('a steady pan in latitude is predicted ahead in Mercator y', () {
    final ys = [for (var i = 0; i < 4; i++) 0.3 + 0.0001 * i];
    final cameras = [
      for (final y in ys) view(latLonOf(Offset(0.6, y)).$1, 36, 10),
    ];
    final (lat, _) = latLonOf(Offset(0.6, ys.last + 0.0002));
    expect(predictLast(cameras), closeCamera(view(lat, 36, 10)));
  });

  test('the velocity uses the camera of two builds earlier', () {
    // Uneven steps: 0.01, then 0.03. Over two builds the velocity is
    // 0.02 per interval.
    final cameras = [view(0, 10, 12), view(0, 10.01, 12), view(0, 10.04, 12)];
    expect(predictLast(cameras, lead: 1), closeCamera(view(0, 10.06, 12)));
  });

  test('with only one earlier build the velocity uses that one', () {
    final cameras = [view(0, 10, 12), view(0, 10.01, 12)];
    expect(predictLast(cameras), closeCamera(view(0, 10.03, 12)));
  });

  test('a camera equal to the previous build gives the converted camera', () {
    final cameras = [
      view(0, 10, 12),
      view(0, 10.01, 12),
      view(0, 10.02, 12),
      view(0, 10.02, 12),
    ];
    expect(predictLast(cameras), view(0, 10.02, 12));
  });

  test('the first build gives the converted camera', () {
    expect(predictLast([view(1, 2, 3, bearing: 4)]), view(1, 2, 3, bearing: 4));
  });

  test('records older than 50 ms are dropped', () {
    final predictor = CameraPredictor();
    const lead = 2 * intervalSeconds;
    predictor.predict(view(0, 10, 12), Duration.zero, lead);
    // 40 ms later: the first record is recent enough.
    expect(
      predictor.predict(
        view(0, 10.04, 12),
        const Duration(milliseconds: 40),
        lead,
      ),
      closeCamera(view(0, 10.04 + 0.04 / 40 * 1000 * lead, 12)),
    );
    // 30 ms later: the first record is 70 ms old and dropped, so the
    // velocity uses the second one.
    expect(
      predictor.predict(
        view(0, 10.07, 12),
        const Duration(milliseconds: 70),
        lead,
      ),
      closeCamera(view(0, 10.07 + 0.03 / 30 * 1000 * lead, 12)),
    );
    // 100 ms later: all earlier records are dropped.
    expect(
      predictor.predict(
        view(0, 10.2, 12),
        const Duration(milliseconds: 170),
        lead,
      ),
      view(0, 10.2, 12),
    );
  });

  test('a second build in the same frame replaces the first', () {
    final predictor = CameraPredictor();
    const lead = 2 * intervalSeconds;
    predictor.predict(view(0, 10, 12), interval, lead);
    predictor.predict(view(0, 10.01, 12), interval * 2, lead);
    predictor.predict(view(0, 10.02, 12), interval * 3, lead);
    // Rebuilt in the same frame with the same camera: still moving.
    expect(
      predictor.predict(view(0, 10.02, 12), interval * 3, lead),
      closeCamera(view(0, 10.04, 12)),
    );
  });

  test(
    'a pan across the antimeridian uses the shorter longitude difference',
    () {
      final cameras = [
        view(0, 179.98, 12),
        view(0, 179.99, 12),
        view(0, -180, 12),
      ];
      expect(predictLast(cameras), closeCamera(view(0, -179.98, 12)));
      final westwards = [
        view(0, -179.98, 12),
        view(0, -179.99, 12),
        view(0, -180, 12),
      ];
      expect(predictLast(westwards), closeCamera(view(0, 179.98, 12)));
    },
  );

  test('a rotation across 0/360 degrees uses the shorter angle', () {
    final cameras = [
      view(0, 10, 12, bearing: 358),
      view(0, 10, 12, bearing: 359),
      view(0, 10, 12, bearing: 0),
    ];
    expect(predictLast(cameras), closeCamera(view(0, 10, 12, bearing: 2)));
    final back = [
      view(0, 10, 12, bearing: 1),
      view(0, 10, 12, bearing: 0),
      view(0, 10, 12, bearing: 359),
    ];
    expect(predictLast(back), closeCamera(view(0, 10, 12, bearing: 357)));
  });

  test('zoom is extrapolated linearly', () {
    final cameras = [view(0, 10, 12), view(0, 10, 12.1), view(0, 10, 12.2)];
    expect(predictLast(cameras, lead: 3), closeCamera(view(0, 10, 12.5)));
  });

  test('the predicted latitude is clamped to the Mercator limit', () {
    final cameras = [view(84, 10, 2), view(85, 10, 2)];
    final predicted = predictLast(cameras, lead: 100);
    expect(predicted.camera.latitude, maxMercatorLatitude);
    final south = predictLast([view(-84, 10, 2), view(-85, 10, 2)], lead: 100);
    expect(south.camera.latitude, -maxMercatorLatitude);
  });

  test('the predicted longitude is normalized to [-180, 180)', () {
    final predicted = predictLast([view(0, 170, 2), view(0, 175, 2)], lead: 3);
    expect(predicted.camera.longitude, closeTo(-170, 1e-9));
    final west = predictLast([view(0, -170, 2), view(0, -175, 2)], lead: 3);
    expect(west.camera.longitude, closeTo(170, 1e-9));
    expect(latLonOf(const Offset(1, 0.5)).$2, -180);
    expect(latLonOf(const Offset(1 - 1e-17, 0.5)).$2, lessThan(180));
  });

  test('latLonOf inverts mercator', () {
    for (final (lat, lon) in [(0.0, 0.0), (51.5, -0.1), (-33.9, 151.2)]) {
      final (lat2, lon2) = latLonOf(mercator(lat, lon));
      expect(lat2, closeTo(lat, 1e-9));
      expect(lon2, closeTo(lon, 1e-9));
    }
  });
}
