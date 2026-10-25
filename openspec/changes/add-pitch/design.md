## Context

`docs/map-pitch-concept.md` is the plan for pitch across the fork and mapigrade; this is its change 2. The fork's commit `04c3e14` (local branch `map-pitch` in `~/git/flutter_map`) adds `MapCamera.pitch`, a projection that matches MapLibre Native's within 0.01 px (archived change `add-flutter-map-pitch-camera`), and `MapCamera.pixelToScreenTransform`.

The camera crosses mapigrade's layers in these places, all of which carry center, zoom and bearing only:

- Dart: `MapCamera` and `FrameCamera` (`lib/src/texture/map_texture_controller.dart`), the FFI structs and `map_texture_set_camera` in `bindings.dart`, the controller in `map_texture_controller_ffi.dart`.
- Native core: `Camera` in `src/core/command_queue.h`, `map_texture_event` and `map_texture_set_camera` in `src/core/map_texture_api.h`, and `map_texture.cpp`, which sets `MLN_CAMERA_OPTION_CENTER | ZOOM | BEARING` and reports each frame's camera.
- Projections: `screenPosition` and `worldPosition` in `lib/src/layer/camera_projection.dart`, used by the measurement mode's alignment error and by feature queries to turn a screen rectangle into ground corners; and `ScreenPosition`/`ScreenBounds` in `src/core/projection.h`, which turn those corners back into a screen box at the camera of the last rendered frame.
- Conversions: `viewCameraOf` (`flutter_map` camera to MapLibre camera) and `flutterMapCameraOf` (the inverse, used to draw children at the camera of the displayed frame).
- Camera prediction: `CameraVelocity` in `camera_prediction.dart`.

## Goals / Non-Goals

**Goals:**

- Pitch flows from the `flutter_map` camera to MapLibre and back in every frame report, so that the existing alignment guarantees hold on a pitched map.
- One projection model: MapLibre's, which the fork already reproduces.

**Non-Goals:**

- The pitch gesture (change 3), pitched camera fitting (change 4) and tile level of detail (change 5).
- MapLibre's padding, field of view, roll or center altitude. The field of view stays MapLibre's default, which is the fork's.
- Publishing the package with pitch. The path override blocks publishing until an upstream `flutter_map` release has pitch.

## Decisions

### 1. Path override for the fork

The workspace root `pubspec.yaml` gets `dependency_overrides: flutter_map: path: ../flutter_map`, relative to the repository root, so that every workspace package resolves to the fork checked out next to mapigrade. Package constraints stay as they are (`^8.3.2` in the package; `8.3.2` in the example, demo and test harness), because an override ignores them.

Alternative: a git dependency pinned to a fork commit. Deferred, because the branch isn't pushed (concept decision 16); it replaces the path override once it is.

### 2. Pitch through the native core and the C API

`Camera` gains `pitch`. `map_texture_set_camera` gains a `pitch` parameter after `bearing`, and `map_texture_event` gains a `pitch` field after `bearing`; the Dart bindings change with them. `map_texture.cpp` adds `MLN_CAMERA_OPTION_PITCH` when it sets the camera, and reports the pitch of the camera each frame was rendered with. The C API is internal to the package, so the change in its layout needs no compatibility handling; `ffi_pins_test.dart` and the native tests check that the two sides agree.

MapLibre limits the pitch to its default maximum of 60 degrees, the same limit as `flutter_map`'s `MapOptions.pitchLimit`, so no bound options are set.

### 3. Dart projection through the fork's camera

`screenPosition(view, world)` builds a `flutter_map` camera for the view (with `flutterMapCameraOf`'s conversion and the view's viewport) and applies its `pixelToScreenTransform` to the world point in projected pixels, after moving the point to the world copy nearest the center as now. `worldPosition(view, screen)` uses the camera's ray-cast inverse. This replaces the rotation-only formulas with the fork's, instead of keeping a third copy of the projection.

Alternative: the perspective formulas written out in `camera_projection.dart`. Rejected: a third copy that could drift from the fork's.

### 4. C++ projection with perspective

`ScreenPosition` in `projection.h` applies the same transform as the fork: rotation, then pitch, then the perspective division with the camera distance `0.5 · height / tan(fov / 2)`, using MapLibre's default field of view. Native tests compare it with MapLibre Native's own `mln_map_projection_pixel_for_lat_lng` for pitched cameras.

Alternative: ask MapLibre through an `mln_map_projection` set to the rendered frame's camera. Rejected: the projection object takes its viewport size from the map when it is created, and after a resize the map's size can differ from the size of the frame the query must match.

### 5. Pitch in camera prediction

`CameraVelocity` gains a pitch rate, computed like the zoom rate. The predicted pitch is the converted pitch plus the rate times the lead, limited to 0 to 60 degrees so that a prediction near the limit doesn't ask MapLibre for a pitch it would clamp differently from `flutter_map`.

### 6. Conversions and equality

`viewCameraOf` sets the MapLibre pitch to the `flutter_map` pitch, and `flutterMapCameraOf` sets the `flutter_map` pitch from the frame's. `MapCamera`, `ViewCamera` and `FrameCamera` include the pitch in equality, hash code and `toString`.

### 7. Verification

- The static alignment test (`static_alignment_test.dart`) gets pitched cases: pitch 30 and 60, rotation 0 and 30, on the Mac, the iPhone and the Pixel. The overlay is a `flutter_map` marker, which faces the viewer, rather than a `CircleMarker`: a circle on the ground is drawn as an ellipse under perspective, and its centroid isn't the projected center. The style's circle is drawn facing the viewer by default (`circle-pitch-alignment: viewport`), so its centroid is the projected point.
- The feature query test gets a pitched case at 60 degrees with a line near the top of the viewport.
- The children alignment requirement's pitched pan uses the existing alignment benchmark at pitch 45 on the Mac.
- Unit tests: `camera_projection_test.dart` and `camera_prediction_test.dart` get pitched cases, and the native tests compare `ScreenPosition` with MapLibre's projection.

### 8. 3D view showcase

A screen in `packages/demo/lib/src/three_d/` with the layer in the Liberty style, whose `building-3d` layer draws extruded buildings from zoom 14. Midtown Manhattan has tall buildings with height data in OpenStreetMap, which makes the pitch visible. A slider sets the pitch through the `MapController`, because there is no pitch gesture until change 3. The route and markers are the layer's children, so that they show the alignment on a pitched map.

### 9. Pitched flyover

The flyover's camera gains a pitch: 50 degrees while it follows a route, 0 at the starts and finishes and between stages, and interpolated in the turns to and from the route, as the zoom and rotation are. The player sets it with `MapController.pitch` after `moveAndRotate`.

The follow model keeps the rider at a place below the center and within a drift of it, both given on screen. It works on the ground, so `Flyover.build` converts them through a camera pitched at 50 degrees: the place exactly, and the drift as the smaller of the ground distances sideways and towards the viewer, where a pitched map is shown largest, so that a drift in any direction stays within the screen limit.

The flyover test that the rider moves up the screen measures the direction relative to the camera's heading without pitch: a pitched view shortens distances up the screen but not across it, so the angle on screen would overstate sideways movement.

## Risks / Trade-offs

- [The path override only resolves on a machine with the fork next to mapigrade] → It only affects mapigrade's `map-pitch` branch until the fork is pushed and pinned (decision 1).
- [3D buildings are drawn by MapLibre above the ground; overlays drawn by `flutter_map` lie on the ground or face the viewer, so a building can hide a route in the map but not in the overlays] → Expected: overlays are drawn above the map. The 3D view places the route along streets.
- [Feature queries on a pitched map use a screen box aligned with the screen axes, as now; near the top of a pitched view a small box covers a large ground area] → No change in behaviour from the unpitched case: the query matches what is drawn in the box.
- [Prediction overshoot at the 60 degree limit] → Limited (decision 5).

## Migration Plan

- Work on mapigrade's local `map-pitch` branch, with the path override. Nothing in the package's public API changes, apart from `MapCamera.pitch` and `FrameCamera`'s camera carrying it.
- Before merging to `main`: push the fork's branch (with approval), replace the path override with a pinned git dependency, or wait for an upstream release.
