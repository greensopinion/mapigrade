## 0.0.1

Initial release. The library `package:flutter_mapigrade/flutter_mapigrade.dart` exports:

- `MapigradeLayer`: displays a MapLibre Native map as the base layer of a `flutter_map` map, with the parameters `styleUrl`, `styleJson`, `alignment`, `httpHeaders`, `onStyleLoaded`, `onError` and `metrics`. `asset://` URLs load Flutter assets, including PMTiles files with `pmtiles://asset://`.
- `HttpHeaderRule`: HTTP headers that the layer adds to requests whose URL matches a glob.
- `LayerAlignment`: how the layer aligns the map with the overlays while the camera changes: `LayerAlignment.prediction()` (the default) or `LayerAlignment.none`.
- `MapigradeLayer.isSupported`: whether the layer can create a map in the process. On Android, an app that runs on a device without an arm64 ABI starts without the native library, and `isSupported` is false there.
- `LayerMetrics` and `LayerMetricsSnapshot`: the frame counts and render time of the layer's map, read with `LayerMetrics.snapshot()`.
- `LayerException` and its subclasses `LayerLoadException`, `LayerRenderException` and `LayerCreateException`: the failures that the layer reports to `onError`.

Licensed under the BSD 3-Clause License. Apps list the notices of MapLibre Native FFI and the libraries it includes in Flutter's license registry, so `showLicensePage` shows them without code in the app; Android apps also list the FFI's Rust crates and the NDK's C++ runtime.

Supported platforms: Android (API level 29, arm64), iOS 15.5 (arm64) and macOS 14.3 (arm64).
