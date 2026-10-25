## Why

Our `flutter_map` fork now has a pitched camera whose projection matches MapLibre Native's (archived change `add-flutter-map-pitch-camera`), but mapigrade sends MapLibre only center, zoom and bearing, and its projections assume an unpitched camera. Until mapigrade passes the pitch through, a pitched `flutter_map` map shows an unpitched MapLibre map under pitched overlays. This change is change 2 in `docs/map-pitch-concept.md`, and it is the test of change 1's projection against a map that MapLibre renders.

## What Changes

- mapigrade depends on the fork through a path override in the workspace, until the fork is pushed and the upstream PR is released.
- The layer sets the MapLibre pitch from the `flutter_map` pitch, and each frame's report includes the pitch it was rendered with.
- Camera prediction extrapolates the pitch, as it does the zoom.
- The layer draws its children at the pitch of the displayed map frame.
- Feature queries find the features under the screen position or rectangle on a pitched map.
- The demo app has a third showcase, "3D view": a city with Liberty's 3D buildings, a pitch slider, and overlays that stay on the map.
- The demo's flyover pitches the camera to 50 degrees while it follows a route, like a drone looking ahead of the rider.
- The package README and `docs/limitations.md` no longer state that there is no pitch.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: the map follows the `flutter_map` pitch; camera prediction includes pitch; alignment at rest and children alignment hold on a pitched map.
- `map-texture`: Dart sets the pitch with the camera, and the frame reports include it.
- `feature-query`: queries stay aligned with the displayed map frame on a pitched map.
- `demo-app`: the gallery lists a third showcase, the 3D view showcase is added, and the flyover is pitched while it follows a route.

## Impact

- `packages/flutter_mapigrade`: the native core's camera, C API and projection; the FFI bindings; `MapCamera`, `FrameCamera`, `ViewCamera` and the camera conversions; camera prediction.
- The workspace root `pubspec.yaml` gets a `dependency_overrides` entry for `flutter_map`, with a path to the fork checked out next to mapigrade. The package can't be published with it; publishing waits for an upstream `flutter_map` release with pitch.
- `packages/demo`: a new showcase screen and gallery entry.
- `packages/test_harness`: pitched cases in the static alignment and feature query tests.
