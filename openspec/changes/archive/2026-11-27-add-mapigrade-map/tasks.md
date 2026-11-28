## 1. Recognizer threads

- [x] 1.1 Find out from mln-rs's source or its maintainers which threads may call `mln_gesture_recognizer_handle` and `mln_gesture_recognizer_tick`, and whether a call blocks on the map; record the answer and the path that D237 then takes in this task
  - Answer, from mln-rs 71769bb (the pinned FFI's submodule): any thread may call them. `crates/mln_c/src/gesture.rs` keeps each recognizer behind its own `parking_lot::Mutex` ("calls run on the caller's thread"). The recognizer reads the camera, viewport and zoom range from `Map::snapshot()`, which copies the snapshot that the runtime's thread last published under a short lock, and sends its moves with `Map::apply_camera_delta` and `Map::update_camera`, which post commands to the runtime's thread and return without waiting (`crates/mln_runtime/src/gestures.rs`, `crates/mln_runtime/src/map.rs`). A call therefore doesn't wait for the map's work; it waits only for the recognizer's lock and the snapshot copy.
  - Path: D237's primary path. The input adapter calls handle and tick on the platform thread, and the result returns synchronously. The fallback queue isn't needed.

## 2. Native core

- [x] 2.1 Add the mode of D235 in which the map owns its camera: the map is created at an initial camera and limits, and the camera slot is never submitted; verify with a native test that a map in that mode renders its initial camera and that no camera command from the slot reaches the FFI
- [x] 2.2 Add the C ABI functions for jump, ease, fly, fit to bounds, cancel and limits, through the command queue, with an event that reports each command's outcome with its request id (D236); verify with native tests that a jump reports `completed`, a cancelled ease reports `cancelled`, and limits keep a jump within the bounds
- [x] 2.3 Add the C ABI functions that create the gesture recognizer with options, pass one input, tick, and change the options, on the thread that task 1.1 allows (D237, D240); verify with a native test that a sequence of pointer inputs for a drag moves the camera by the drag's distance on a flat map
- [x] 2.4 Return the frame's matrix, the camera fields of D247 and the clip depth convention from `map_texture_select_newest` and in the frame reports, and the source of the last camera change that each frame includes (D241, D243, D247); verify with a native test that the returned matrix equals the frame result's `frame_projection`
  - Native tests `OwnedMapRendersItsInitialCamera`, `JumpReportsCompleted`, `CancelledEaseReportsCancelled` (also `replaced`), `LimitsKeepJumpWithinBounds`, `FitBoundsWithoutRoomIsCancelled`, `DragMovesCameraByItsDistance`, `TapIsReportedByRecognizer` and `FrameReportsItsMatrix` pass on the Mac.
  - Changes to D243, found while implementing: mln-rs ends every camera command with a did-change event that carries that command's mode, so "a did-change event that isn't animated" never arrives after an ease. The map thread instead reports `MAP_TEXTURE_EVENT_CAMERA_SETTLED` after a camera event once the map snapshot shows no transition and no gesture in progress, with the snapshot's latest render update generation; Dart's rest condition "a frame with that camera has been displayed" compares frames' `map_update_generation` with it. Camera events carry a snapshot generation and frame results only a render update generation, so a frame can't be joined to the event that moved it: each frame reports the source of the last camera event that the runtime delivered before the frame's result was handled, which can name the previous source for one frame when the source changes.

## 3. Camera API

- [x] 3.1 Add `Mapigrade` with `isSupported` and `maximumCacheSizeBytes`, and make `MapigradeLayer`'s static members delegate to it through the integration library (D244); verify with unit tests that a value set through either class reads the same through the other
- [x] 3.2 Add the values `MapigradeCamera` with the fields of D247, `GeoBounds`, `CameraLimits`, `CameraChange`, `CameraChangeSource` and `CameraTransitionOutcome`; verify with unit tests of equality, of fields that a command may omit, including a command camera that sets only the padding, and of invalid limits
- [x] 3.3 Add `MapigradeCameraController` with its attach rules, `camera`, the commands and the two streams (D236, D243); verify with unit tests on a fake map controller that commands complete with the reported outcome, that calls while detached fail with a `StateError`, and that the rest stream emits once per rest

## 4. Widget and frame projection

- [x] 4.1 Add `MapigradeMap`: style URL or JSON, initial camera, limits, header rules, metrics, `onStyleLoaded`, failure callback, both controllers, children, and the `MapigradeCreateException` path where `Mapigrade.isSupported` is false (D235); verify with widget tests on a fake map controller and with `unsupported_platform_test.dart`
- [x] 4.2 Add `MapigradeFrame` with the projection of D241 and the inherited model of D242; verify with unit tests that a coordinate round-trips within 0.5 logical pixels at pitch 0, 45 and 80, that a coordinate behind the camera has no position, and that the copy of the world nearest the center is chosen
- [x] 4.3 Make `MapigradeMap` provide an overlay host and an `OverlayChildIndex` to its children, and attach a `MapigradeController` with the displayed frame's camera; verify that a `MapigradePolylineLayer` and a feature query work in a widget test on a fake map controller

## 5. Gestures

- [x] 5.1 Write the gesture arena member of D238 with a fake recognizer that records inputs; verify with adapter unit tests: a marker's tap wins, a vertical drag in a `ListView` goes to one recognizer, a two-finger gesture in a list goes to the map, a disabled part releases its pointer, and the kept events are replayed in order on a win
- [x] 5.2 Map trackpad `PointerPanZoom` events, the mouse wheel through `PointerSignalResolver`, Shift, Ctrl and the right button, and the keyboard through `Focus` (D238); verify with adapter unit tests of the inputs each produces, and that a wheel event over the map doesn't scroll an enclosing list
- [x] 5.3 Add the tap callbacks with the double-tap delay of D239, and haptic feedback and the box zoom rectangle of D245; verify with adapter unit tests of taps 290 ms and 310 ms apart, a double tap that calls no `onTap`, a pan that calls no `onTap`, and a notch that plays feedback once
- [x] 5.4 Map `MapigradeGestures` to the recognizer's options and create the recognizer with each platform's momentum (D240); verify with unit tests of the options passed for each part and for iOS, macOS and Android
  - Unit tests in `packages/mapigrade/test/map/map_gestures_test.dart` pass. Open for the manual checks of group 10: the size of a mouse wheel detent is taken as 20 logical pixels, the multiplier of Flutter's macOS embedder for a wheel's line delta, which task 10.2 checks; the arrow keys move the view (the right arrow moves the content 100 pixels to the left), and Shift with the right arrow turns the bearing clockwise.

## 6. Markers

- [x] 6.1 Write `MapigradeMarkers` and `MapigradeMarker` with the render object of D242: layout with loose constraints, upright placement by alignment, perspective scaling, far markers behind near ones, one copy of the world; verify with widget tests that a child's build isn't called while frames change, and that two overlapping markers paint in order of distance
- [x] 6.2 Add the pitch and rotation alignments `map` (D242); verify with widget tests that a ground marker's painted corners equal the projections of its ground corners within 0.5 logical pixels, and that a tap on a ground marker reaches its child
- [x] 6.3 Hide markers behind the camera, beyond the visible ground and off screen, keeping them mounted (D242); verify with widget tests that a hidden marker isn't painted or hit, and that a child's `State` survives leaving and returning to the screen

## 7. Integration tests

- [x] 7.1 Add integration tests driven by the camera controller: initial camera with pitch, roll and padding, commands and their outcomes, limits, the camera streams, children and markers at the frame camera under pitch, the frame projection against the FFI projection, hidden markers, polylines and feature queries in a `MapigradeMap`; verify that they pass on macOS, the iOS simulator and the Android emulator
- [x] 7.2 Add integration tests from gesture to camera with glides off: a drag pans by its distance on the ground, a pinch zooms by its scale, a tap reports the coordinate that the displayed frame draws at its position; verify that they pass on macOS, the iOS simulator and the Android emulator
- [x] 7.3 Run the integration tests of tasks 7.1 and 7.2 on the iPhone and the Pixel; verify that they pass, and record each failure
  - `packages/test_harness/integration_test/mapigrade_map_test.dart`, 12 tests, passed on 2026-11-27 on macOS, the iOS simulator (iOS 27.2), the Android emulator (`mapigrade-api37`), the iPhone (`flutter drive --profile`) and the Pixel 4a (5G). No failures to record.
  - The frame projection is compared with the FFI's projection through a new test hook, `map_texture_project_for_testing`, which projects with the view of the last rendered frame.
  - The pinch test expects the zoom of the spread from 105 to 200 pixels, not from 100: the recognizer decides whether two fingers tilt once both have moved 2 pixels (`PITCH_DECIDE_PX` in mln-rs), and that move doesn't zoom.

## 8. Benchmarks

- [x] 8.1 Add an alignment benchmark for `MapigradeMap` that measures markers against the displayed frame during commanded camera motion, and run it on the Mac, the iPhone and the Pixel; verify that the drawn error is within 1 logical pixel, and add the results to `docs/benchmarks.md`
- [x] 8.2 Measure the latency from a pointer event to the first displayed frame that includes its camera movement, on the iPhone and the Pixel; add the results to `docs/benchmarks.md`
- [x] 8.3 Measure the frame rate of a pan with 100 and 1,000 markers, against the same pan with no markers, on the Mac, the iPhone and the Pixel; add the results to `docs/benchmarks.md`
  - `packages/test_harness/lib/map_benchmark.dart`, run on 2026-11-27 at pitch 0 and 60 on the Mac, the iPhone 15 Pro Max, the iPhone 13 and the Pixel 4a (5G); results in `docs/benchmarks.md`, section "MapigradeMap". The drawn error was at most 0.03 logical pixels on the Mac and the iPhones. The Pixel reports no display times, so its drawn error isn't measured, and at pitch 60 it renders at 25 to 35 map frames per second (53 to 57 at pitch 0).
- [x] 8.4 Run the frame-rate and alignment benchmarks of `MapigradeLayer` on the Mac, `main` against this branch, 3 alternating runs of each, and add a section to `docs/benchmarks.md`, for the move to the mln-rs-based FFI (moved from task 6.1 of `port-ffi-gesture-recognizer`); verify that the section states the builds, the conditions and the ranges over 3 runs
  - Run on 2026-11-27, alternating `main` (`bd1f066`, FFI 0.202610.3) and this branch (mln-rs-based FFI `4371ff6`); section "`MapigradeLayer` with the mln-rs-based FFI" in `docs/benchmarks.md`. No regression: this branch displayed 119.3 to 119.5 map frames per second against 100.7 to 112.0, `render_update` was 5.38 to 5.44 ms against 6.81 to 7.03 ms, and the drawn error was 0 px in both.
- [x] 8.5 Present the Mac results of task 8.4 to the user, and ask whether the iPhones and the Pixel run those benchmarks; record the decision in this task (moved from task 6.2 of `port-ffi-gesture-recognizer`)
  - Decision (user, 2026-11-27): the Mac is enough; the iPhones and the Pixel don't run these benchmarks.
- [x] 8.6 Present the results of tasks 8.1 to 8.3 to the user; record the decisions in this task
  - Decision (user, 2026-11-27): don't follow up the Pixel's frame rate at pitch 60 (25 to 35 map frames per second); we assume a limit of its hardware, and record the numbers as measured.

## 9. Example and demo

- [x] 9.1 Add `packages/mapigrade/example/` with a `MapigradeMap` at a pitched initial camera and a `MapigradeMarker`, importing only `package:mapigrade/mapigrade.dart`; verify that it runs on macOS, the iOS simulator and the Android emulator with the marker at its coordinate
  - Ran on 2026-11-27 (debug builds) on macOS, the iOS simulator and the Android emulator (`mapigrade-api37`): central Vancouver at pitch 50 and bearing 30, with the pin at 49.2827, -123.1207 on each, checked in screenshots. The platform folders are copies of `flutter_mapigrade`'s example with the identifiers renamed, without its stale Xcode reference to `darwin/flutter_mapigrade`. The example is in the root workspace.
- [x] 9.2 Add the "Pitch and markers" showcase to the demo and the gallery, and one sentence about it to `packages/demo/README.md`; verify by running the demo on macOS and the Pixel and trying each scenario of the requirement "Pitch and markers"
  - `packages/demo/lib/src/pitch/pitch_screen.dart`: Chamonix at pitch 50 in Liberty, upright pins at five peaks, made-up wind arrows on the ground, a switch for perspective scaling, Flat and Pitched buttons that fly, the camera readout from `cameraChanges`, the tap's coordinate and the name of the topmost feature, and a pin dropped by a long press. `MapigradeMap` can't use `flutter_map`'s `RichAttributionWidget`, so the screen shows the attribution as links, from the new `attributionEntriesOf` in `common/styles.dart`. The demo's README also names `package:mapigrade/mapigrade.dart` as a library it uses.
  - Decision (user, 2026-11-27): verify on the Mac only, not on the Pixel. The user tried the scenarios on the Mac in a debug build on 2026-11-27, and they worked.

## 10. Manual checks on devices

- [ ] 10.1 With the user, check on the iPhone and the Pixel the feel of flings, pinches and the snap to north, whether the replayed pointer events make the map jump when it wins the arena, and the haptic feedback, with the "Pitch and markers" showcase of the demo; record the outcome and any change to D238 or D240 in this task
  - Skipped for now (user, 2026-11-27).
- [x] 10.2 With the user, check on the Mac the trackpad scroll and pinch, the mouse wheel, the right-drag, the box zoom and the keyboard, with the "Pitch and markers" showcase of the demo; record the outcome in this task
  - Found while verifying task 9.2: a Ctrl-drag turns the map with the drag on the lower half of the map and against it on the upper half. This is intended: the recognizer turns the bearing by the horizontal movement only (0.5 degrees per pixel, `drag_step` in mln-rs `crates/mln_gestures/src/recognizer.rs`), as MapLibre GL JS does, and a larger bearing turns the map counterclockwise around the center.
  - Checked by the user on 2026-11-27 with the trackpad and the keyboard: no finding besides the Ctrl-drag direction above. No mouse was available, so the mouse wheel (including the 20-pixel detent of task 5.4) and the right-drag weren't checked.

## 11. Documentation

- [x] 11.1 Write the `MapigradeMap` sections of `mapigrade`'s README: placing the map, the two controllers, camera commands, markers, taps and gestures; verify by reading it
  - Sections "Placing the map", "Controllers", "Camera commands", "Markers" and "Taps and gestures", before "Supported platforms".
- [x] 11.2 Update `docs/architecture.md` (the camera owned by the map, the input path, the frame projection), `docs/limitations.md` (no terrain occlusion of markers, no web, no globe) and the unreleased CHANGELOG entries of both packages; verify by reading each changed section
  - `docs/architecture.md` has a new section "`MapigradeMap`". In `docs/limitations.md`, the last known limitation ("no gestures, pitch or animations") was out of date; it is replaced by one about `MapigradeLayer` and three about `MapigradeMap` (terrain and globe, web, mounted markers), and the web limitation names `Mapigrade.isSupported`.
- [x] 11.3 Add a section to the repository root `README.md` that helps the reader decide between `flutter_mapigrade` (`MapigradeLayer` in a `flutter_map` map) and `mapigrade` (`MapigradeMap`); verify by reading it
  - Section "Choosing a package". Decision (user, 2026-11-27): cite alternatives without comparing them, and no commercial packages; it cites `maplibre_gl`, `maplibre` and `vector_map_tiles`. The README's first sentence, the "Use Mapigrade in your app" line and the repository layout now name `mapigrade` and `MapigradeMap` too.
- [x] 11.4 Review the exports of `mapigrade` for internal types that its main library exports by accident, and the exports of `flutter_mapigrade` for internal types or `mapigrade` types that it exports by accident, beyond the names of the `package-api` requirement "Exported names"; record each finding and its fix in this task
  - `mapigrade`: `MapigradeFrame` had public members that only the package and its tests use: `fromFrame`, which takes the internal `FrameCamera`, `forTesting`, `matrix`, `clipOf`, `clipOfWorld`, `clipOfWorldPoint`, `positionOfClip`, `withinDepth`, `worldOf`, `worldSizeInPixels` and `centerWorld`. Fix: they moved to the extension `MapigradeFrameInternals` in the same file, which the main library doesn't export and `src/testing.dart` does, as `OverlayPlacementNative` does for `OverlayPlacement`.
  - `mapigrade`, kept: `MapigradeMap.createState` returns `MapigradeMapState` and `MapigradeMarkers.createRenderObject` returns `RenderMapigradeMarkers`, which the main library doesn't export; applications can't name them, and the tests reach them through `src/testing.dart`.
  - `flutter_mapigrade`: no finding. `MapigradeLayer` and `LayerAlignment` have no public member of an internal type.
  - `flutter analyze` found no issues; the unit tests of both packages pass, except `ffi_pins_test.dart` "the lock file names an FFI release", which fails because the pin is a commit without a release (design D219 of `port-ffi-gesture-recognizer`).
