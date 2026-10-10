// Integration tests for the map-texture spec scenarios.
//
//   cd example && flutter test integration_test -d macos
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map_maplibre_texture/flutter_map_maplibre_texture.dart';
import 'package:flutter_map_maplibre_texture_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const demoStyleUrl = 'https://demotiles.maplibre.org/style.json';
const unreachableStyleUrl = 'https://invalid.example.invalid/style.json';

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

/// Waits for the first event on [stream] that satisfies [test].
Future<T> waitFor<T>(Stream<Object> stream, bool Function(T) test,
    {Duration timeout = const Duration(seconds: 20)}) {
  return stream
      .where((e) => e is T && test(e as T))
      .cast<T>()
      .first
      .timeout(timeout);
}

bool near(double a, double b) => (a - b).abs() < 1e-6;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let the engine produce frames continuously, so Flutter takes map frames
  // from the texture without the test pumping.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final controllers = <MapTextureController>[];

  /// Creates a controller and shows it in a 400x300 view.
  Future<MapTextureController> showMap(WidgetTester tester) async {
    final controller = MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio);
    controllers.add(controller);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
            width: 400,
            height: 300,
            child: MapTextureView(controller: controller)),
      ),
    ));
    return controller;
  }

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  testWidgets('create and dispose', (tester) async {
    final controller = MapTextureController.create(pixelRatio: 2);
    expect(controller.textureId, greaterThanOrEqualTo(0));
    controller.dispose();
    expect(controller.isDisposed, isTrue);
  });

  testWidgets('style loads from URL and renders', (tester) async {
    final controller = await showMap(tester);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    final frame = waitFor<FrameCamera>(controller.frames, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;
    final displayed = await frame;
    expect(displayed.physicalSize.width,
        closeTo(400 * tester.view.devicePixelRatio, 1));
  });

  testWidgets('style fails to load from an unreachable URL', (tester) async {
    final controller = await showMap(tester);
    final failed = waitFor<LoadingFailed>(controller.events, (_) => true);
    controller.loadStyleUrl(unreachableStyleUrl);
    final event = await failed;
    expect(event.message, isNotEmpty);
    // The map keeps working after the failure.
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#00ff00'));
    await loaded;
  });

  testWidgets('style fails to load from invalid JSON', (tester) async {
    final controller = await showMap(tester);
    final failed = waitFor<LoadingFailed>(controller.events, (_) => true);
    controller.loadStyleJson('{"version": 8, "layers": [');
    final event = await failed;
    expect(event.message, isNotEmpty);
  });

  testWidgets('style is replaced', (tester) async {
    final controller = await showMap(tester);
    var loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#ff0000'));
    await loaded;
    await waitFor<FrameCamera>(controller.frames, (_) => true);

    loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;
    // A frame rendered after the second style loaded.
    final frame = await waitFor<FrameCamera>(controller.frames, (_) => true);
    expect(frame.frameId, greaterThan(1));
  });

  testWidgets('camera change shows up in the frame camera', (tester) async {
    final controller = await showMap(tester);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#3366cc'));
    await loaded;

    const camera =
        MapCamera(latitude: 48.8566, longitude: 2.3522, zoom: 11, bearing: 30);
    final frame = waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            near(f.camera.latitude, camera.latitude) &&
            near(f.camera.longitude, camera.longitude) &&
            near(f.camera.zoom, camera.zoom));
    controller.setCamera(camera);
    final displayed = await frame;
    // MapLibre reports bearing with the opposite sign convention.
    expect(displayed.camera.bearing.abs(), closeTo(30, 1e-6));
  });

  testWidgets('rapid camera updates do not build up a backlog',
      (tester) async {
    final controller = await showMap(tester);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;

    final sent = <double>[];
    final displayed = <FrameCamera>[];
    final sub = controller.frames.listen(displayed.add);
    // One camera per 8 ms for 3 seconds, faster than the 120 Hz display.
    final stopwatch = Stopwatch()..start();
    var i = 0;
    while (stopwatch.elapsed < const Duration(seconds: 3)) {
      final longitude = -10 + i * 0.01;
      sent.add(longitude);
      controller.setCamera(
          MapCamera(latitude: 0, longitude: longitude, zoom: 3));
      i++;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    final last = sent.last;
    // The final camera appears soon after the last update.
    final caughtUp = Stopwatch()..start();
    while (!displayed.any((f) => near(f.camera.longitude, last))) {
      if (caughtUp.elapsed > const Duration(seconds: 2)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await sub.cancel();
    debugPrint('rapid updates: sent ${sent.length} cameras, '
        'displayed ${displayed.length} frames, caught up in '
        '${caughtUp.elapsedMilliseconds} ms; ${controller.stats()}');

    expect(displayed.any((f) => near(f.camera.longitude, last)), isTrue,
        reason: 'the last camera was never displayed');
    expect(caughtUp.elapsed, lessThan(const Duration(milliseconds: 500)));
    // The map renders at most one frame ahead of what Flutter displays, so
    // camera updates that arrive between frames are coalesced.
    final stats = controller.stats();
    expect(stats.renderedFrames, lessThanOrEqualTo(stats.presentedFrames + 1));
    // From the first frame that shows a sent camera on, displayed cameras
    // never go backwards: no stale camera is shown after a newer one.
    final first =
        displayed.indexWhere((f) => near(f.camera.longitude, sent.first));
    expect(first, greaterThanOrEqualTo(0));
    for (var k = first + 1; k < displayed.length; k++) {
      expect(displayed[k].camera.longitude,
          greaterThanOrEqualTo(displayed[k - 1].camera.longitude - 1e-9));
    }
  });

  testWidgets('calls after dispose report an error', (tester) async {
    final controller = MapTextureController.create(pixelRatio: 2);
    controller.dispose();
    expect(
        () => controller.setCamera(
            const MapCamera(latitude: 0, longitude: 0, zoom: 1)),
        throwsA(isA<MapTextureDisposedException>()));
    expect(() => controller.loadStyleUrl(demoStyleUrl),
        throwsA(isA<MapTextureDisposedException>()));
    expect(() => controller.stats(),
        throwsA(isA<MapTextureDisposedException>()));
    // A second dispose is a no-op.
    controller.dispose();
  });

  testWidgets('50 create/dispose cycles keep the thread count stable',
      (tester) async {
    Future<void> cycle() async {
      final controller = MapTextureController.create(pixelRatio: 2);
      final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
      controller.resize(const Size(400, 300), 2);
      controller.loadStyleJson(colorStyle('#123456'));
      await loaded;
      controller.dispose();
    }

    // The first cycle starts process-wide threads that stay, such as
    // MapLibre's shared worker threads.
    await cycle();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final before = processThreadCount();
    for (var i = 0; i < 50; i++) {
      await cycle();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final after = processThreadCount();
    debugPrint('thread count: before $before, after 50 cycles $after');
    expect(after, lessThanOrEqualTo(before));
  });

  testWidgets('dispose while rendering', (tester) async {
    for (var round = 0; round < 5; round++) {
      final controller = await showMap(tester);
      controllers.remove(controller);
      final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
      controller.loadStyleUrl(demoStyleUrl);
      await loaded;
      // Keep the map rendering, then dispose while frames are in progress.
      for (var i = 0; i < 20; i++) {
        controller.setCamera(
            MapCamera(latitude: 0, longitude: i.toDouble(), zoom: 2));
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('idle map renders no frames for 10 seconds', (tester) async {
    final controller = await showMap(tester);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final before = controller.stats();
    await Future<void>.delayed(const Duration(seconds: 10));
    final after = controller.stats();
    debugPrint('idle: rendered ${before.renderedFrames} -> '
        '${after.renderedFrames} over 10 s');
    expect(after.renderedFrames, before.renderedFrames);
  });

  testWidgets('resizing on every frame for 10 seconds', (tester) async {
    final controller = MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio);
    controllers.add(controller);
    final size = ValueNotifier(const Size(400, 300));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<Size>(
          valueListenable: size,
          builder: (context, s, _) => SizedBox(
              width: s.width,
              height: s.height,
              child: MapTextureView(controller: controller)),
        ),
      ),
    ));
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;

    final stopwatch = Stopwatch()..start();
    var i = 0;
    while (stopwatch.elapsed < const Duration(seconds: 10)) {
      // Sizes between 300x200 and 700x500, changing every frame.
      final t = (i % 120) / 120;
      size.value = Size(300 + 400 * t, 200 + 300 * (1 - t));
      i++;
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    const finalSize = Size(640, 480);
    size.value = finalSize;
    await tester.pump();
    final ratio = tester.view.devicePixelRatio;
    final frame = await waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            f.physicalSize.width == finalSize.width * ratio &&
            f.physicalSize.height == finalSize.height * ratio);
    debugPrint('resize: $i sizes, final frame $frame; ${controller.stats()}');
    expect(frame.scaleFactor, ratio);
  });

  testWidgets('example shows a style load failure and keeps running',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: app.MapScreen()));
    await tester.tap(find.byKey(const Key('style-select')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Invalid URL').last);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (find.byKey(const Key('error')).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    debugPrint('example error text: ${error.data}');
    expect(error.data, startsWith('Error: '));
    expect(error.data!.length, greaterThan('Error: '.length));
    // The app still responds.
    await tester.tap(find.byKey(const Key('zoom-in')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Requested:'), findsOneWidget);
  });
}
