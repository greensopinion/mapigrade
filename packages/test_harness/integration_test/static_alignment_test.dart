// Static alignment test (map-layer spec "Alignment at rest", design D27).
//
//   cd packages/test_harness && flutter test integration_test/static_alignment_test.dart -d macos
//
// The style draws a green circle at a coordinate, and a flutter_map
// CircleMarker draws a blue circle at the same coordinate. With the camera at
// rest, the test captures the map twice, without and with the overlay, and
// compares the centroids of the two colors. Each case runs with the overlay
// placed after the layer and as a child of the layer (task 5.2 of the
// layer-children-alignment change).
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_mapigrade/src/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

/// Captures are taken at this many image pixels per logical pixel.
const capturePixelRatio = 2.0;
const radius = 12.0;

String styleWithPoint(LatLng point) => jsonEncode({
  'version': 8,
  'sources': {
    'point': {
      'type': 'geojson',
      'data': {
        'type': 'Feature',
        'properties': {},
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude],
        },
      },
    },
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#ffffff'},
    },
    {
      'id': 'circle',
      'type': 'circle',
      'source': 'point',
      'paint': {
        'circle-radius': radius,
        'circle-color': '#00ff00',
        'circle-pitch-alignment': 'viewport',
      },
    },
  ],
});

class AlignmentCase {
  const AlignmentCase(
    this.name,
    this.center,
    this.zoom, {
    this.rotation = 0,
    this.size = const Size(400, 300),
    this.resizeTo,
    this.pointAt = const Offset(300, 100),
    this.point,
  });

  final String name;
  final LatLng center;
  final double zoom;
  final double rotation;
  final Size size;

  /// If set, the map is shown at [size] first and then resized to this size.
  final Size? resizeTo;

  /// The screen position of the test coordinate under the camera, in the
  /// final viewport.
  final Offset pointAt;

  /// The test coordinate, if given instead of [pointAt].
  final LatLng? point;

  Size get finalSize => resizeTo ?? size;
}

const cases = [
  AlignmentCase('integer zoom', LatLng(51.5, -0.12), 14),
  AlignmentCase('fractional zoom', LatLng(51.5, -0.12), 13.37),
  AlignmentCase('rotation 30 degrees', LatLng(48.85, 2.35), 12.5, rotation: 30),
  AlignmentCase('latitude 80 degrees', LatLng(80, 15), 7.25),
  // The center is west of the antimeridian, the point 0.7 degrees east of
  // the center, across the antimeridian. Given directly, because
  // screenOffsetToLatLng clamps longitudes to 180.
  AlignmentCase(
    'within 1 degree of the antimeridian',
    LatLng(-17, 179.6),
    8,
    point: LatLng(-16.9, -179.7),
  ),
  AlignmentCase(
    'after a resize',
    LatLng(40.7, -74),
    11.5,
    rotation: -20,
    // Both sizes fit an iPhone screen (402 logical pixels wide).
    size: Size(300, 240),
    resizeTo: Size(380, 320),
    pointAt: Offset(290, 80),
  ),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // The default layer (prediction, lead 1). At rest the predicted camera is
  // the converted camera, so the layer with no alignment draws the same frame
  // (design D50 of the remove-camera-transform change).
  for (final children in [false, true]) {
    for (final c in cases) {
      final variant = children ? ' with children' : '';
      testWidgets('alignment at rest$variant: ${c.name}', (tester) async {
        final camera = fm.MapCamera(
          crs: const fm.Epsg3857(),
          center: c.center,
          zoom: c.zoom,
          rotation: c.rotation,
          nonRotatedSize: c.finalSize,
        );
        final point = c.point ?? camera.screenOffsetToLatLng(c.pointAt);
        final style = styleWithPoint(point);

        final boundaryKey = GlobalKey();
        MapTextureController? controller;
        Widget app(Size size, {required bool overlay}) {
          final circles = fm.CircleLayer(
            circles: [
              fm.CircleMarker(
                point: point,
                radius: radius,
                color: const Color(0xff0000ff),
              ),
            ],
          );
          return MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox.fromSize(
                  size: size,
                  child: fm.FlutterMap(
                    options: fm.MapOptions(
                      initialCenter: c.center,
                      initialZoom: c.zoom,
                      initialRotation: c.rotation,
                    ),
                    children: [
                      MapTextureLayer(
                        styleJson: style,
                        onController: (x) => controller = x,
                        children: [if (overlay && children) circles],
                      ),
                      if (overlay && !children) circles,
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(app(c.size, overlay: false));
        final idle = controller!.events
            .firstWhere((e) => e is MapIdle)
            .timeout(const Duration(seconds: 20));
        if (c.resizeTo != null) {
          await controller!.frames.first.timeout(const Duration(seconds: 20));
          await tester.pumpWidget(app(c.finalSize, overlay: false));
        }
        await idle;
        await _waitForDisplayedCamera(tester, controller!, camera, c.finalSize);

        final displayed = controller!.displayedFrame;
        final green = await _centroid(boundaryKey, _isGreen);
        // Diagnostics for misalignment after a resize on the x86_64 emulator:
        // a second capture after a delay shows whether the map was still
        // changing at the first capture.
        await Future<void>.delayed(const Duration(seconds: 2));
        await tester.pump();
        final greenLater = await _centroid(boundaryKey, _isGreen);
        debugPrint(
          'CAPTURE$variant ${c.name}: displayed $displayed at the capture, '
          '${controller!.displayedFrame} 2 s later; style $green, '
          '2 s later $greenLater',
        );
        await tester.pumpWidget(app(c.finalSize, overlay: true));
        await tester.pump();
        final blue = await _centroid(boundaryKey, _isBlue);

        expect(green, isNotNull, reason: 'no style circle in the capture');
        expect(blue, isNotNull, reason: 'no overlay circle in the capture');
        final distance = (green! - blue!).distance;
        debugPrint(
          'ALIGNMENT$variant ${c.name}: style $green, overlay $blue, '
          'distance ${distance.toStringAsFixed(3)} logical px',
        );
        expect(distance, lessThanOrEqualTo(1.0));
      });
    }
  }
}

/// Waits until Flutter displays a map frame with the converted [camera] and
/// [size], and the layer has rebuilt with it.
Future<void> _waitForDisplayedCamera(
  WidgetTester tester,
  MapTextureController controller,
  fm.MapCamera camera,
  Size size,
) async {
  bool matches(FrameCamera? f) =>
      f != null &&
      (f.camera.latitude - camera.center.latitude).abs() < 1e-9 &&
      (f.camera.longitude - camera.center.longitude).abs() < 1e-9 &&
      (f.camera.zoom - (camera.zoom - 1)).abs() < 1e-9 &&
      (f.camera.bearing + camera.rotation).abs() < 1e-6 &&
      (f.physicalSize / f.scaleFactor - size as Offset).distance < 0.5;
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!matches(controller.displayedFrame)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the camera was never displayed; last ${controller.displayedFrame}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  // The style has no tiles; let the last frames after idle show, and the
  // layer rebuild with the displayed frame.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await tester.pump();
}

bool _isGreen(int r, int g, int b) => g > 200 && r < 80 && b < 80;
bool _isBlue(int r, int g, int b) => b > 200 && r < 80 && g < 80;

/// The centroid in logical pixels of the pixels that satisfy [test], or null
/// if there are none.
Future<Offset?> _centroid(
  GlobalKey key,
  bool Function(int r, int g, int b) test,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: capturePixelRatio);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var sx = 0.0, sy = 0.0, n = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final o = (y * image.width + x) * 4;
      if (test(
        bytes.getUint8(o),
        bytes.getUint8(o + 1),
        bytes.getUint8(o + 2),
      )) {
        sx += x + 0.5;
        sy += y + 0.5;
        n++;
      }
    }
  }
  if (n == 0) return null;
  return Offset(sx / n, sy / n) / capturePixelRatio;
}
