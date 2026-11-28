import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/src/map/camera.dart';
import 'package:mapigrade/src/map/mapigrade_camera_controller.dart';
import 'package:mapigrade/src/texture/map_texture_controller.dart';

import 'fake_map_controller.dart';

void main() {
  late MapigradeCameraController controller;
  late FakeMapController map;
  final owner = Object();
  const initial = MapigradeCamera(center: LatLng(10, 20), zoom: 4);

  setUp(() {
    controller = MapigradeCameraController();
    map = FakeMapController();
  });

  void attach() {
    bindCameraController(controller, owner, initial);
    setCameraControllerMap(controller, owner, map);
  }

  test('commands complete with the outcome that the map reports', () async {
    attach();
    final jump = controller.jumpTo(const MapigradeCamera(zoom: 12));
    final ease = controller.easeTo(
      const MapigradeCamera(bearing: 90),
      duration: const Duration(milliseconds: 300),
    );
    final fly = controller.flyTo(const MapigradeCamera(center: LatLng(1, 2)));
    expect(map.commands.map((c) => c.$2), [0, 1, 2]);
    expect(map.commands[0].$3.fields, mapTextureCameraZoomBit);
    expect(map.commands[0].$3.zoom, 12);
    expect(map.commands[1].$4, 300);
    expect(map.commands[2].$4, -1);
    map.send(CameraTransitionEnded(map.commands[1].$1, 3));
    map.send(CameraTransitionEnded(map.commands[0].$1, 0));
    map.send(CameraTransitionEnded(map.commands[2].$1, 1));
    expect(await jump, CameraTransitionOutcome.completed);
    expect(await ease, CameraTransitionOutcome.replaced);
    expect(await fly, CameraTransitionOutcome.cancelled);
  });

  test('a command camera that sets only the padding sets only its bit', () {
    attach();
    controller.jumpTo(
      const MapigradeCamera(padding: EdgeInsets.fromLTRB(1, 2, 3, 4)),
    );
    final camera = map.commands.single.$3;
    expect(camera.fields, 32);
    expect(
      (
        camera.paddingLeft,
        camera.paddingTop,
        camera.paddingRight,
        camera.paddingBottom,
      ),
      (1, 2, 3, 4),
    );
  });

  test('fitBounds passes the area, padding and optional angles', () {
    attach();
    controller.fitBounds(
      GeoBounds(const LatLng(1, 2), const LatLng(3, 4)),
      padding: const EdgeInsets.all(20),
      pitch: 30,
    );
    final (_, mode, fit, _) = map.fits.single;
    expect(mode, 0);
    expect((fit.south, fit.west, fit.north, fit.east), (1, 2, 3, 4));
    expect(fit.fields, 1 | 4);
    expect(fit.paddingTop, 20);
    expect(fit.pitch, 30);
  });

  test('calls while detached fail with a StateError', () async {
    await expectLater(
      controller.jumpTo(const MapigradeCamera(zoom: 1)),
      throwsStateError,
    );
    expect(() => controller.camera, throwsStateError);
    expect(controller.cancelTransitions, throwsStateError);
    // Attached, but without a map yet.
    bindCameraController(controller, owner, initial);
    await expectLater(
      controller.easeTo(const MapigradeCamera(zoom: 1)),
      throwsStateError,
    );
    expect(controller.camera.zoom, 4);
    setCameraControllerMap(controller, owner, map);
    releaseCameraController(controller, owner);
    await expectLater(
      controller.flyTo(const MapigradeCamera(zoom: 1)),
      throwsStateError,
    );
  });

  test('a detach cancels pending commands', () async {
    attach();
    final ease = controller.easeTo(const MapigradeCamera(zoom: 9));
    releaseCameraController(controller, owner);
    expect(await ease, CameraTransitionOutcome.cancelled);
  });

  test('the camera is the displayed frame camera, or the initial one', () {
    attach();
    expect(
      controller.camera,
      const MapigradeCamera(
        center: LatLng(10, 20),
        centerAltitude: 0,
        zoom: 4,
        bearing: 0,
        pitch: 0,
        roll: 0,
        fieldOfView: defaultFieldOfView,
        padding: EdgeInsets.zero,
      ),
    );
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(latitude: 1, longitude: 362, zoom: 7, pitch: 30),
    );
    expect(controller.camera.center, const LatLng(1, 2));
    expect(controller.camera.zoom, 7);
    expect(controller.camera.pitch, 30);
  });

  test('changes come with their source, one per changed frame', () async {
    attach();
    final changes = <CameraChange>[];
    controller.cameraChanges.listen(changes.add);
    cameraControllerFrameDisplayed(controller, owner, fakeFrame(zoom: 3));
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(zoom: 3.5, source: NativeCameraSource.gesture),
    );
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(zoom: 3.5, source: NativeCameraSource.gesture),
    );
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(zoom: 4, source: NativeCameraSource.momentum),
    );
    cameraControllerFrameDisplayed(controller, owner, fakeFrame(zoom: 5));
    await pumpEventQueue();
    expect(changes.map((c) => (c.camera.zoom, c.source)), [
      (3.5, CameraChangeSource.gesture),
      (4, CameraChangeSource.gesture),
      (5, CameraChangeSource.command),
    ]);
  });

  test('the rest stream emits once per rest', () async {
    attach();
    final rests = <MapigradeCamera>[];
    controller.rests.listen(rests.add);
    cameraControllerInputActive(controller, owner, true);
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(zoom: 3, generation: 4),
    );
    map.send(const CameraSettled(6));
    // A pointer is down, and no frame shows the settled camera yet.
    cameraControllerInputActive(controller, owner, false);
    await pumpEventQueue();
    expect(rests, isEmpty);
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(zoom: 4, generation: 6),
    );
    await pumpEventQueue();
    expect(rests.map((c) => c.zoom), [4]);
    cameraControllerFrameDisplayed(
      controller,
      owner,
      fakeFrame(zoom: 4, generation: 7),
    );
    await pumpEventQueue();
    expect(rests, hasLength(1));
    // The next rest.
    map.send(const CameraSettled(7));
    await pumpEventQueue();
    expect(rests.map((c) => c.zoom), [4, 4]);
  });
}

const mapTextureCameraZoomBit = 2;
