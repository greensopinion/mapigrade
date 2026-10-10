## 1. Pinned MapLibre Native FFI build

- [x] 1.1 Create the repository layout from design D8 (`packages/`, `example/`, `scripts/`, `third_party/` gitignored) and verify `git status` shows only the intended new files
- [x] 1.2 Write `scripts/build_maplibre_ffi.sh` that clones MapLibre Native FFI at commit `dd97d20f8fab6990cd87c13f091ce00e662707bd` and builds the `macos-arm64-metal` preset into `third_party/maplibre-native-ffi/`; verify that a clean run produces the dynamic library and `include/maplibre_native_c.h`, and record the commands, build time and library size in the README
- [x] 1.3 Build and run the upstream `examples/c-map` (or the closest macOS Metal example) against the pinned build and verify that it shows a map, which confirms that the build works before Flutter is involved

## 2. Plugin scaffold and packaging

- [x] 2.1 Create the Flutter plugin `packages/flutter_map_maplibre_texture` (macOS only) with the `lib/src/texture/` and `lib/src/layer/` layout from D8 and the `example/` app; record the Flutter version and the plugin's native build integration (CocoaPods or Swift Package Manager); verify that `flutter build macos` succeeds for the example
- [x] 2.2 Link the plugin against the pinned FFI library and embed it in the app bundle; verify with `otool -L` that the library resolves inside the bundle, and that a release build runs after copying the `.app` outside the build directory

## 3. Metal bridge feasibility (do before the full core)

- [x] 3.1 Implement the set of three IOSurface-backed `CVPixelBuffer`s (`kCVPixelFormatType_32BGRA`) with `CVMetalTextureCache` textures, and a `FlutterTexture` that returns the latest buffer; verify that the example's `Texture` widget shows a solid color cleared by Metal into the buffer
- [x] 3.2 On a dedicated native thread, create a runtime and map, load a fixed style, attach `mln_metal_borrowed_texture_attach()` to one buffer, and render; verify that the map appears in the `Texture` widget
- [x] 3.3 Measure `mln_metal_borrowed_texture_set_target()` with an unchanged size, switching among the three buffers per frame: record its duration and whether `render_update` returns `MLN_RENDER_RESULT_SIZE_PENDING` afterward; decide between D3 and D3b and record the decision with the numbers in design.md
- [x] 3.4 Determine whether the macOS embedder allows `textureFrameAvailable:` from the map thread (documentation, then a test with thread assertions enabled); record the result in design.md and use a main-queue dispatch if it doesn't
- [x] 3.5 Check the rendered colors against a style with known fill colors and verify that they match within a tolerance of 2/255 per channel; set the IOSurface color space explicitly if they don't

## 4. Native core (`src/core/`)

- [x] 4.1 Implement the map thread loop from D2 with a wake source, an ordered command queue (style, resize, dispose) and a latest-value camera slot; add C++ unit tests (no MapLibre) for queue ordering and camera coalescing, and verify that they pass
- [x] 4.2 Implement the buffer state (latest, presented, free) from D3/D4, including skipping a render when no buffer is free; add unit tests for the state transitions and verify that they pass
- [x] 4.3 Forward the selected events (style loaded, loading failed with message, render error, idle) and the frame-displayed event with the camera from `mln_render_session_projection_create()`/`mln_map_projection_get_camera()`; verify in the example log that each displayed frame id has a camera
- [x] 4.4 Implement resize and device pixel ratio changes from D7, coalescing consecutive resizes; verify by dragging the window edge for 10 seconds without a crash or a stretched frame, and, if a second display is available, by moving the window between displays with different pixel ratios
- [x] 4.5 Implement dispose: stop the thread, destroy the session, map, runtime and wake source in order, release the buffers, and unregister the texture; verify that calls after dispose return an error status

## 5. Dart API (`packages/flutter_map_maplibre_texture/lib/src/texture/`)

- [x] 5.1 Define the C ABI and its `@Native` bindings; verify that `flutter analyze` passes and that a smoke test calls create and dispose
- [x] 5.2 Implement the controller: `loadStyleUrl`, `loadStyleJson`, `setCamera` (center, zoom, bearing), `resize`, `dispose`, an event stream (style loaded, load failure, render error, idle), a frame-camera stream, and errors for calls after dispose, with events delivered through `NativeCallable.listener`; verify with the integration tests in 7.1
- [x] 5.3 Implement the widget: `LayoutBuilder` plus `MediaQuery.devicePixelRatio` sends resize commands, and the widget builds `Texture(textureId:)`; verify that the map fills the widget bounds in the example
- [x] 5.4 Add a test that fails if any file under `lib/src/texture/` imports `package:flutter_map` (D9); verify that it passes, and that it fails when such an import is added temporarily

## 6. Example app

- [x] 6.1 Build the example screen: the map widget in a `Stack` with a Flutter control panel above it (zoom, bearing and pan buttons, a style switch, a "continuous pan" toggle that changes the camera on every Flutter frame); use a public style that needs no API key (for example OpenFreeMap Liberty for measurements and MapLibre demo tiles for smoke tests); verify that the panel is drawn above the map and that its buttons respond
- [x] 6.2 Add an invalid style URL option and show the reported failure message in the UI; verify that the app keeps running

## 7. Verification and measurement

- [x] 7.1 Write macOS integration tests (`flutter test integration_test -d macos`) for the spec scenarios: style loads, style fails, style replaced, camera change shows up in the frame camera, rapid camera updates don't build up a backlog, call after dispose, 50 create/dispose cycles with a stable thread count, dispose while rendering; verify that they all pass
- [x] 7.2 Verify the idle scenario: after the map reaches idle, the native rendered-frame counter doesn't increase over 10 seconds
- [x] 7.3 Verify no CPU readback: confirm that the source doesn't call `mln_texture_read_premultiplied_rgba8`, `getBytes`, or `CVPixelBufferLockBaseAddress` on the frame path, and capture a Metal System Trace during continuous pan that shows no readback; record the evidence
- [x] 7.4 Run the frame rate scenario (30 s continuous pan, 1600x1000 logical window, cached area) in a release build and record the median, p95 and p99 frame durations, the displayed map frame rate, `render_update` and GPU time, and skipped renders in `benchmarks.md`, with the machine, macOS, Flutter and FFI versions; state the result against the 30 fps minimum and the 60 fps target

## 8. Documentation

- [x] 8.1 Write the README: architecture (threading diagram, frame path), pinned versions, prerequisites and exact build and run commands; verify by following it from a clean clone
- [x] 8.2 Write `limitations.md`: app bundle size increase, MapLibre Native and FFI licenses and third-party notices, known blockers, and what the iOS slice can reuse; include the D3/D3b decision and the measured numbers
