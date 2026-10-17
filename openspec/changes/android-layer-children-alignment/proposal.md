## Why

On Android, `MapigradeLayer` draws its `children` at the live `flutter_map` camera, because the map has one `SurfaceProducer` and Dart can't choose the frame that Flutter displays (D128 of layer-children-alignment). On the Pixel 4a (5G) the overlays float over the map during every pan, even with camera prediction at a lead of 1. The layer-children-alignment change made children exact on macOS and iOS, and left Android to this change.

## What Changes

- Android: the map renders into an `ImageReader` that the plugin owns, and Flutter displays it through an image texture (`TextureRegistry.createImageTexture`). The `SurfaceProducer` is removed. Each finished frame is reported to Dart with its display slot before Flutter displays it, as on macOS and iOS, and `map_texture_select` gives Flutter the chosen frame's image before the Flutter frame being built is rasterized.
- Android has six display slots. All six use the one image texture, so `textureIds` has six entries with the same id. A chosen slot becomes free when Dart has chosen three later frames, because Flutter tells the plugin nothing when it has finished with an image. The slots beyond the three held ones hold the ready frame, a frame whose image hasn't arrived yet, and the frame being rendered.
- The layer draws its children at the camera of the displayed map frame on Android too, and the Android branch in the layer is removed.
- The map keeps rendering once per display refresh interval (D53 of android-texture-vertical-slice). Dart chooses the newest ready frame in each Flutter frame, and frames that Dart doesn't choose are replaced.
- On Android the frame-displayed report is sent when Dart chooses the frame, with no display time. Frames that Dart never chooses don't count as displayed. As a result, the layer metrics count fewer displayed frames than rendered frames, as on macOS and iOS.
- The plugin releases its `ImageReader` when the Flutter activity stops and when Android reports memory pressure, and creates a new one when the activity starts again. Flutter took these actions for the `SurfaceProducer`.

Assumption, to be confirmed or changed in the manual check (tasks): an image that Dart chose is no longer read by the GPU once Dart has chosen three later frames. Flutter's own `ImageReaderSurfaceProducer` closes images under the same assumption.

Non-goals:

- The alignment benchmark on Android. It needs display times, which Android doesn't report. The user checks alignment by hand on the reference device, as decided for the Android slice.
- An exact display time on Android.
- Vulkan rendering for the map (D51).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: "Display slots" adds six slots on Android that share one Flutter texture, and their release rule. "Camera of each displayed frame" adds frame-ready reports on Android, and moves the Android frame-displayed report to when Dart chooses the frame. "Surface replacement and removal on Android" changes from Flutter removing the surface to the plugin releasing its image reader when the activity stops or under memory pressure.
- `map-layer`: "Children aligned with the displayed map frame" applies to Android too. "Metrics" counts a displayed frame on Android when Dart chooses it.

## Impact

- Native core (`packages/flutter_mapigrade/src/core/`): `buffer_state.h` (a release rule that counts selections, six slots), `map_texture.cpp/.h` (the Android target publishes a frame when its image arrives, the frame-displayed event at `Select`, a free slot for each render paced by the refresh interval), `render_target.h` (the Android target's kind and functions).
- Android (`android/src/main/cpp/map_texture_android.cpp`, `android/src/main/kotlin/.../MapSurface.kt`, `MapigradePlugin.kt`): an `ImageReader` per size with its listener on a dedicated thread, presentation times as frame ids, `pushImage` on selection, closing images, releasing the reader on stop and memory pressure.
- Dart (`lib/src/layer/map_texture_layer.dart`, `lib/src/texture/map_texture_controller.dart`): no Android branch; documentation of `textureIds`, `readyFrames`, `select`, `frames` and the statistics.
- Tests: native core tests of the release rule, integration tests in `packages/test_harness` that check Android counts, pacing and surface removal, and the layer metrics test.
- Documentation: `docs/architecture.md`, `docs/limitations.md`, `docs/camera-alignment-options.md`, `docs/benchmarks.md`, `CHANGELOG.md`.
- Memory: up to seven buffers of the map's size, as the `SurfaceProducer` allowed.
