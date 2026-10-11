// Color check (task 4.3 of the iOS slice) without a screenshot: renders the
// color check screen (lib/color_check.dart) to an image with
// RepaintBoundary.toImage, which includes the map's texture layer, and
// compares the map's fill and background with the Flutter swatches of the
// same colors in that image. Not part of the integration test suite:
//
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/color_measurement.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map_maplibre_texture/testing.dart';
import 'package:flutter_map_maplibre_texture_example/color_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('map colors match Flutter swatches within 2/255',
      (tester) async {
    // EXPERIMENT: `--dart-define=ZERO_COPY=true` renders directly into the
    // display buffers.
    setZeroCopyForTesting(const bool.fromEnvironment('ZERO_COPY'));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(key: boundaryKey, child: const ColorCheck())));
    // The style has no tiles to load; a few seconds cover loading and the
    // first frames.
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();

    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width;
    final height = image.height;
    List<int> pixel(double fx, double fy) {
      final x = (width * fx).round();
      final y = (height * fy).round();
      final offset = (y * width + x) * 4;
      return [
        for (var c = 0; c < 3; c++) bytes.getUint8(offset + c),
      ];
    }

    // The map fills the screen above a 100-logical-pixel swatch strip; its
    // left half is the fill, its right half the background. toImage() uses
    // pixel ratio 1, so the image size is the logical size.
    final mapCenterY = (height - 100) / 2 / height;
    final stripY = (height - 50) / height;
    final samples = {
      'map fill': pixel(0.25, mapCenterY),
      'swatch fill': pixel(0.25, stripY),
      'map background': pixel(0.75, mapCenterY),
      'swatch background': pixel(0.75, stripY),
    };
    int maxDiff(List<int> a, List<int> b) => [
          for (var c = 0; c < 3; c++) (a[c] - b[c]).abs(),
        ].reduce((x, y) => x > y ? x : y);
    final fillDiff = maxDiff(samples['map fill']!, samples['swatch fill']!);
    final backgroundDiff =
        maxDiff(samples['map background']!, samples['swatch background']!);
    debugPrint('COLOR_RESULT ${image.width}x${image.height} $samples '
        'fill diff $fillDiff, background diff $backgroundDiff');
    expect(fillDiff, lessThanOrEqualTo(2));
    expect(backgroundDiff, lessThanOrEqualTo(2));
  });
}
