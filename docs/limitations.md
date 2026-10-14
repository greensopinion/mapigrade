# Limitations and findings of the macOS and iOS vertical slices

Measured results are in `benchmarks.md`. The designs and their amendments are in `openspec/changes/archive/2026-10-09-macos-texture-vertical-slice/design.md` (macOS) and `openspec/changes/archive/2026-10-10-ios-texture-vertical-slice/design.md` (iOS, decisions D11 to D18).

## App bundle size

### macOS

Release builds, arm64, measured with `du -sk` on 2026-10-09:

| Bundle | Size |
| --- | --- |
| `flutter create` template app (baseline) | 37,716 KB |
| example app with this plugin | 51,816 KB |
| increase | 14,100 KB (13.8 MiB) |
| of which `MapLibreNativeC.framework` | 12,884 KB |

The rest of the increase is the plugin's native code in the app executable and the example's own Dart code. The FFI library is built for arm64 only; a universal build would roughly double the framework.

### iOS

`Runner.app` of release builds for iOS devices (`flutter build ios --release --no-codesign`, arm64), measured with `du -sk` on 2026-10-10. The builds are unsigned; signing adds the code signature and the provisioning profile.

| Bundle | Size |
| --- | --- |
| `flutter create` template app (baseline) | 14,224 KB |
| example app with this plugin | 27,736 KB |
| increase | 13,512 KB (13.2 MiB) |
| of which `MapLibreNativeC.framework` | 12,852 KB |

This is the size of the app bundle, not the App Store download size, which Apple computes after compression and app thinning.

## Licenses and third-party notices

The package is licensed under the BSD 3-Clause License (`packages/flutter_mapigrade/LICENSE`, and an identical `LICENSE` at the repository root).

Apps built with the package show the notices of MapLibre Native FFI in Flutter's license registry, so `showLicensePage` lists them without code in the app (third-party-notices change). The FFI build installs the notices in `third_party/maplibre-native-ffi/<preset>/share/maplibre-native-c/`. `scripts/copy_ffi_notices.sh` copies them unchanged into `packages/flutter_mapigrade/notices/`, and the package registers one entry per file:

| File | Entry | Component | License | Platforms |
| --- | --- | --- | --- | --- |
| `LICENSE` | MapLibre Native FFI | MapLibre Native FFI | BSD 2-Clause | all |
| `licenses/maplibre-native.md` | MapLibre Native | MapLibre Native and the third-party code it includes (Boost, RapidJSON, earcut.hpp, protozero, geojson-vt-cpp and others; 1,347 lines) | BSD 2-Clause plus the listed notices | all |
| `licenses/icu.txt` | ICU | ICU | Unicode license | all |
| `licenses/fastpfor.txt` | FastPFOR | FastPFOR | Apache 2.0 | all |
| `licenses/nunicode.txt` | nunicode | nunicode | MIT | all |
| `licenses/pmtiles.txt` | PMTiles | PMTiles | BSD 3-Clause | all |
| `licenses/rust.md` | MapLibre Native FFI Rust crates | 62 Rust crates of the FFI's platform component, including `rustls-platform-verifier-android` | MIT, Apache 2.0, BSD, ISC, 0BSD, CDLA-Permissive-2.0, Unicode-3.0 | Android |
| `licenses/cxx-runtime.txt` | Android NDK C++ runtime | the NDK's C++ runtime | Apache 2.0 and the other licenses that the NDK's notice file lists | Android |

The Apple builds of the FFI (macOS and iOS) don't link its Rust platform component or the NDK's C++ runtime, so their apps neither contain nor list those two notices.

No review has been done of whether each license is acceptable for a given app, for example CDLA-Permissive-2.0 and Unicode-3.0 among the Rust crates. The notices are shown; their acceptability is the app's decision.

On the license page:

- "MapLibre Native FFI" appears above the alphabetical list. The page places the first package of the registry there, and the package registers its notices before `main` (design D95 of the third-party-notices change).
- The Markdown files (`maplibre-native.md`, `rust.md`) are shown as text, including headings, code fences and link syntax.
- Our "ICU" entry and the Flutter engine's "icu" entry are separate rows, because the page compares package names case-sensitively.

Size of the notices, measured on 2026-10-14 with release builds of the test harness, with and without the notice assets: the Android APK grew by 79,799 bytes (about 78 KB), and the macOS app bundle by 112 KB on disk (`du -sk`) and 29,482 bytes zipped.

Map data: the example uses OpenFreeMap tiles (OpenStreetMap data, ODbL) and the MapLibre demo tiles. The example does not show the attribution that OpenStreetMap data requires. A product must show it.

## Decisions and findings

### D3b instead of D3: one render texture and a GPU copy per frame

D3 rendered directly into the three IOSurface buffers and switched the session's target with `mln_metal_borrowed_texture_set_target()` before each frame. `set_target` was cheap (7.0 µs average, 893 µs maximum over 6,948 calls) and never caused `MLN_RENDER_RESULT_SIZE_PENDING`, but after each target change the renderer reported `needs_repaint` and the map published another render update, so with a static camera the map rendered about 880 frames per second and never stopped. With one render texture the map stops rendering after the style and tiles load. We chose D3b: MapLibre renders into one private `MTLTexture`, and each frame is copied with an `MTLBlitCommandEncoder` into a free IOSurface buffer. The copy took 0.40 ms per frame at 3200x2000 including the wait for completion. The full measurement is in design.md (D3).

The constant re-rendering after `set_target` may be worth reporting to MapLibre Native FFI. If it is fixed upstream, D3 would save the copy.

### Rendering is paced by the display

The map thread renders the next frame only after Flutter has taken the latest one (amendment to D4). Without this, during camera changes the map rendered about 1,200 frames per second, of which Flutter displayed about 120. The map is therefore at most one frame ahead of the display.

### `textureFrameAvailable:` needs the platform thread

The engine source asserts the platform thread in `Shell::OnPlatformViewMarkTextureFrameAvailable`, so the bridge dispatches `textureFrameAvailable:` to the main queue. We did not run this with a debug engine that has the assertions enabled. Details are in design.md (D4).

### Colors

Map colors match Flutter's within 1/255 per channel on macOS without setting a color space on the IOSurface (`benchmarks.md`, Color check). On the iPhone they match exactly: rendered to an image with `RepaintBoundary.toImage` (`packages/test_harness/integration_test/color_measurement.dart`), the map's fill and background and the Flutter swatches of the same colors had identical RGB values.

### Frame rate on the iPhone over dense areas

Over central London the iPhone 15 Pro Max displays 99 to 100 map frames per second at the median second (p10 87, lowest second 85) with rendering ahead (design D19), which meets the 60 fps target. Without it, the map waited for Flutter to take each frame before rendering the next, the GPU idled between frames, and iOS kept the GPU in its minimum performance state: `render_update` took about 17 ms and the median second had 40 frames (`benchmarks.md`, iPhone variants). Rendering ahead keeps the GPU busy, so it runs at higher clocks; this costs more power, and about 1% of rendered frames are replaced before Flutter displays them. The 5-minute run was measured before rendering ahead, so the thermal behavior with rendering ahead is not measured.

A render thread (design D2, alternative) did not help: the FFI waits for the GPU inside `render_update`, so it can only remove the map thread's work between frames, 0.1 ms. Rendering directly into the display buffers saves the copy (1.5 ms per frame on the iPhone); maps do this by default since 2026-10-11 (`copyFree`, design D20). On the Mac it made `render_update` about 0.7 ms longer, more than the 0.5 ms copy, and gave no consistent gain (`benchmarks.md`, 2026-10-11); `copyFree: false` keeps the copy. On the iPhone a copy-free frame costs about one refresh interval, so more rendered frames are replaced before Flutter displays them (7–9% against 3–5%); we accepted this, because counting those frames copy-free still spends less render time per displayed frame than the copy, and a 5-minute run showed no thermal difference.

### Rendering pauses in the background (iOS)

iOS doesn't allow GPU work in the background. The plugin pauses rendering when the app enters the background, waiting for a render in progress (at most 8.9 ms measured), and resumes it before the app enters the foreground (design D13). Over 23 transitions on the iPhone no frame was rendered in the background, and Metal API validation reported no errors. An app launched in the background, for example while the device is locked, receives no did-enter-background notification, so the plugin also pauses at registration if the app is in the background.

### Replaced display buffers stayed alive after resizes

Every resize allocates a new set of three display buffers. Until the fixes in design D18, the replaced buffers stayed alive until the map was disposed: on the iPhone the footprint went from 292 MiB to 696 MiB after 300 resizes, and a test run that started with the phone locked was terminated for using too much memory. Two causes were in the plugin and are fixed: the map thread had no autorelease pool, and the plugin wrapped its buffers through its own `CVMetalTextureCache`. The third is Flutter's Darwin texture cache, which keeps the buffers it has displayed until it has been idle for 1 s; the plugin works around it by telling Flutter once more that a frame is available 1.1 s after the last resize. After the fixes, the footprint is 246 MiB 2.5 s after the last of 300 resizes. During a burst of resizes Flutter's cache still holds the replaced buffers (the footprint reached 457 MiB during the 300 resizes). Details and a proposed Flutter fix: `docs/flutter-texture-cache-followup.md`.

### Memory warnings release little (iOS)

On a memory warning the plugin calls `mln_render_session_reduce_memory_use()` (design D14). Measured on the iPhone with the map full screen after visiting zoom levels 10 to 16 over San Francisco with the OpenFreeMap Liberty style (`packages/test_harness/integration_test/memory_measurement.dart`, 2026-10-10): the footprint was 236 MiB before the map was created and 396 MiB before the reduction, and 388 MiB 2 s and 389 MiB 7 s after it, so the reduction released about 8 MiB of the 160 MiB the map added. In MapLibre's source, the reduction clears the renderer's tile cache and unused images; the Metal context's `reduceMemoryUsage()` is empty.

The same measurement with copy-free maps (2026-10-11, debug builds, 2 runs per mode, alternating): copy-free, 391.6 MiB before the reduction (both runs) and 381.0–381.2 MiB 7 s after it; with the copy, 399.5–399.8 MiB before and 394.6–396.3 MiB after. A copy-free map has no private render texture (13.8 MiB at 1290x2796), and it used about 8 MiB less before the reduction and about 14 MiB less after it. The footprint before the map was created was 242.6–249.0 MiB in all runs.

### Alignment during camera changes (Stage 3)

The `flutter_map` layer (`MapLibreTextureLayer`, flutter-map-layer change) aligns the map with the overlays at rest within 0.1 logical px. During camera changes its compensating transform, built from the camera of the last displayed frame that Dart knew about, halved the error, but the map stayed one Flutter frame of movement off the overlays: 8.33 px at p50 during a pan at 1,000 px/s, on the Mac and on the iPhone. In about 79% of frames (77.6–87.2% over all pan phases and runs) Flutter displayed a newer map frame than the one the transform was built for. A screen capture confirmed the computed error. The transform also uncovered strips at the viewport edges, 16 px wide at 1,000 px/s. Results are in `benchmarks.md`; the decision is in the change's design (Results and decision), and the options are in `docs/camera-alignment-options.md`. We accepted this behavior for Stage 3 (2026-10-11). Since the camera-prediction-default change the transform was no longer the layer's default (Camera prediction, below), and on 2026-10-12 we removed it (remove-camera-transform change), because it was the only part of the layer that needed the camera of the frame Flutter displays, which Android can't report exactly.

### Camera prediction (camera-prediction change)

`MapigradeLayer`'s `alignment` parameter selects how the layer aligns the map with the overlays during camera changes: `LayerAlignment.prediction(lead: n)` sets the camera extrapolated n display refresh intervals ahead from its recent velocity; `LayerAlignment.none` sets the current camera (the public-api change renamed `MapLibreTextureLayer` and `CameraAlignment` to these names). The layer draws the map without a transform in both cases. The default is prediction with a lead of 1 (camera-prediction-default change). With a lead of 1, the map uncovers no strips at the edges and, in pans at 1,000 px/s, lags the overlays by 4.2–5.5 px on average on the Mac and 7.9 px on the iPhone (p50 0 or 8.33 px on the Mac, 8.33 px on the iPhone). It runs ahead of them by 7–8 px after an abrupt stop and by 22–25 px after an abrupt reversal. In a manual check on both devices it felt better than the transform, and the overlays floated only while a fling decelerated. We decided on 2026-10-11 to make a lead of 1 the default. Results are in `benchmarks.md`, the decision in the camera-prediction change's design.

## Known limitations

- arm64 only: the FFI presets are `macos-arm64-metal`, `ios-arm64-metal` and `ios-simulator-arm64-metal`, so the iOS simulator works only on Apple-silicon Macs. The macOS example sets `ARCHS = arm64`, and the iOS example excludes `x86_64` from simulator builds. On Android the plugin packages `libflutter_mapigrade.so` for `arm64-v8a` only. On a device without an arm64 ABI, the plugin logs a warning that names the device's ABIs and calls no native code, the app starts, `MapigradeLayer.isSupported` is false, and a `MapigradeLayer` reports a `LayerCreateException` (unsupported-architectures change). `packages/test_harness/integration_test/unsupported_test.dart` checks this on an arm64 device with an APK built without the library; a 32-bit device was not tested.
- iOS 15.5 or later, the FFI's iOS deployment target.
- Swift Package Manager only: the plugin has no podspec.
- One Flutter engine per process: the plugin keeps the texture registry of the engine that registered it last.
- The map's sprite and glyph density is fixed when the map is created (`mln_map_options.scale_factor`). After a device pixel ratio change the map renders at the new ratio, but MapLibre logs a warning and keeps sprites at the original density. A map recreated at the new ratio would fix this.
- We did not test moving the window between displays with different pixel ratios, because only one display was available. Resizing was tested by resizing the map widget on every frame for 10 s in an integration test, and by dragging the example window's edge for about 10 s by hand; after the drag the map filled the window at the correct scale.
- During camera changes the map in the `flutter_map` layer, with its default alignment, trails the overlays in steady pans by up to about one Flutter frame of movement (4.2–7.9 logical px on average at 1,000 px/s), runs ahead of them briefly after an abrupt stop (7–8 px) or reversal (22–25 px), and the overlays appear to float while a fling decelerates (see Camera prediction).
- Camera prediction was measured only on 120 Hz displays. At 60 Hz a lead of 1 refresh interval is twice as long, and how far the map lags at that rate isn't known.
- The alignment during camera changes was checked against the screen only on the Mac and only with the transform (screen capture), which has since been removed. For camera prediction only the computed error exists.
- With camera prediction, the best lead in the synthetic benchmark differed by device (1 on the Mac, 2 on the iPhone), and on the iPhone the benchmark's best lead felt worse in a manual check than a lead of 1. The cause is unknown.
- `render_update` waits on the map thread until the GPU completes, so a frame's CPU encoding and GPU work can't overlap with the next frame's. On the iPhone, rendering ahead keeps the frame rate at about 100 fps over central London despite this (see Frame rate on the iPhone over dense areas).
- The iOS GPU's clock depends on how busy it is, and the paced map settled in its minimum performance state. Rendering ahead only applies while a frame costs more than a refresh interval; a map whose frames cost slightly less than that is paced and may run at low clocks.
- During a burst of resizes, Flutter's texture cache keeps the replaced display buffers until the resizing stops (see Replaced display buffers stayed alive after resizes). A continuous resize that lasts long, such as dragging a desktop window edge, holds memory for as long as it lasts.
- The plugin exposes only style, camera (center, zoom, bearing), resize and dispose. There are no gestures, pitch or animations.

## What the Android slice can reuse

- `src/core/` as is: the map thread, command queue, camera coalescing, buffer state, pacing, events and the C ABI, and from the iOS slice the pause gate (`render_gate.h`, `SetAllPaused`), the memory reduction command (`ReduceAllMemoryUse`) and the platform scope hook (`RunInPlatformScope`, which can be empty on Android). The Android bridge drives pause and memory reduction from its own lifecycle callbacks.
- The Dart API (`lib/src/texture/`) and the test hooks (`package:flutter_mapigrade/testing.dart`) as is.
- The integration tests, including the lifecycle tests (pause, dispose while paused, memory reduction) and the released-buffer test, which needs an Android implementation of `map_texture_released_buffers_alive_for_testing`.
- The measurement procedure (`packages/test_harness/lib/benchmark.dart`, including the 5-minute mode) and the memory and color measurements in `packages/test_harness/integration_test/`.
- `MaybeNotifyAfterResize()` is a workaround for Flutter's Darwin embedders; check whether Android's `SurfaceProducer` path needs it before keeping it there.
