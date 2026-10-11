## 1. Verify the timing assumptions (D24, D25)

- [x] 1.1 Find in the Flutter 3.47.5 engine source which clock `FrameTiming` timestamps use on macOS and iOS, and whether a plugin can read the same clock; verify with a probe in the example that a native timestamp taken in `copyPixelBuffer` falls between `rasterStart` and `rasterFinish` of a `FrameTiming` for at least 95% of displayed frames during a pan on macOS; record the clock and the probe result in design.md (D24), and choose the fallback from D24 if the clocks differ
- [x] 1.2 Check that `SchedulerBinding.currentSystemFrameTimeStamp` in a persistent frame callback equals `FrameTiming.vsyncStart` of the same frame; verify with a probe that logs both for 300 frames during a pan on macOS and on the iPhone that each build matches exactly one `FrameTiming`; record the result in design.md (D25), and switch to another matching method if they don't match (they didn't; we chose matching by engine frame number, see D25)

## 2. Dependency and display time

- [x] 2.1 Check pub.dev for the newest `flutter_map` release, add it at an exact version (at least 8.3.1) to `packages/flutter_mapigrade/pubspec.yaml` and to the example, and record the version in design.md (D30); verify that `flutter pub get`, `flutter analyze` and the boundary test (`test/texture_boundary_test.dart`) pass
- [x] 2.2 Record the display time in `MapTexture::Present()` on the clock chosen in 1.1, add it to the frame-displayed event in the C ABI, and expose it as `FrameCamera.displayTime`; verify with a native unit test that the time is set for every frame-displayed event, and with the integration test `map_texture_test.dart` on macOS that `displayTime` increases from frame to frame

## 3. Layer (D21, D22, D23)

- [x] 3.1 Implement the camera conversion (D22) and the transform `T(R -> C)` (D23) as pure Dart functions in `lib/src/layer/`; verify with unit tests: identity for equal cameras; a pure pan maps a point by the expected offset; a zoom difference of 1 scales by 2 about the viewport center; a bearing difference rotates in the direction D22 gives; a pan across the antimeridian uses the shorter longitude difference; a frame with a different viewport size is placed by its own center
- [x] 3.2 Implement `MapLibreTextureLayer` (D21): creates and disposes its controller, loads the style, sets the converted camera during build when it changes, and wraps the texture in `ClipRect` and the transform from 3.1 using `controller.displayedFrame`; verify with a widget test that the layer is a child of `FlutterMap`, that markers after it are drawn above it, and that removing it disposes the controller
- [x] 3.3 Add a `flutter_map` page to the example with the layer, a `MarkerLayer` and a `PolylineLayer`, and pan, pinch-zoom and rotate gestures enabled; verify by running it on macOS and on the iPhone that the map follows the gestures and that the overlays are drawn above it
- [x] 3.4 Extend the insert/remove lifecycle test to the layer; verify on macOS that inserting and removing the layer 50 times returns the thread count to its starting value and keeps memory use bounded

## 4. Static alignment (D27)

- [x] 4.1 Write the integration test from D27 (JSON style with a GeoJSON point drawn as a circle, a `CircleMarker` at the same coordinate, two captures with `RepaintBoundary.toImage`, color centroids) for the cases in the spec: integer and fractional zoom, rotation 30 degrees, latitude 80 degrees, within 1 degree of the antimeridian, after a resize; verify that all cases pass on macOS and on the iOS simulator with at most 1 logical pixel between the centers, and if a case fails, fix the conversion or record the cause before continuing

## 5. Alignment measurement (D25, D26, D28)

- [x] 5.1 Implement the error computation from D26 as a pure Dart function over (C_N, k_used, k_shown and their cameras); verify with unit tests that the error with the transform is 0 when k_shown = k_used, and that a known camera difference between k_shown and k_used gives the expected error in logical pixels
- [x] 5.2 Implement the recording and matching from D25 in the example (persistent frame callback, timings callback, display events, matching by frame number after the run, count of unmatched frames); verify on macOS that at least 95% of Flutter frames in a 30 s pan are matched
- [x] 5.3 Add the alignment benchmark phases from D28 (pans at 100, 500, 1,000 and 2,000 logical px/s, zoom at 1 level per second, rotation at 90 degrees per second), moving the camera through `MapController`, with one result line per phase as in `benchmark.dart`; verify that a run on macOS prints a line for each phase with the speed, the mismatch fraction, the matched-frame count and the p50, p95 and largest error with and without the transform

## 6. Measurements

- [x] 6.1 Run the alignment benchmark on the reference Mac in release mode, three runs; record the results in `benchmarks.md` with the conditions that `benchmarks.md` already records for each run, plus the `flutter_map` version
- [x] 6.2 Run the alignment benchmark on the reference iPhone in release mode, three runs, with Auto-Lock off; record the results in `benchmarks.md`, and check that the displayed map frame rate during the 100 px/s pan isn't lower than in the Stage 2 benchmark, so that the layer doesn't slow down rendering
- [x] 6.3 Do the screen capture check from D29 on the reference Mac during the 1,000 px/s pan (video mode of the alignment benchmark, ScreenCaptureKit at 120 Hz, automatic measurement of every captured frame); verify that the distance at rest is below 1 logical pixel; record the measured disc-to-dot distances away from the viewport edges, compare them with the error the benchmark computes in the same run, and record the width of the uncovered edge strips; if the capture and the computed error disagree by more than 2 logical pixels at p50, find the cause before 7.1

## 7. Decision

- [x] 7.1 Record in design.md and in `limitations.md` the alignment results, the alignment threshold we set from them, and whether per-buffer textures (and overscan) are needed; record the Stage 3 decision for model A (continue with the last-reported-frame transform, continue with per-buffer textures, or consider model B) in the Decision column of the roadmap in `docs/maplibre-native-ffi-flutter-texture-concept.md`
