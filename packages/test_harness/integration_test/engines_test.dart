// Integration tests for the map-texture spec requirement "Multiple Flutter
// engines" (design D159 of the multiple-flutter-engines change). The test
// harness's native code starts the second engine; see lib/second_engine.dart.
//
//   cd packages/test_harness && flutter test integration_test/engines_test.dart -d <iOS or Android id>
//   cd packages/test_harness && flutter drive -d macos \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/engines_test.dart
//
// On macOS the second engine's entry point has to be in the root library,
// which under `flutter test` is a generated file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mapigrade/src/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:test_harness/second_engine.dart' as second_engine;

/// The entry point of the second engine on macOS, which looks it up in the
/// root library.
@pragma('vm:entry-point')
Future<void> secondEngineMain() => second_engine.secondEngineMain();

String colorStyle(String color) => jsonEncode({
  'version': 8,
  'sources': {},
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': color},
    },
  ],
});

const red = [255, 0, 0];
const blue = [0, 0, 255];

/// Waits for the first event on [stream] that satisfies [test].
Future<T> waitFor<T>(
  Stream<Object> stream,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 20),
}) {
  return stream
      .where((e) => e is T && test(e as T))
      .cast<T>()
      .first
      .timeout(timeout);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final controllers = <MapTextureController>[];
  late second_engine.SecondEngine secondEngine;

  setUp(() => secondEngine = second_engine.SecondEngine());

  tearDown(() async {
    await secondEngine.destroy();
    secondEngine.close();
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  final boundaryKey = GlobalKey();

  /// Shows [maps] side by side, each in a 200x150 view, in a RepaintBoundary.
  Future<void> show(WidgetTester tester, List<MapTextureController> maps) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final map in maps)
                    SizedBox(
                      width: 200,
                      height: 150,
                      child: MapTextureView(controller: map),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  /// The color of the center of the view of the map at [index] in the
  /// RepaintBoundary.
  Future<List<int>> centerColor(int index) async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final x = (index * 200 + 100) * image.width ~/ boundary.size.width;
    final y = image.height ~/ 2;
    final offset = (y * image.width + x) * 4;
    return [for (var c = 0; c < 3; c++) bytes.getUint8(offset + c)];
  }

  /// Creates a map with a background of [color] and waits for its style.
  Future<MapTextureController> createMap(
    WidgetTester tester,
    String color,
  ) async {
    final controller = await MapTextureController.create(
      pixelRatio: tester.view.devicePixelRatio,
    );
    controllers.add(controller);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle(color));
    await loaded;
    return controller;
  }

  /// Waits until [map] reports a displayed frame, and then for a few frames
  /// of Flutter, so that a capture shows it.
  Future<void> waitForDisplayedFrame(MapTextureController map) async {
    await waitFor<FrameCamera>(map.frames, (_) => true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  testWidgets('a second engine starts after the first engine shows a map', (
    tester,
  ) async {
    final first = await createMap(tester, '#ff0000');
    await show(tester, [first]);
    await waitForDisplayedFrame(first);

    final report = await secondEngine.start();
    expect(report['event'], 'started');

    final second = await createMap(tester, '#0000ff');
    final displayed = waitForDisplayedFrame(second);
    await show(tester, [first, second]);
    await displayed;
    expect(await centerColor(0), red);
    expect(await centerColor(1), blue);
  });

  testWidgets('a second engine is destroyed', (tester) async {
    final first = await createMap(tester, '#ff0000');
    await show(tester, [first]);
    await waitForDisplayedFrame(first);

    expect((await secondEngine.start())['event'], 'started');
    await secondEngine.destroy();

    final second = await createMap(tester, '#0000ff');
    final displayed = waitForDisplayedFrame(second);
    await show(tester, [first, second]);
    await displayed;
    expect(await centerColor(0), red);
    expect(await centerColor(1), blue);

    // The map that existed before keeps rendering.
    final frame = waitFor<FrameCamera>(
      first.frames,
      (f) => (f.camera.zoom - 3).abs() < 1e-6,
    );
    first.setCamera(const MapCamera(latitude: 0, longitude: 0, zoom: 3));
    await frame;
  });

  testWidgets('maps of a destroyed engine are released', (tester) async {
    if (Platform.isMacOS) {
      markTestSkipped('macOS has no detach callback (design D158)');
      return;
    }
    final first = await createMap(tester, '#ff0000');
    await show(tester, [first]);
    await waitForDisplayedFrame(first);

    // A first start and destroy starts the process-wide threads that stay,
    // such as those of the Dart VM.
    expect((await secondEngine.start())['event'], 'started');
    await secondEngine.destroy();
    await Future<void>.delayed(const Duration(seconds: 1));
    final before = processThreadCount();

    final report = await secondEngine.start(createMap: true);
    expect(report['event'], 'mapCreated', reason: '$report');
    final during = processThreadCount();
    await secondEngine.destroy();
    await Future<void>.delayed(const Duration(seconds: 2));
    final after = processThreadCount();
    debugPrint(
      'ENGINES threads: before $before, with the second engine '
      '$during, after it was destroyed $after',
    );
    expect(after, lessThanOrEqualTo(before));

    // The maps of the first engine keep rendering.
    final frame = waitFor<FrameCamera>(
      first.frames,
      (f) => (f.camera.zoom - 3).abs() < 1e-6,
    );
    first.setCamera(const MapCamera(latitude: 0, longitude: 0, zoom: 3));
    await frame;
    expect(await centerColor(0), red);
  });
}
