## 0.2.0-beta.1

- This beta supports iOS and macOS only: it uses a version of MapLibre Native FFI that has no release yet, and Android builds need the FFI's release from Maven Central. On Android, apps build and run, and `Mapigrade.isSupported` is false.
- First release. It contains:
  - `MapigradeMap`, a map widget with MapLibre's gestures and camera. The camera (`MapigradeCamera`) has pitch, roll, field of view and padding, and `CameraLimits` keeps it within zoom and pitch ranges and `GeoBounds`.
  - `MapigradeCameraController`, which jumps, eases or flies the camera, or fits it to bounds. Each of these completes with how the transition ended (`CameraTransitionOutcome`). The controller also gives the camera of the displayed map frame, and streams of camera changes and of rests.
  - Touch, trackpad, mouse and keyboard gestures, which share input with other widgets through Flutter's gesture arena. `MapigradeGestures` turns each gesture on or off. `onTap`, `onLongPress` and `onSecondaryTap` report the position and the coordinate (`MapigradeTap`).
  - `MapigradeMarkers`, which places widgets at coordinates, upright or lying on the map (`MarkerAlignment`), and `MapigradeFrame`, which converts between coordinates and positions on the map.
  - `MapigradePolylineLayer`, whose polylines the map draws among the style's layers, and `MapigradeController`, for feature queries and feature state.
  - `Mapigrade.isSupported` and `Mapigrade.maximumCacheSizeBytes`.
- The map is drawn by mln-rs, the Rust port of MapLibre Native, through MapLibre Native FFI at commit `4371ff6`, which no FFI release contains yet. The iOS and macOS builds download a build of that commit from this repository's GitHub release [`maplibre-native-ffi-4371ff6`](https://github.com/greensopinion/mapigrade/releases/tag/maplibre-native-ffi-4371ff6).
