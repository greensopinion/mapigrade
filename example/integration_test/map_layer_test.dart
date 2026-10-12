// Integration tests for the flutter_map layer (map-layer spec, design D21).
//
//   cd example && flutter test integration_test/map_layer_test.dart -d macos
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

final redStyle = jsonEncode({
  'version': 8,
  'sources': {},
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#ff0000'},
    },
  ],
});

const markerColor = Color(0xff0000ff);
const center = LatLng(51.5, -0.12);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  /// A 400x300 FlutterMap with the layer, if [withLayer], and a 40x40 marker
  /// at the center.
  Widget mapApp(
    GlobalKey boundaryKey, {
    required bool withLayer,
    void Function(MapTextureController)? onController,
  }) => MaterialApp(
    home: Center(
      child: RepaintBoundary(
        key: boundaryKey,
        child: SizedBox(
          width: 400,
          height: 300,
          child: FlutterMap(
            options: const MapOptions(initialCenter: center, initialZoom: 12),
            children: [
              if (withLayer)
                MapLibreTextureLayer(
                  styleJson: redStyle,
                  onController: onController,
                ),
              const MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 40,
                    height: 40,
                    child: ColoredBox(color: markerColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<List<int> Function(double x, double y)> capture(GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return (x, y) {
      final offset = (y.round() * image.width + x.round()) * 4;
      return [for (var c = 0; c < 3; c++) bytes.getUint8(offset + c)];
    };
  }

  testWidgets('the layer fills the FlutterMap below the markers', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    MapTextureController? controller;
    await tester.pumpWidget(
      mapApp(boundaryKey, withLayer: true, onController: (c) => controller = c),
    );
    expect(
      find.descendant(
        of: find.byType(FlutterMap),
        matching: find.byType(MapLibreTextureLayer),
      ),
      findsOneWidget,
    );
    await controller!.frames.first.timeout(const Duration(seconds: 20));
    // Let Flutter show the frame and the layer rebuild with it.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();

    final pixel = await capture(boundaryKey);
    // The map fills the viewport up to its corners.
    for (final (x, y) in const [
      (2.0, 2.0),
      (397.0, 2.0),
      (2.0, 297.0),
      (397.0, 297.0),
    ]) {
      expect(pixel(x, y), [255, 0, 0], reason: 'map at ($x, $y)');
    }
    // The marker after the layer is drawn above it.
    expect(pixel(200, 150), [0, 0, 255]);
  });

  testWidgets('a camera jump larger than the viewport shows the new camera',
      (tester) async {
    final mapController = MapController();
    MapTextureController? controller;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: FlutterMap(
            mapController: mapController,
            options: const MapOptions(initialCenter: center, initialZoom: 12),
            children: [
              MapLibreTextureLayer(
                  styleJson: redStyle, onController: (c) => controller = c),
            ],
          ),
        ),
      ),
    ));
    await controller!.frames.first.timeout(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Two viewport widths east at flutter_map zoom 12.
    final degreesPerPx = 360 / (256 * (1 << 12));
    final target =
        LatLng(center.latitude, center.longitude + 800 * degreesPerPx);
    mapController.move(target, 12);
    final shown = await controller!.frames
        .firstWhere(
            (f) => (f.camera.longitude - target.longitude).abs() < 1e-9)
        .timeout(const Duration(seconds: 5),
            onTimeout: () => fail('no frame with the new camera was '
                'displayed; last ${controller!.displayedFrame}'));
    expect(shown.camera.longitude, closeTo(target.longitude, 1e-9));
  });

  /// A 400x300 FlutterMap at [center] with only the layer, with [alignment]
  /// or, if null, the layer's default.
  Widget layerApp(
    MapController mapController, {
    CameraAlignment? alignment,
    required void Function(MapTextureController) onController,
  }) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 400,
        height: 300,
        child: FlutterMap(
          mapController: mapController,
          options: const MapOptions(initialCenter: center, initialZoom: 12),
          children: [
            if (alignment == null)
              MapLibreTextureLayer(
                styleJson: redStyle,
                onController: onController,
              )
            else
              MapLibreTextureLayer(
                styleJson: redStyle,
                alignment: alignment,
                onController: onController,
              ),
          ],
        ),
      ),
    ),
  );

  final transformInLayer = find.descendant(
    of: find.byType(MapLibreTextureLayer),
    matching: find.byType(Transform),
  );

  for (final (name, alignment) in const [
    ('the default layer (prediction, lead 1)', null),
    ('the layer with no alignment', CameraAlignment.none),
    ('the layer with prediction, lead 2', CameraAlignment.prediction(lead: 2)),
  ]) {
    testWidgets('$name has no Transform while the camera moves', (
      tester,
    ) async {
      final mapController = MapController();
      MapTextureController? controller;
      await tester.pumpWidget(
        layerApp(
          mapController,
          alignment: alignment,
          onController: (c) => controller = c,
        ),
      );
      await controller!.frames.first.timeout(const Duration(seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();

      // Each step builds the layer with a camera that no displayed frame has
      // yet, because the layer sets the camera during the build.
      for (var i = 1; i <= 10; i++) {
        mapController.move(
          LatLng(center.latitude, center.longitude + 0.002 * i),
          12,
        );
        await tester.pump();
        expect(controller!.displayedFrame, isNotNull);
        expect(
          transformInLayer,
          findsNothing,
          reason: 'step $i',
        );
      }
    });
  }

  testWidgets('with the default layer (prediction, lead 1), the map shows the '
      'converted camera after a camera move stops', (tester) async {
    final mapController = MapController();
    MapTextureController? controller;
    await tester.pumpWidget(
      layerApp(mapController, onController: (c) => controller = c),
    );
    await controller!.frames.first.timeout(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final displayed = <double>[];
    final subscription = controller!.frames.listen(
      (f) => displayed.add(f.camera.longitude),
    );
    final steps = [for (var i = 1; i <= 20; i++) center.longitude + 0.01 * i];
    for (final longitude in steps) {
      mapController.move(LatLng(center.latitude, longitude), 12);
      await tester.pump();
    }
    final last = LatLng(center.latitude, steps.last);
    final shown = await controller!.frames
        .firstWhere(
          (f) =>
              (f.camera.longitude - last.longitude).abs() < 1e-9 &&
              (f.camera.latitude - last.latitude).abs() < 1e-9,
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'no frame with the converted camera was '
            'displayed; last ${controller!.displayedFrame}',
          ),
        );
    await subscription.cancel();
    expect(shown.camera.zoom, closeTo(11, 1e-9));
    // During the move the map rendered predicted cameras, which lie between
    // or beyond the steps.
    expect(
      displayed.where(
        (lon) =>
            !steps.any((step) => (lon - step).abs() < 1e-9) &&
            lon > center.longitude + 1e-9,
      ),
      isNotEmpty,
      reason: 'displayed longitudes $displayed',
    );
  });

  testWidgets('removing the layer disposes its map', (tester) async {
    final boundaryKey = GlobalKey();
    MapTextureController? controller;
    await tester.pumpWidget(
      mapApp(boundaryKey, withLayer: true, onController: (c) => controller = c),
    );
    await controller!.frames.first.timeout(const Duration(seconds: 20));
    expect(controller!.isDisposed, isFalse);

    await tester.pumpWidget(mapApp(boundaryKey, withLayer: false));
    expect(controller!.isDisposed, isTrue);
  });

  testWidgets('50 layer insert/remove cycles keep threads and memory stable',
      (tester) async {
    final boundaryKey = GlobalKey();
    Future<void> cycle() async {
      MapTextureController? controller;
      await tester.pumpWidget(mapApp(boundaryKey,
          withLayer: true, onController: (c) => controller = c));
      await controller!.frames.first.timeout(const Duration(seconds: 20));
      await tester.pumpWidget(mapApp(boundaryKey, withLayer: false));
      expect(controller!.isDisposed, isTrue);
    }

    // The first cycle starts process-wide threads that stay, such as
    // MapLibre's shared worker threads.
    await cycle();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final threadsBefore = processThreadCount();
    final footprintBefore = memoryFootprintForTesting();
    final footprints = <int>[];
    for (var i = 0; i < 50; i++) {
      await cycle();
      footprints.add(memoryFootprintForTesting());
    }
    // Threads and memory settle within a few seconds after the last cycle;
    // a plain MapTextureView shows the same rise and settling without
    // flutter_map.
    await Future<void>.delayed(const Duration(seconds: 3));
    final threadsAfter = processThreadCount();
    final footprintAfter = memoryFootprintForTesting();
    String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
    debugPrint('LAYER_LIFECYCLE threads $threadsBefore -> $threadsAfter; '
        'footprint ${mib(footprintBefore)} MiB -> ${mib(footprintAfter)} MiB; '
        'after cycles 10/20/30/40/50: '
        '${[for (final i in [9, 19, 29, 39, 49]) mib(footprints[i])]}');
    expect(threadsAfter, lessThanOrEqualTo(threadsBefore));
    expect(footprintAfter - footprintBefore, lessThan(100 * 1024 * 1024));
  });
}
