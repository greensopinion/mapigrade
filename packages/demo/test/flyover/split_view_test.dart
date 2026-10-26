// The right-half clip and the seam (designs D196 and D197) of the demo-app
// spec, requirement "Split view".
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapigrade_demo/src/flyover/split_view.dart';

/// The height of the attribution button on touch platforms.
const _attributionHeight = 56.0;

/// Pumps the clip and the seam above a map stand-in that counts drags.
Future<List<int>> _pump(WidgetTester tester, Size viewport) async {
  tester.view
    ..physicalSize = viewport
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final drags = [0];
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => drags[0]++,
            child: const SizedBox.expand(),
          ),
          const RightHalf(child: SizedBox.expand()),
          const SplitSeam(),
        ],
      ),
    ),
  );
  return drags;
}

void main() {
  for (final viewport in const [Size(390, 844), Size(1280, 720)]) {
    final center = viewport.width / 2;

    group('${viewport.width} x ${viewport.height}', () {
      testWidgets('clips to the right half', (tester) async {
        await _pump(tester, viewport);
        final clip = tester.renderObject<RenderClipRect>(find.byType(ClipRect));
        expect(
          clip.clipper!.getClip(clip.size),
          Rect.fromLTRB(center, 0, viewport.width, viewport.height),
        );
      });

      testWidgets('centers the line on the seam', (tester) async {
        await _pump(tester, viewport);
        final line = tester.getRect(
          find.descendant(
            of: find.byType(SplitSeam),
            matching: find.byType(ColoredBox),
          ),
        );
        expect(line.center.dx, center);
        expect(line.width, 1);
        expect(line.top, 0);
        expect(line.bottom, viewport.height);
      });

      testWidgets('places the labels beside the line, above the attribution', (
        tester,
      ) async {
        await _pump(tester, viewport);
        final left = tester.getRect(find.text('Mapigrade'));
        final right = tester.getRect(find.text('Raster (OSM)'));
        expect(left.right, lessThan(center));
        expect(right.left, greaterThan(center));
        for (final label in [left, right]) {
          expect(
            label.bottom,
            lessThanOrEqualTo(viewport.height - _attributionHeight),
          );
        }
      });

      testWidgets('passes drags on the line and the labels to the map', (
        tester,
      ) async {
        final drags = await _pump(tester, viewport);
        for (final start in [
          Offset(center, viewport.height / 2),
          tester.getCenter(find.text('Mapigrade')),
          tester.getCenter(find.text('Raster (OSM)')),
        ]) {
          await tester.dragFrom(start, const Offset(40, 0));
        }
        expect(drags[0], 3);
      });
    });
  }
}
