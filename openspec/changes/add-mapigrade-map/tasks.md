## 1. Recognizer threads

- [ ] 1.1 Find out from mln-rs's source or its maintainers which threads may call `mln_gesture_recognizer_handle` and `mln_gesture_recognizer_tick`, and whether a call blocks on the map; record the answer and the path that D237 then takes in this task

## 2. Native core

- [ ] 2.1 Add the mode of D235 in which the map owns its camera: the map is created at an initial camera and limits, and the camera slot is never submitted; verify with a native test that a map in that mode renders its initial camera and that no camera command from the slot reaches the FFI
- [ ] 2.2 Add the C ABI functions for jump, ease, fly, fit to bounds, cancel and limits, through the command queue, with an event that reports each command's outcome with its request id (D236); verify with native tests that a jump reports `completed`, a cancelled ease reports `cancelled`, and limits keep a jump within the bounds
- [ ] 2.3 Add the C ABI functions that create the gesture recognizer with options, pass one input, tick, and change the options, on the thread that task 1.1 allows (D237, D240); verify with a native test that a sequence of pointer inputs for a drag moves the camera by the drag's distance on a flat map
- [ ] 2.4 Return the frame's matrix, the camera fields of D247 and the clip depth convention from `map_texture_select_newest` and in the frame reports, and the source of the last camera change that each frame includes (D241, D243, D247); verify with a native test that the returned matrix equals the frame result's `frame_projection`

## 3. Camera API

- [ ] 3.1 Add `Mapigrade` with `isSupported` and `maximumCacheSizeBytes`, and make `MapigradeLayer`'s static members delegate to it through the integration library (D244); verify with unit tests that a value set through either class reads the same through the other
- [ ] 3.2 Add the values `MapigradeCamera` with the fields of D247, `GeoBounds`, `CameraLimits`, `CameraChange`, `CameraChangeSource` and `CameraTransitionOutcome`; verify with unit tests of equality, of fields that a command may omit, including a command camera that sets only the padding, and of invalid limits
- [ ] 3.3 Add `MapigradeCameraController` with its attach rules, `camera`, the commands and the two streams (D236, D243); verify with unit tests on a fake map controller that commands complete with the reported outcome, that calls while detached fail with a `StateError`, and that the rest stream emits once per rest

## 4. Widget and frame projection

- [ ] 4.1 Add `MapigradeMap`: style URL or JSON, initial camera, limits, header rules, metrics, `onStyleLoaded`, failure callback, both controllers, children, and the `MapigradeCreateException` path where `Mapigrade.isSupported` is false (D235); verify with widget tests on a fake map controller and with `unsupported_platform_test.dart`
- [ ] 4.2 Add `MapigradeFrame` with the projection of D241 and the inherited model of D242; verify with unit tests that a coordinate round-trips within 0.5 logical pixels at pitch 0, 45 and 80, that a coordinate behind the camera has no position, and that the copy of the world nearest the center is chosen
- [ ] 4.3 Make `MapigradeMap` provide an overlay host and an `OverlayChildIndex` to its children, and attach a `MapigradeController` with the displayed frame's camera; verify that a `MapigradePolylineLayer` and a feature query work in a widget test on a fake map controller

## 5. Gestures

- [ ] 5.1 Write the gesture arena member of D238 with a fake recognizer that records inputs; verify with adapter unit tests: a marker's tap wins, a vertical drag in a `ListView` goes to one recognizer, a two-finger gesture in a list goes to the map, a disabled part releases its pointer, and the kept events are replayed in order on a win
- [ ] 5.2 Map trackpad `PointerPanZoom` events, the mouse wheel through `PointerSignalResolver`, Shift, Ctrl and the right button, and the keyboard through `Focus` (D238); verify with adapter unit tests of the inputs each produces, and that a wheel event over the map doesn't scroll an enclosing list
- [ ] 5.3 Add the tap callbacks with the double-tap delay of D239, and haptic feedback and the box zoom rectangle of D245; verify with adapter unit tests of taps 290 ms and 310 ms apart, a double tap that calls no `onTap`, a pan that calls no `onTap`, and a notch that plays feedback once
- [ ] 5.4 Map `MapigradeGestures` to the recognizer's options and create the recognizer with each platform's momentum (D240); verify with unit tests of the options passed for each part and for iOS, macOS and Android

## 6. Markers

- [ ] 6.1 Write `MapigradeMarkers` and `MapigradeMarker` with the render object of D242: layout with loose constraints, upright placement by alignment, perspective scaling, far markers behind near ones, one copy of the world; verify with widget tests that a child's build isn't called while frames change, and that two overlapping markers paint in order of distance
- [ ] 6.2 Add the pitch and rotation alignments `map` (D242); verify with widget tests that a ground marker's painted corners equal the projections of its ground corners within 0.5 logical pixels, and that a tap on a ground marker reaches its child
- [ ] 6.3 Hide markers behind the camera, beyond the visible ground and off screen, keeping them mounted (D242); verify with widget tests that a hidden marker isn't painted or hit, and that a child's `State` survives leaving and returning to the screen

## 7. Integration tests

- [ ] 7.1 Add integration tests driven by the camera controller: initial camera with pitch, roll and padding, commands and their outcomes, limits, the camera streams, children and markers at the frame camera under pitch, the frame projection against the FFI projection, hidden markers, polylines and feature queries in a `MapigradeMap`; verify that they pass on macOS, the iOS simulator and the Android emulator
- [ ] 7.2 Add integration tests from gesture to camera with glides off: a drag pans by its distance on the ground, a pinch zooms by its scale, a tap reports the coordinate that the displayed frame draws at its position; verify that they pass on macOS, the iOS simulator and the Android emulator
- [ ] 7.3 Run the integration tests of tasks 7.1 and 7.2 on the iPhone and the Pixel; verify that they pass, and record each failure

## 8. Benchmarks

- [ ] 8.1 Add an alignment benchmark for `MapigradeMap` that measures markers against the displayed frame during commanded camera motion, and run it on the Mac, the iPhone and the Pixel; verify that the drawn error is within 1 logical pixel, and add the results to `docs/benchmarks.md`
- [ ] 8.2 Measure the latency from a pointer event to the first displayed frame that includes its camera movement, on the iPhone and the Pixel; add the results to `docs/benchmarks.md`
- [ ] 8.3 Measure the frame rate of a pan with 100 and 1,000 markers, against the same pan with no markers, on the Mac, the iPhone and the Pixel; add the results to `docs/benchmarks.md`
- [ ] 8.4 Run the frame-rate and alignment benchmarks of `MapigradeLayer` on the Mac, `main` against this branch, 3 alternating runs of each, and add a section to `docs/benchmarks.md`, for the move to the mln-rs-based FFI (moved from task 6.1 of `port-ffi-gesture-recognizer`); verify that the section states the builds, the conditions and the ranges over 3 runs
- [ ] 8.5 Present the Mac results of task 8.4 to the user, and ask whether the iPhones and the Pixel run those benchmarks; record the decision in this task (moved from task 6.2 of `port-ffi-gesture-recognizer`)
- [ ] 8.6 Present the results of tasks 8.1 to 8.3 to the user; record the decisions in this task

## 9. Manual checks on devices

- [ ] 9.1 With the user, check on the iPhone and the Pixel the feel of flings, pinches and the snap to north, whether the replayed pointer events make the map jump when it wins the arena, and the haptic feedback; record the outcome and any change to D238 or D240 in this task
- [ ] 9.2 With the user, check on the Mac the trackpad scroll and pinch, the mouse wheel, the right-drag, the box zoom and the keyboard; record the outcome in this task

## 10. Example and demo

- [ ] 10.1 Add `packages/mapigrade/example/` with a `MapigradeMap` at a pitched initial camera and a `MapigradeMarker`, importing only `package:mapigrade/mapigrade.dart`; verify that it runs on macOS, the iOS simulator and the Android emulator with the marker at its coordinate
- [ ] 10.2 Add the "Pitch and markers" showcase to the demo and the gallery, and one sentence about it to `packages/demo/README.md`; verify by running the demo on macOS and the Pixel and trying each scenario of the requirement "Pitch and markers"

## 11. Documentation

- [ ] 11.1 Write the `MapigradeMap` sections of `mapigrade`'s README: placing the map, the two controllers, camera commands, markers, taps and gestures; verify by reading it
- [ ] 11.2 Update `docs/architecture.md` (the camera owned by the map, the input path, the frame projection), `docs/limitations.md` (no terrain occlusion of markers, no web, no globe) and the unreleased CHANGELOG entries of both packages; verify by reading each changed section
