// Memory before and after a memory reduction (task 5.5 of the iOS slice), and
// what holds the memory that resizing adds.
// Not part of the integration test suite; run it on its own:
//
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/memory_measurement.dart
//
// Shows the map full screen with the OpenFreeMap Liberty style, visits zoom
// levels 10 to 16 around San Francisco, waiting for each to load, then asks
// the renderer to release cached resources through the same native function
// that the iOS memory warning handler calls, and prints the process's memory
// footprint (the value Xcode's memory gauge shows) before and after.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const libertyStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // `--dart-define=COPY=true` measures maps with the copy.
  const copyFree = !bool.fromEnvironment('COPY');

  testWidgets('memory footprint before and after a memory reduction',
      (tester) async {
    final controller = MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MapTextureView(controller: controller));

    Future<void> idle() => controller.events
        .firstWhere((e) => e is MapIdle)
        .timeout(const Duration(seconds: 30), onTimeout: () => const MapIdle());

    double mib(int bytes) => bytes / (1024 * 1024);
    final baseline = memoryFootprintForTesting();

    var loaded = idle();
    controller.loadStyleUrl(libertyStyleUrl);
    controller.setCamera(
        const MapCamera(latitude: 37.7749, longitude: -122.4194, zoom: 10));
    await loaded;
    for (var zoom = 11; zoom <= 16; zoom++) {
      loaded = idle();
      controller.setCamera(MapCamera(
          latitude: 37.7749,
          longitude: -122.4194 + (zoom - 10) * 0.01,
          zoom: zoom.toDouble()));
      await loaded;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final before = memoryFootprintForTesting();
    final statsBefore = controller.stats();

    reduceMemoryUseForTesting();
    await Future<void>.delayed(const Duration(seconds: 2));
    final after2s = memoryFootprintForTesting();
    await Future<void>.delayed(const Duration(seconds: 5));
    final after7s = memoryFootprintForTesting();
    final statsAfter = controller.stats();

    debugPrint('MEMORY_RESULT ${jsonEncode({
          'copy_free': copyFree,
          'baseline_before_map_mib': mib(baseline),
          'before_reduction_mib': mib(before),
          'after_2s_mib': mib(after2s),
          'after_7s_mib': mib(after7s),
          'memory_reductions':
              statsAfter.memoryReductions - statsBefore.memoryReductions,
          'frames_rendered_after_reduction':
              statsAfter.renderedFrames - statsBefore.renderedFrames,
        })}');
    expect(statsAfter.memoryReductions, statsBefore.memoryReductions + 1);
  });

  // Display buffers that stay alive after the plugin released them when the
  // map is resized repeatedly. Before the fixes, they stayed alive until the
  // map was disposed.
  testWidgets('released buffers and memory footprint during resizing',
      (tester) async {
    String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);
    String phase(String name) {
      final r = releasedBuffersForTesting();
      return '$name: footprint ${mib(memoryFootprintForTesting())} MiB, '
          'released buffers alive ${r.alive} of ${r.released} '
          '(${mib(r.aliveBytes)} MiB)';
    }

    final controller = MapTextureController.create(
        pixelRatio: tester.view.devicePixelRatio, copyFree: copyFree);
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
    final loaded = controller.events.firstWhere((e) => e is StyleLoaded);
    controller.loadStyleUrl('https://demotiles.maplibre.org/style.json');
    await loaded;
    await Future<void>.delayed(const Duration(seconds: 1));
    resetReleasedBuffersForTesting();
    final lines = <String>[phase('start')];
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 300; i++) {
      final t = (i % 120) / 120;
      size.value = Size(view.width * (0.3 + 0.6 * t),
          view.height * (0.2 + 0.5 * (1 - t)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if ((i + 1) % 60 == 0) lines.add(phase('after ${i + 1} resizes'));
    }
    lines.add(phase('right after the last resize'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    lines.add(phase('0.5 s after the last resize'));
    await Future<void>.delayed(const Duration(seconds: 2));
    lines.add(phase('2.5 s after the last resize'));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await Future<void>.delayed(const Duration(seconds: 2));
    lines.add(phase('2 s after dispose'));
    debugPrint('RESIZE_BUFFERS\n  ${lines.join('\n  ')}');
  });
}
