// Integration tests for the map-texture spec scenarios.
//
//   cd packages/test_harness && flutter test integration_test -d macos
//   cd packages/test_harness && flutter test integration_test -d <Android device id>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart' show MapigradeLayer;
import 'package:flutter_mapigrade/src/testing.dart';
import 'package:test_harness/main.dart' as app;
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

/// Marks the running test as skipped on Android, with [reason], and returns
/// true there. Tests that return early after it pass on Android.
bool skipOnAndroid(String reason) {
  if (!Platform.isAndroid) return false;
  markTestSkipped(reason);
  return true;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Let the engine produce frames continuously, so Flutter takes map frames
  // from the texture without the test pumping.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final controllers = <MapTextureController>[];
  // `--dart-define=COPY=true` runs every test with maps that copy each frame
  // instead of the default copy-free maps. The tests below that name a mode
  // run in that mode either way.
  const copyFree = !bool.fromEnvironment('COPY');

  /// Creates a controller and shows it in a 400x300 view.
  Future<MapTextureController> showMap(WidgetTester tester,
      {bool copyFree = copyFree}) async {
    final controller = await MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
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
    final controller =
        await MapTextureController.create(pixelRatio: 2, copyFree: copyFree);
    // Four slots with a texture each on macOS and iOS; six slots that share
    // one texture on Android (design D135).
    expect(controller.textureIds, hasLength(Platform.isAndroid ? 6 : 4));
    expect(controller.textureIds, everyElement(greaterThanOrEqualTo(0)));
    expect(controller.textureIds.toSet(),
        hasLength(Platform.isAndroid ? 1 : controller.textureIds.length));
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
    // The frame reports the bearing with the sign it was set with; the
    // layer's transform relies on it (flutter-map-layer design D23).
    expect(displayed.camera.bearing, closeTo(30, 1e-6));
  });

  testWidgets('display time increases from frame to frame', (tester) async {
    if (skipOnAndroid('Android reports no display times (design D58)')) return;
    final controller = await showMap(tester);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#3366cc'));
    await loaded;

    final displayed = <FrameCamera>[];
    final sub = controller.frames.listen(displayed.add);
    for (var i = 0; i < 30; i++) {
      controller
          .setCamera(MapCamera(latitude: 0, longitude: i * 0.1, zoom: 3));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();

    expect(displayed.length, greaterThan(10));
    expect(displayed.first.displayTime, greaterThan(0));
    for (var k = 1; k < displayed.length; k++) {
      expect(displayed[k].displayTime,
          greaterThan(displayed[k - 1].displayTime!),
          reason: 'frame ${displayed[k].frameId}');
    }
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
    final stats = controller.stats();
    if (Platform.isAndroid) {
      // Renders are paced to one per display refresh interval (designs D53
      // and D134), so camera updates that arrive between renders are
      // coalesced.
      final refreshRate = tester.view.display.refreshRate;
      final seconds = (stopwatch.elapsedMilliseconds +
              caughtUp.elapsedMilliseconds) /
          1000;
      expect(stats.renderedFrames,
          lessThanOrEqualTo((seconds * refreshRate).ceil() + 1));
      expect(stats.intervalWaits, greaterThan(0));
    } else {
      // The map renders at most one frame ahead of what Dart chooses, so
      // camera updates that arrive between frames are coalesced. Renders that
      // start before Dart chose the latest frame (while frames take longer
      // than a refresh interval, design D19) can replace an undisplayed
      // frame.
      expect(stats.renderedFrames,
          lessThanOrEqualTo(
              stats.presentedFrames + stats.renderAheadFrames + 1));
      expect(stats.intervalWaits, 0);
    }
    // From the first frame that shows a sent camera on, displayed cameras
    // never go backwards: no stale camera is shown after a newer one. Camera
    // updates coalesce, so the first sent camera may never be displayed.
    final first = displayed.indexWhere(
        (f) => sent.any((longitude) => near(f.camera.longitude, longitude)));
    expect(first, greaterThanOrEqualTo(0));
    for (var k = first + 1; k < displayed.length; k++) {
      expect(displayed[k].camera.longitude,
          greaterThanOrEqualTo(displayed[k - 1].camera.longitude - 1e-9));
    }
  });

  testWidgets('calls after dispose report an error', (tester) async {
    final controller =
        await MapTextureController.create(pixelRatio: 2, copyFree: copyFree);
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
      final controller =
        await MapTextureController.create(pixelRatio: 2, copyFree: copyFree);
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
    final footprintBefore = memoryFootprintForTesting();
    for (var i = 0; i < 50; i++) {
      await cycle();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final after = processThreadCount();
    String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);
    debugPrint('thread count: before $before, after 50 cycles $after; '
        'memory footprint ${mib(footprintBefore)} MiB before, '
        '${mib(memoryFootprintForTesting())} MiB after');
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

  testWidgets('copy-free map renders frames without copies', (tester) async {
    final controller = await showMap(tester, copyFree: true);
    expect(controller.copyFree, isTrue);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#00ff00'));
    await loaded;
    await waitFor<FrameCamera>(controller.frames, (_) => true);
    final stats = controller.stats();
    expect(stats.renderedFrames, greaterThan(0));
    expect(stats.copyCount, 0);
  });

  // Selecting a display buffer as the target before each render made the map
  // render without end before maplibre-native-ffi#807 (design D20).
  testWidgets('idle copy-free map renders no frames for 10 seconds',
      (tester) async {
    final controller = await showMap(tester, copyFree: true);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final before = controller.stats();
    await Future<void>.delayed(const Duration(seconds: 10));
    final after = controller.stats();
    debugPrint('idle copy-free: rendered ${before.renderedFrames} -> '
        '${after.renderedFrames} over 10 s');
    expect(after.renderedFrames, before.renderedFrames);
  });

  testWidgets('map with the copy renders frames with copies', (tester) async {
    final controller = await showMap(tester, copyFree: false);
    expect(controller.copyFree, isFalse);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#00ff00'));
    await loaded;
    await waitFor<FrameCamera>(controller.frames, (_) => true);
    final stats = controller.stats();
    expect(stats.renderedFrames, greaterThan(0));
    if (Platform.isAndroid) {
      // Every map renders directly into Flutter's buffers on Android.
      expect(stats.copyCount, 0);
    } else {
      // A frame is counted as copied just before it's counted as rendered.
      expect(stats.copyCount, greaterThanOrEqualTo(stats.renderedFrames));
    }
  });

  testWidgets('idle map with the copy renders no frames for 10 seconds',
      (tester) async {
    final controller = await showMap(tester, copyFree: false);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final before = controller.stats();
    await Future<void>.delayed(const Duration(seconds: 10));
    final after = controller.stats();
    debugPrint('idle with copy: rendered ${before.renderedFrames} -> '
        '${after.renderedFrames} over 10 s');
    expect(after.renderedFrames, before.renderedFrames);
  });

  // The lifecycle tests use the test hooks, which call the same native
  // functions as the iOS background, foreground and memory warning handlers
  // (design D15).
  testWidgets('no rendering while paused; resume shows the latest camera',
      (tester) async {
    addTearDown(() => setRenderingPausedForTesting(false));
    final controller = await showMap(tester);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final errors = <RenderError>[];
    final sub = controller.events
        .where((e) => e is RenderError)
        .cast<RenderError>()
        .listen(errors.add);

    setRenderingPausedForTesting(true);
    final paused = controller.stats();
    // Camera changes on every Flutter frame for 2 seconds while paused.
    final stopwatch = Stopwatch()..start();
    var i = 0;
    while (stopwatch.elapsed < const Duration(seconds: 2)) {
      controller.setCamera(
          MapCamera(latitude: 0, longitude: -20 + i * 0.05, zoom: 3));
      i++;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    const last = MapCamera(latitude: 10, longitude: 20, zoom: 4);
    controller.setCamera(last);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final whilePaused = controller.stats();

    final frame = waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            near(f.camera.latitude, last.latitude) &&
            near(f.camera.longitude, last.longitude) &&
            near(f.camera.zoom, last.zoom));
    setRenderingPausedForTesting(false);
    await frame;
    await sub.cancel();
    debugPrint('paused: sent $i cameras; rendered '
        '${paused.renderedFrames} -> ${whilePaused.renderedFrames} while '
        'paused; ${controller.stats()}');

    expect(whilePaused.renderedFrames, paused.renderedFrames);
    expect(whilePaused.renderUpdateCount, paused.renderUpdateCount);
    expect(whilePaused.pausedRenders, greaterThan(paused.pausedRenders));
    expect(errors, isEmpty);
  });

  testWidgets('a map created while paused renders after resume',
      (tester) async {
    addTearDown(() => setRenderingPausedForTesting(false));
    setRenderingPausedForTesting(true);
    final controller = await showMap(tester);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleJson(colorStyle('#3366cc'));
    await loaded;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(controller.stats().renderedFrames, 0);

    final frame = waitFor<FrameCamera>(controller.frames, (_) => true);
    setRenderingPausedForTesting(false);
    await frame;
  });

  testWidgets('dispose while paused', (tester) async {
    addTearDown(() => setRenderingPausedForTesting(false));
    final controller = await showMap(tester);
    controllers.remove(controller);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final events = <Object>[];
    final sub = controller.events.listen(events.add);
    final frames = controller.frames.listen(events.add);

    setRenderingPausedForTesting(true);
    controller.setCamera(const MapCamera(latitude: 0, longitude: 5, zoom: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    events.clear();
    setRenderingPausedForTesting(false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sub.cancel();
    await frames.cancel();
    expect(controller.isDisposed, isTrue);
    expect(events, isEmpty);
  });

  testWidgets('memory reduction keeps the map rendering', (tester) async {
    final controller = await showMap(tester);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final errors = <RenderError>[];
    final sub = controller.events
        .where((e) => e is RenderError)
        .cast<RenderError>()
        .listen(errors.add);

    final before = controller.stats();
    reduceMemoryUseForTesting();
    const camera = MapCamera(latitude: 30, longitude: -40, zoom: 3);
    final frame = waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            near(f.camera.latitude, camera.latitude) &&
            near(f.camera.longitude, camera.longitude));
    controller.setCamera(camera);
    await frame;
    await sub.cancel();
    expect(controller.stats().memoryReductions, before.memoryReductions + 1);
    expect(errors, isEmpty);
  });

  // The plugin releases the image reader when the activity stops and creates
  // one when the activity starts (design D137). The test hook makes it do both
  // while the activity runs.
  testWidgets('surface removal and restore keep the map and its style',
      (tester) async {
    if (!Platform.isAndroid) {
      markTestSkipped('the plugin releases surfaces only on Android');
      return;
    }
    final controller = await showMap(tester);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    final events = <MapEvent>[];
    final sub = controller.events.listen(events.add);

    final chosen = controller.selectedFrame;
    trimSurfacesForTesting(restore: false);
    final removed = controller.stats();
    // The release frees the slots, so no frame can be chosen, and the frame
    // chosen before stays the selected frame.
    expect(chosen, isNotNull);
    expect(controller.selectNewest(), isNull);
    expect(controller.selectedFrame, same(chosen));
    // Camera changes while the surface is removed render nothing.
    const camera = MapCamera(latitude: 20, longitude: 30, zoom: 4);
    controller.setCamera(camera);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final whileRemoved = controller.stats();

    final frame = waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            near(f.camera.latitude, camera.latitude) &&
            near(f.camera.longitude, camera.longitude) &&
            near(f.camera.zoom, camera.zoom));
    trimSurfacesForTesting(restore: true);
    await frame;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();
    debugPrint('surface removed: rendered ${removed.renderedFrames} -> '
        '${whileRemoved.renderedFrames}; events after removal $events');

    expect(whileRemoved.renderedFrames, removed.renderedFrames);
    expect(events.whereType<RenderError>(), isEmpty);
    expect(events.whereType<StyleLoaded>(), isEmpty,
        reason: 'the style must not load again');
  });

  // The maximum cache size is process-wide, so these tests set the default
  // again when they end. They set values above 50 MiB so that they don't
  // evict the resources that the other tests use.
  testWidgets('a map with a maximum cache size loads its style',
      (tester) async {
    addTearDown(() => MapigradeLayer.maximumCacheSizeBytes = 50 << 20);
    MapigradeLayer.maximumCacheSizeBytes = 100 << 20;
    final controller = await showMap(tester);
    final errors = <RenderError>[];
    final sub = controller.events
        .where((e) => e is RenderError)
        .cast<RenderError>()
        .listen(errors.add);
    final idle = waitFor<MapIdle>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await idle;
    await sub.cancel();
    expect(errors, isEmpty);
  });

  testWidgets('a maximum cache size set while a map exists', (tester) async {
    addTearDown(() => MapigradeLayer.maximumCacheSizeBytes = 50 << 20);
    MapigradeLayer.maximumCacheSizeBytes = 100 << 20;
    final first = await showMap(tester);
    var idle = waitFor<MapIdle>(first.events, (_) => true);
    first.loadStyleUrl(demoStyleUrl);
    await idle;

    MapigradeLayer.maximumCacheSizeBytes = 80 << 20;
    final second = await MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
    controllers.add(second);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        SizedBox(
            width: 200, height: 300, child: MapTextureView(controller: first)),
        SizedBox(
            width: 200, height: 300, child: MapTextureView(controller: second)),
      ]),
    ));
    final errors = <RenderError>[];
    final subs = [
      for (final c in [first, second])
        c.events
            .where((e) => e is RenderError)
            .cast<RenderError>()
            .listen(errors.add),
    ];
    final firstIdle = waitFor<MapIdle>(first.events, (_) => true);
    idle = waitFor<MapIdle>(second.events, (_) => true);
    first.setCamera(const MapCamera(latitude: 20, longitude: 30, zoom: 3));
    second.loadStyleUrl(demoStyleUrl);
    await Future.wait([firstIdle, idle]);
    for (final sub in subs) {
      await sub.cancel();
    }
    expect(errors, isEmpty);
    expect(MapigradeLayer.maximumCacheSizeBytes, 80 << 20);
  });

  testWidgets('resizing on every frame for 10 seconds', (tester) async {
    final controller = await MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
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
    final footprintBefore = memoryFootprintForTesting();
    var footprintMax = footprintBefore;

    // Sizes that fit the view: a 1600x1000 window on macOS, a 402x874 screen
    // on an iPhone 16 Pro.
    final ratio = tester.view.devicePixelRatio;
    final view = tester.view.physicalSize / ratio;
    final minSize = Size(view.width * 0.3, view.height * 0.2);
    final maxSize = Size(view.width * 0.9, view.height * 0.7);
    final stopwatch = Stopwatch()..start();
    var i = 0;
    while (stopwatch.elapsed < const Duration(seconds: 10)) {
      // Sizes between minSize and maxSize, changing every frame.
      final t = (i % 120) / 120;
      size.value = Size(
          minSize.width + (maxSize.width - minSize.width) * t,
          minSize.height + (maxSize.height - minSize.height) * (1 - t));
      i++;
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 8));
      if (i % 30 == 0) {
        footprintMax = math.max(footprintMax, memoryFootprintForTesting());
      }
    }
    // The core rounds the physical size to whole pixels; with a device pixel
    // ratio such as 2.625 (Android) whole logical pixels don't give whole
    // physical pixels.
    final finalSize = Size((view.width * 0.8).floorToDouble(),
        (view.height * 0.6).floorToDouble());
    size.value = finalSize;
    FrameCamera? lastFrame;
    final lastFrames = controller.frames.listen((f) => lastFrame = f);
    await tester.pump();
    final FrameCamera frame;
    try {
      frame = await waitFor<FrameCamera>(
          controller.frames,
          (f) =>
              f.physicalSize.width == (finalSize.width * ratio).roundToDouble() &&
              f.physicalSize.height ==
                  (finalSize.height * ratio).roundToDouble());
    } on TimeoutException {
      debugPrint('resize: no frame of ${finalSize * ratio} (rounded); last frame '
          '$lastFrame; ${controller.stats()}');
      rethrow;
    } finally {
      await lastFrames.cancel();
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);
    debugPrint('resize: $i sizes, final frame $frame; ${controller.stats()}; '
        'memory footprint ${mib(footprintBefore)} MiB before, '
        '${mib(footprintMax)} MiB max during, '
        '${mib(memoryFootprintForTesting())} MiB after');
    expect(frame.scaleFactor, ratio);
  });

  // Before the fixes in docs/flutter-texture-cache-followup.md, almost every
  // display buffer replaced by a resize stayed alive until the map was
  // disposed. Flutter's own texture cache keeps them during a burst of
  // resizes; the plugin makes it free them after the burst.
  testWidgets('display buffers replaced by resizes are freed afterwards',
      (tester) async {
    if (skipOnAndroid('the plugin owns no display buffers on Android')) {
      return;
    }
    final controller = await MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
    controllers.add(controller);
    final size = ValueNotifier(const Size(200, 200));
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
    resetReleasedBuffersForTesting();
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 120; i++) {
      final t = i / 120;
      size.value = Size(view.width * (0.3 + 0.6 * t),
          view.height * (0.2 + 0.5 * (1 - t)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final r = releasedBuffersForTesting();
    debugPrint('released buffers: ${r.alive} of ${r.released} alive '
        '2.5 s after the last resize');
    expect(r.released, greaterThan(100));
    expect(r.alive, lessThanOrEqualTo(r.released ~/ 4));
  });

  testWidgets('example shows a style load failure and keeps running',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: app.MapScreen()));
    // The screen creates its map asynchronously (design D155 of the
    // multiple-flutter-engines change).
    final shown = DateTime.now().add(const Duration(seconds: 20));
    while (find.byType(MapTextureView).evaluate().isEmpty &&
        DateTime.now().isBefore(shown)) {
      await tester.pump(const Duration(milliseconds: 10));
    }
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

  testWidgets('example panel buttons change the camera and the style switch '
      'loads another style', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: app.MapScreen()));
    Future<void> pumpUntil(bool Function() condition, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out waiting: $what');
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    String text(Finder finder) => tester.widget<Text>(finder).data!;
    String status() => text(find.byKey(const Key('status')));
    String requested() => text(find.textContaining('Requested:'));
    String displayed() => text(find.textContaining('Displayed'));
    // Parses "<lat>, <lon> z<zoom> b<bearing>" at the end of a panel line.
    List<double> camera(String line) {
      final m = RegExp(r'(-?[\d.]+), (-?[\d.]+) z([\d.]+) b(-?[\d.]+)$')
          .firstMatch(line)!;
      return [for (var i = 1; i <= 4; i++) double.parse(m.group(i)!)];
    }

    bool displaysRequested() {
      if (!displayed().contains('#')) return false;
      final r = camera(requested());
      final d = camera(displayed());
      final bearingDelta = ((r[3] - d[3]) % 360 + 360) % 360;
      return (r[0] - d[0]).abs() < 1e-3 &&
          (r[1] - d[1]).abs() < 1e-3 &&
          (r[2] - d[2]).abs() < 1e-2 &&
          (bearingDelta < 0.5 || bearingDelta > 359.5);
    }

    await pumpUntil(() => status() == 'Status: idle', 'first style idle');
    for (final key in ['zoom-in', 'rotate-right', 'pan-east', 'pan-north']) {
      final before = requested();
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      expect(requested(), isNot(before), reason: key);
      await pumpUntil(displaysRequested, 'frame for $key');
    }
    debugPrint('panel: ${requested()} / ${displayed()}');

    await tester.tap(find.byKey(const Key('style-select')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('MapLibre demo tiles').last);
    await tester.pump();
    await pumpUntil(() => status() == 'Status: idle', 'second style idle');
    expect(find.byKey(const Key('error')), findsNothing);
  });

  // Design D123: the texture of the chosen slot is marked available
  // synchronously, so the Flutter frame displays the frame Dart chose.
  // On Android the plugin closes each image it gives to Flutter (design
  // D133). If it didn't, the image reader would run out of images and the map
  // would stop rendering long before 600 frames.
  testWidgets('a pan of 600 Flutter frames keeps rendering', (tester) async {
    final controller = await showMap(tester);
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;
    final errors = <RenderError>[];
    final sub = controller.events
        .where((e) => e is RenderError)
        .cast<RenderError>()
        .listen(errors.add);
    for (var i = 0; i < 600; i++) {
      controller.setCamera(
          MapCamera(latitude: 0, longitude: -10 + i * 0.01, zoom: 3));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    // A map that ran out of images would never display this camera.
    const last = MapCamera(latitude: 5, longitude: 5, zoom: 3);
    final shown = waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            near(f.camera.latitude, last.latitude) &&
            near(f.camera.longitude, last.longitude));
    controller.setCamera(last);
    await shown;
    await sub.cancel();
    final stats = controller.stats();
    debugPrint('600 frames: $stats');
    expect(stats.presentedFrames, greaterThan(1));
    expect(errors, isEmpty);
  });

  testWidgets('a selected frame is displayed', (tester) async {
    final controller = await MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
    controllers.add(controller);
    final log = <_SlotEntry>[];
    final displayed = controller.frames
        .listen((f) => log.add(_SlotEntry(selected: false, frame: f)));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
            width: 400,
            height: 300,
            child: _SelectingView(controller: controller, log: log)),
      ),
    ));
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;
    for (var i = 0; i < 30; i++) {
      controller.setCamera(MapCamera(latitude: 10, longitude: i * 0.2, zoom: 4));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    // The map may still render the last cameras, and the view choose their
    // frames; wait until the frame chosen last has been displayed.
    bool lastSelectedDisplayed() {
      final selected = log.lastWhere((e) => e.selected);
      return log.any((e) =>
          !e.selected && e.frame.frameId == selected.frame.frameId);
    }
    final settle = Stopwatch()..start();
    do {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } while (!lastSelectedDisplayed() &&
        settle.elapsed < const Duration(seconds: 10));
    await displayed.cancel();
    final selectedIds = {
      for (final e in log)
        if (e.selected) e.frame.frameId,
    };
    final displayedFrames = [
      for (final e in log)
        if (!e.selected) e.frame,
    ];
    debugPrint('select: ${selectedIds.length} frames selected, '
        '${displayedFrames.length} displayed; ${controller.stats()}');
    expect(displayedFrames, isNotEmpty);
    for (final frame in displayedFrames) {
      expect(selectedIds, contains(frame.frameId),
          reason: 'displayed $frame was never selected');
    }
    // The frame selected last is the frame displayed last.
    final lastSelected = log.lastWhere((e) => e.selected).frame;
    expect(displayedFrames.last.frameId, lastSelected.frameId);
    expect(displayedFrames.last.slot, lastSelected.slot);
    expect(displayedFrames.last.seq, lastSelected.seq);
  });

  // Design D126: during a resize the texture keeps showing the frame Dart
  // chose last, until Dart chooses a frame of the new size. On Android the
  // image texture keeps the image Dart chose last (design D136).
  testWidgets('resize keeps the selected frame until a new-size selection',
      (tester) async {
    final controller = await MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
    controllers.add(controller);
    final log = <_SlotEntry>[];
    final displayed = controller.frames
        .listen((f) => log.add(_SlotEntry(selected: false, frame: f)));
    // Widths up to 400 fit every screen the tests run on.
    final size = ValueNotifier(const Size(200, 300));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<Size>(
          valueListenable: size,
          builder: (context, s, _) => SizedBox(
              width: s.width,
              height: s.height,
              child: _SelectingView(controller: controller, log: log)),
        ),
      ),
    ));
    final loaded = waitFor<StyleLoaded>(controller.events, (_) => true);
    controller.loadStyleUrl(demoStyleUrl);
    await loaded;
    final ratio = tester.view.devicePixelRatio;
    for (var round = 0; round < 5; round++) {
      final oldWidth = (size.value.width * ratio).roundToDouble();
      if (controller.displayedFrame?.physicalSize.width != oldWidth) {
        await waitFor<FrameCamera>(
            controller.frames, (f) => f.physicalSize.width == oldWidth);
      }
      final start = log.length;
      size.value = Size(size.value.width + 40, 300);
      final newWidth = (size.value.width * ratio).roundToDouble();
      final newFrame = waitFor<FrameCamera>(
          controller.frames, (f) => f.physicalSize.width == newWidth);
      await tester.pump();
      await newFrame;
      final entries = log.sublist(start);
      final firstNew = entries.indexWhere(
          (e) => e.selected && e.frame.physicalSize.width == newWidth);
      expect(firstNew, greaterThanOrEqualTo(0));
      for (final e in entries.take(firstNew)) {
        if (e.selected) continue;
        expect(e.frame.physicalSize.width, oldWidth,
            reason: 'round $round: displayed ${e.frame} before the first '
                'selection of a ${newWidth}px frame');
      }
    }
    await displayed.cancel();
  });
}

/// A selection or a display, in the order the test saw them.
class _SlotEntry {
  _SlotEntry({required this.selected, required this.frame});
  final bool selected;
  final FrameCamera frame;
}

/// Chooses the newest finished frame in each build, as the layer does,
/// displays the slot of the frame selected last, and logs each recorded
/// selection to [log].
class _SelectingView extends StatefulWidget {
  const _SelectingView({required this.controller, required this.log});
  final MapTextureController controller;
  final List<_SlotEntry> log;

  @override
  State<_SelectingView> createState() => _SelectingViewState();
}

class _SelectingViewState extends State<_SelectingView> {
  StreamSubscription<FrameCamera>? _ready;

  @override
  void initState() {
    super.initState();
    _ready = widget.controller.readyFrames.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _ready?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // If no frame has finished since the last choice, the view keeps the
    // frame selected before.
    final chosen = controller.isDisposed ? null : controller.selectNewest();
    if (chosen != null) {
      widget.log.add(_SlotEntry(selected: true, frame: chosen));
    }
    return MapTextureView(
        controller: controller, slot: controller.selectedFrame?.slot ?? 0);
  }
}
