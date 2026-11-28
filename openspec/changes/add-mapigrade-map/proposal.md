## Why

MapLibre Native has, or is adding, features that change the camera transform or move the camera itself: terrain (in mln-rs since 0.0.16, 2026-11-26), the globe, camera parameters such as roll, field of view and padding, and camera motion that MapLibre computes, such as flights and gesture momentum. `flutter_map` works with many tile sources, and its layers and plugins paint in flat pixel space, which one matrix transforms to the screen. That keeps layers simple, and it fits a camera over a plane. Terrain and the globe don't fit it: every layer would have to project each point, with elevation data that only the renderer has. `flutter_map` could add a hook through which a plugin provides the transform and elevation. We haven't proposed one, and it would change every layer.

`MapigradeMap` is a widget in `mapigrade` (change `split-mapigrade-package`) that displays a MapLibre map on its own, with MapLibre's camera and gestures. MapLibre owns the camera, the FFI's gesture recognizer moves it (change `port-ffi-gesture-recognizer`), and Flutter widgets are drawn over the map with the projection matrix of the displayed frame. Dart reads that matrix instead of computing the transform, so the camera parameters need no new projection code in Dart. Terrain and the globe need new Dart code only to find the ground (D241). This change adds pitch and the camera parameters of `mln_camera`; later changes add terrain and the globe. `MapigradeLayer` stays supported for applications built on `flutter_map`, and it gets each camera feature once `flutter_map` can show it, such as pitch after #2304.

## What Changes

- **Widget.** `MapigradeMap` displays a style in a Flutter `Texture`, as the layer does. It takes an initial camera, camera constraints (minimum and maximum zoom, minimum and maximum pitch, bounds), gesture options, event callbacks and children. The camera has every field of MapLibre's camera: center, center altitude, zoom, bearing, pitch, roll, field of view and padding, in MapLibre's conventions.
- **Controllers, by composition.** `MapigradeMap` takes the `MapigradeController` of `split-mapigrade-package` for everything except the camera, as `MapigradeLayer` does, and a separate camera controller, which the application also creates. The camera controller has the camera commands (jump, ease, fly, fit to bounds, cancel), each completing with the outcome of its transition (completed, cancelled, replaced). Its camera is the camera of the displayed frame. It reports a stream of camera changes, each with its source (gesture or command), and a stream of moments when the camera comes to rest. Neither controller extends the other. Map events, such as taps, style loads and failures, are callbacks of the widget, not of a controller.
- **Frame projection.** Each frame reaches Dart with the projection matrix it was drawn with. Dart projects coordinates to screen positions and back, synchronously, with that matrix. Children read it through an inherited `MapigradeFrame`.
- **Markers.** `MapigradeMarkers` places `MapigradeMarker` widgets at coordinates with a render object that moves them each frame without rebuilding them. Each marker chooses its own size and has `pitchAlignment` and `rotationAlignment` (`viewport` or `map`, as in MapLibre's symbol layers) and an option to scale with perspective when upright. Far markers are drawn behind near ones. A marker appears once, in the copy of the world nearest the camera's center. Markers behind the camera, beyond the visible ground or off screen are not drawn and receive no hit tests, and stay mounted.
- **Polylines.** `MapigradePolylineLayer` works among `MapigradeMap`'s children, as among `MapigradeLayer`'s.
- **Gestures.** An input adapter takes part in the Flutter gesture arena and sends the pointers it wins to the FFI's gesture recognizer. Touch: pan, pinch, rotate, pitch, double-tap and two-finger-tap zoom, momentum with each platform's decay (friction with a half-life of 346 ms on iOS and macOS, the `CURVE` model on Android). macOS: a two-finger trackpad scroll pans, a pinch zooms and rotates, the mouse wheel zooms, a right-drag or Ctrl-drag rotates and pitches, a Shift-drag zooms to a box that the widget draws, and the arrow, `+` and `-` keys move the camera while the map has focus. `MapigradeGestures` turns each part on or off.
- **Events.** `onTap`, `onLongPress` and `onSecondaryTap` report the screen position and the coordinate of the gesture, as the recognizer classifies it. When double-tap zoom is on, `onTap` waits until a double tap is ruled out. Notches, such as the snap to north, play haptic feedback.
- **Demo.** A new showcase on `MapigradeMap`: pitch and rotation by gesture, upright pins and wind arrows lying on the ground, perspective scaling, taps and long presses. The existing showcases stay on `MapigradeLayer`.
- **Verification.** Unit tests of the input adapter with synthetic pointer events and a fake recognizer; integration tests driven by the controller; a few integration tests from gesture to camera; an alignment benchmark, a latency measurement from gesture to display and a frame-rate benchmark with many markers; manual checks on devices of momentum, haptics and the trackpad.

Not in this change: terrain, the globe, the free camera, axonometric projection, web, and markers built only near the viewport. The design records the two decisions that a web backend would change: synchronous terrain elevation for markers, and synchronous conversion of a tap over terrain to a coordinate. It also records that converting a position to a coordinate assumes the Mercator ground plane, which the terrain and globe changes replace.

## Capabilities

### New Capabilities
- `map-widget`: `MapigradeMap`, the camera controller, the camera model, constraints, camera commands and camera streams.
- `map-gestures`: the input adapter, the gesture arena, gesture options, momentum, desktop input, taps and haptic feedback.
- `map-markers`: the frame projection, `MapigradeFrame`, `MapigradeMarkers` and `MapigradeMarker`, placement, alignment, scaling, order and hiding.

### Modified Capabilities
- `map-texture`: each frame report includes the frame's projection matrix and every field of the camera.
- `polyline-layer`: polylines draw among the children of `MapigradeMap` as among those of `MapigradeLayer`.
- `feature-query`: `MapigradeController` attaches to `MapigradeMap` as to `MapigradeLayer`, and query positions are relative to the widget that displays the map.
- `package-api`: `mapigrade` exports the new widget, controller, markers and value types, under `mapigrade`'s naming rule: no name equal to a name exported by `latlong2`, `flutter/widgets` or `flutter/material`; `mapigrade` has an example app that uses `MapigradeMap`.
- `demo-app`: the gallery lists the new showcase.

## Impact

- `packages/mapigrade/lib/`: the widget, controller, frame projection, markers, input adapter and events.
- Native code: the C ABI gains functions for gesture input and ticks, camera commands with completions, constraints and the frame projection; the map thread publishes the frame projection.
- `packages/test_harness/`: integration tests and benchmarks for `MapigradeMap`, and the comparison of `MapigradeLayer` with `main` that `port-ffi-gesture-recognizer` deferred to this change.
- `packages/demo/`: the new showcase and one sentence in its README.
- Documentation: the `mapigrade` README, `docs/architecture.md` (camera owned by MapLibre, input path), `docs/limitations.md` (no terrain occlusion of markers, no web), `docs/benchmarks.md`.
- Dependencies: none new; `mapigrade` already depends on `latlong2`.
