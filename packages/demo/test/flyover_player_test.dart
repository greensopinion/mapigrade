// The player's warm-up pass and the recording mode's wait at the start
// (design D145 of the readme-demo-recording change).
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade_demo/src/flyover.dart';
import 'package:mapigrade_demo/src/flyover_player.dart';
import 'package:mapigrade_demo/src/stages.dart';

void main() {
  final stages = parseStages(File(stagesAsset).readAsStringSync());

  /// A map of 1200 x 800 pixels with [controller], and a flyover built for it.
  Future<Flyover> pumpMap(WidgetTester tester, MapController controller) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 1200,
            height: 800,
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(43.7, 7.27),
                initialZoom: 12,
              ),
              children: const [],
            ),
          ),
        ),
      ),
    );
    return Flyover.build(stages, controller.camera);
  }

  void expectCamera(MapController controller, FlyoverCamera expected) {
    final camera = controller.camera;
    expect(camera.center.latitude, closeTo(expected.center.latitude, 1e-9));
    expect(camera.center.longitude, closeTo(expected.center.longitude, 1e-9));
    expect(camera.zoom, closeTo(expected.zoom, 1e-9));
    expect(camera.rotation, closeTo(expected.rotation, 1e-6));
  }

  testWidgets('a warm-up of 31 s waits at the start, then plays from 0', (
    tester,
  ) async {
    final controller = MapController();
    final flyover = await pumpMap(tester, controller);
    final player = FlyoverPlayer(
      vsync: const TestVSync(),
      controller: controller,
    );
    addTearDown(player.dispose);

    player.play(
      flyover,
      warmUp: const Duration(seconds: 31),
      waitAfterWarmUp: true,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(player.phase, FlyoverPhase.warmingUp);
    expectCamera(controller, flyover.cameraAt(const Duration(seconds: 30)));

    await tester.pump(const Duration(seconds: 2));
    expect(player.phase, FlyoverPhase.waiting);
    expect(player.isActive, isTrue);
    expect(player.rider.value, isNull);
    expectCamera(controller, flyover.cameraAt(Duration.zero));

    // Waiting doesn't move the camera.
    await tester.pump(const Duration(seconds: 5));
    expect(player.phase, FlyoverPhase.waiting);
    expectCamera(controller, flyover.cameraAt(Duration.zero));

    player.start();
    await tester.pump();
    expect(player.phase, FlyoverPhase.playing);
    expectCamera(controller, flyover.cameraAt(Duration.zero));
    await tester.pump(const Duration(seconds: 10));
    expectCamera(controller, flyover.cameraAt(const Duration(seconds: 10)));
    expect(player.rider.value, flyover.riderAt(const Duration(seconds: 10)));
    player.stop();
  });

  testWidgets('a warm-up of the whole flyover plays again from 0', (
    tester,
  ) async {
    final controller = MapController();
    final flyover = await pumpMap(tester, controller);
    final player = FlyoverPlayer(
      vsync: const TestVSync(),
      controller: controller,
    );
    addTearDown(player.dispose);

    player.play(flyover, warmUp: flyover.duration);
    await tester.pump();
    await tester.pump(flyover.duration);
    expect(player.phase, FlyoverPhase.playing);
    expectCamera(controller, flyover.cameraAt(Duration.zero));
    await tester.pump(const Duration(seconds: 4));
    expectCamera(controller, flyover.cameraAt(const Duration(seconds: 4)));
    player.stop();
  });

  testWidgets('without a warm-up the run starts at once', (tester) async {
    final controller = MapController();
    final flyover = await pumpMap(tester, controller);
    final player = FlyoverPlayer(
      vsync: const TestVSync(),
      controller: controller,
    );
    addTearDown(player.dispose);

    player.play(flyover);
    expect(player.phase, FlyoverPhase.playing);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expectCamera(controller, flyover.cameraAt(const Duration(seconds: 4)));

    // start() does nothing outside the wait.
    player.start();
    expect(player.phase, FlyoverPhase.playing);
    player.stop();
  });
}
