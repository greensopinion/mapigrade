## Unreleased

- The native libraries come from MapLibre Native FFI 0.202610.2, whose native core runs the map and its commands; the plugin's native code was ported to it. The Dart API doesn't change.
- Android apps also list the notices of Kotlin and of the FFI's rustls-platform-verifier component in Flutter's license registry.
- While rendering is paused (iOS in the background, a stopped Android activity), a memory warning releases cached renderer resources when rendering resumes, not at once.

## 0.0.1

Initial release. The library `package:flutter_mapigrade/flutter_mapigrade.dart` exports:

- `MapigradeLayer`: displays a MapLibre Native map as the base layer of a `flutter_map` map, with the parameters `styleUrl`, `styleJson`, `alignment`, `httpHeaders`, `onStyleLoaded`, `onError`, `metrics` and `children`. The layer draws its `children` at the camera of the map frame it displays, so that they stay on the map while the camera moves. `asset://` URLs load Flutter assets, including PMTiles files with `pmtiles://asset://`.
- `HttpHeaderRule`: HTTP headers that the layer adds to requests whose URL matches a glob.
- `LayerAlignment`: how the layer aligns the map with the overlays while the camera changes: `LayerAlignment.prediction()` (the default) or `LayerAlignment.none`.
- `MapigradeLayer.isSupported`: whether the layer can create a map in the process. On Android, an app that runs on a device with none of the ABIs `arm64-v8a`, `armeabi-v7a` and `x86_64` starts without the native library, and `isSupported` is false there. Apps built for web build with the package, and `isSupported` is false on web.
- `LayerMetrics` and `LayerMetricsSnapshot`: the frame counts and render time of the layer's map, read with `LayerMetrics.snapshot()`.
- `LayerException` and its subclasses `LayerLoadException`, `LayerRenderException` and `LayerCreateException`: the failures that the layer reports to `onError`.

Licensed under the BSD 3-Clause License. Apps list the notices of MapLibre Native FFI and the libraries it includes in Flutter's license registry, so `showLicensePage` shows them without code in the app; Android apps also list the FFI's Rust crates and the NDK's C++ runtime.

Maps keep working when the app or another plugin, such as a messaging plugin that runs Dart in the background, starts a second Flutter engine: each map displays in the engine whose Dart code created it. On Android and iOS, the maps of an engine that is destroyed are released with it.

Supported platforms: Android (API level 29; `arm64-v8a`, `armeabi-v7a` and `x86_64`), iOS 15.5 (arm64) and macOS 14.3 (arm64).

The native libraries come from MapLibre Native FFI 0.202610.1: on Android the runtime AAR from Maven Central, on iOS and macOS the release's `MaplibreNativeC.xcframework.zip`. The package contains no native binaries.
