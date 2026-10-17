## Why

During camera changes, `flutter_map` overlays drawn above `MapigradeLayer` don't stay exactly on the map. The map renders asynchronously on the map thread. Flutter's raster thread displays whichever map frame is the latest when it composites, and Dart can't tell which frame that is when it builds the overlays. Camera prediction (lead 1, the default) reduces the offset during steady pans. In the manual check the overlays still visibly floated while a fling decelerated, and after abrupt stops and reversals the map ran ahead by 7 to 25 px (`docs/camera-alignment-options.md`, option 5). This change makes overlays exactly aligned by construction on macOS and iOS: Dart chooses the map frame that each Flutter frame displays, and draws the overlays at the camera that frame was rendered with. This is option 6 of that document combined with option 4.

## What Changes

- `MapigradeLayer` gets a new optional parameter, `children`: the overlay layers to draw aligned with the map. The layer draws them above the map, at the `flutter_map` camera of the displayed map frame instead of the live `flutter_map` camera. Layers placed after `MapigradeLayer` among the `FlutterMap` children (siblings) keep today's behavior.
- On macOS and iOS the native map registers four Flutter textures, one per display buffer ("slots"), instead of one. When a frame finishes rendering into a slot, Dart is told the slot and the camera. Each Flutter frame displays the texture of the newest finished slot, and the native map doesn't render into a slot while a Flutter frame may still display it.
- The camera that Dart sends to the map carries a sequence number. The frame report carries the number of the camera the frame was rendered with, so that the layer can give the children the exact `flutter_map` camera object that it converted for that frame. With camera prediction on, that is the predicted camera, so prediction changes how far map and children lag the gesture, and no longer changes their alignment.
- Gesture latency: the children move with the map, so they lag the gesture as the map does today, by about 1 to 2 Flutter frames at 120 Hz. Their hit tests use the positions they are drawn at.
- Android: unchanged rendering, one texture. The layer accepts `children` and draws them at the live `flutter_map` camera, as it draws siblings. A follow-up change covers Android.
- The alignment benchmark gets a configuration with the overlays as children, and reports the lag of the displayed camera behind the live `flutter_map` camera in logical pixels.
- The layer reads `flutter_map`'s `MapInheritedModel`, which `package:flutter_map/flutter_map.dart` doesn't export, through `package:flutter_map/src/map/inherited_model.dart`. The import is confined to one file under `lib/src/layer/`.

Assumptions, to be confirmed or changed in the manual check (tasks):

- The default alignment stays camera prediction with a lead of 1.
- Four slots are enough to keep today's frame rate.

Non-goals:

- Android slots (one `SurfaceProducer` per slot): the follow-up change.
- Blocking the raster thread until the map frame for the Flutter frame's camera has rendered (option A in the exploration).
- Exact alignment for siblings of `MapigradeLayer`.
- Overscan, or a transform of the map frame.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: a new requirement, "Children aligned with the displayed map frame", states that on macOS and iOS the layer draws its children at the camera of the displayed map frame, and on Android at the live camera. The requirement "Base layer of a flutter_map map" adds the `children` parameter. The requirement "Alignment measurement" adds the configuration with children and the lag measure.
- `map-texture`: the requirement "Camera of each displayed frame" changes on macOS and iOS: the system reports each finished frame with its slot and camera sequence number before Flutter displays it, and Dart chooses the frame to display. A new requirement, "Display slots", states the slot rules: a slot that a Flutter frame may still display isn't rendered into, and the displayed frame's contents don't change.

## Impact

- Native core (`packages/flutter_mapigrade/src/core/`): `buffer_state.h` (slot states replace latest, presented and free), `map_texture.cpp/.h` (render into a free slot, the frame-ready event, `Present(slot)`), `command_queue.h` (camera sequence number), `map_texture_api.h/.cpp` (new functions `map_texture_texture_ids`, `map_texture_select`, a `seq` argument on `map_texture_set_camera`, `slot` and `seq` fields in the event), `render_target.h` (texture id and frame-available per slot).
- Darwin (`darwin/.../MapTextureMetal.mm`): four `FlutterTexture`s and registrations, the fallback buffer during a resize per selected slot, the texture-cache workaround for each texture.
- Android (`android/src/main/cpp/map_texture_android.cpp`): reports one slot and accepts the new C functions; no rendering change.
- Dart: `lib/src/texture/` (controller: `textureIds`, `select`, camera sequence numbers, the frame-ready event; view: displays the selected slot), `lib/src/layer/map_texture_layer.dart` and `mapigrade_layer.dart` (`children`, the camera ring, the inherited model), `lib/src/testing.dart`.
- Tests: native core tests of the slot protocol (`test/native/`), Dart tests of the layer with a fake controller, `packages/test_harness` integration tests and the alignment benchmark (`lib/alignment_benchmark.dart`, `lib/alignment_mode.dart`).
- Demo (`packages/demo`) and example: place the route and marker layers as children of `MapigradeLayer`.
- Documentation: `docs/architecture.md` (threads and frame path), `docs/camera-alignment-options.md` (decision and results), `docs/benchmarks.md`, `README.md`, `CHANGELOG.md`.
- Dependency risk: a `flutter_map` release can change `MapInheritedModel` without notice; a test that builds it catches this when we upgrade.
