## Why

Maintaining a vector map renderer in Dart has a high cost. The CPU version draws with the Flutter canvas. The GPU version adds a dependency on `flutter_gpu`, which may take years to reach GA or may never reach it. We want to find out whether MapLibre Native, called through MapLibre Native FFI, can render the base map on the GPU into a Flutter `Texture` widget, with no platform view and no CPU pixel readback. If it can, Flutter can draw `flutter_map` overlays on top of it. This change is the first vertical slice, on macOS, because the Metal bridge built for macOS also applies to iOS, and macOS has the shortest build-and-run loop. Background and the full staged plan: `docs/maplibre-native-ffi-flutter-texture-poc.md`.

## What Changes

- Add the Flutter plugin package `flutter_map_maplibre_texture` (macOS only in this change) that displays a MapLibre Native map in a `Texture` widget. The name follows the `flutter_map` plugin naming convention, and "texture" distinguishes it from `flutter_map_maplibre`, which displays the native MapLibre SDK view. In this change the package doesn't depend on `flutter_map` yet.
- Add a native C/C++ core that owns the MapLibre runtime, map and render session on its own threads, and accepts commands from Dart through `dart:ffi`.
- Add a Metal bridge that renders into a set of IOSurface-backed pixel buffers and passes completed frames to Flutter's texture registry without CPU readback.
- Add a minimal Dart API: create, load style, set camera, resize (including device pixel ratio), dispose, error and event reporting, and the camera of each displayed frame.
- Add an example macOS app that shows the map with a Flutter widget overlaid on it and changes the camera from Flutter.
- Add build scripts that build MapLibre Native FFI at a pinned revision for `macos-arm64-metal`.
- Add a measurement procedure and report frame timing results against the 30 fps minimum and 60 fps target.

Out of scope for this change: iOS, Android, `flutter_map` integration and overlay alignment (a later change adds the `flutter_map` layer to the same package), MapLibre-side gestures or camera animation, offline regions, and changes to `dart-vector-tile-renderer` or `flutter-vector-map-tiles`. Draft PR #906 in `maplibre/flutter-maplibre-gl` is used for ideas only, and this change reuses none of its code.

## Capabilities

### New Capabilities

- `map-texture`: displaying a MapLibre Native map as a Flutter `Texture`, controlling it from Dart (style, camera, viewport, lifecycle), reporting its events and the camera of each displayed frame, and the performance and no-readback constraints on the frame path.

### Modified Capabilities

None. The project has no existing specs.

## Impact

- New code in this repository: the Flutter plugin package `flutter_map_maplibre_texture` (Dart API, macOS native bridge, shared C/C++ core) and an example app. No existing code is changed.
- New external dependency: MapLibre Native FFI, pinned to an exact commit (`dd97d20f8fab6990cd87c13f091ce00e662707bd` was HEAD on 2026-10-09). Its C ABI is pre-1.0 and unstable, so updating the pin can require code changes.
- Build prerequisites: Xcode with the macOS SDK, CMake and the toolchain that the FFI repository's `mise` configuration installs, and the Flutter SDK with macOS desktop enabled.
- Distribution: the macOS app bundle includes the MapLibre Native FFI dynamic library. This change records the size increase.
- Licenses: MapLibre Native and MapLibre Native FFI licenses and their third-party notices must be reviewed and recorded before any distribution.
