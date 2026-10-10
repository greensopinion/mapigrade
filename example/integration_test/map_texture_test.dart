// Integration tests for the map-texture spec scenarios.
//
//   cd example && flutter test integration_test -d macos
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map_maplibre_texture/flutter_map_maplibre_texture.dart';
import 'package:flutter_map_maplibre_texture/testing.dart';
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
    // Whole logical pixels, so the physical size is exact.
    final finalSize = Size((view.width * 0.8).floorToDouble(),
        (view.height * 0.6).floorToDouble());
    size.value = finalSize;
    await tester.pump();
    final frame = await waitFor<FrameCamera>(
        controller.frames,
        (f) =>
            f.physicalSize.width == finalSize.width * ratio &&
            f.physicalSize.height == finalSize.height * ratio);
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
    final controller = MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio);
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
}
