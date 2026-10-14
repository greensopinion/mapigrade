## Why

The plugin's native library is built for arm64 only. On Android, `MapigradePlugin.onAttachedToEngine` calls `System.loadLibrary("flutter_mapigrade")` when the Flutter engine starts. On a device without an arm64 process, such as a 32-bit (`armeabi-v7a`) phone, a Chromebook or an x86_64 emulator, that call throws `UnsatisfiedLinkError`. The generated `GeneratedPluginRegistrant` catches only `Exception`, so the app crashes at startup, whether or not it uses the layer. A Flutter release build packages `libflutter.so` for `armeabi-v7a` and `x86_64` by default, so Google Play probably still offers such an app to those devices. An application has no way to avoid the crash, or to display another layer, such as a raster tile layer, in place of the map. We want to fix this before the package is published.

## What Changes

- On Android, the plugin catches `UnsatisfiedLinkError` when it loads its native library, logs a warning that names the device's ABIs, and does nothing else for the life of the process: it doesn't initialize the native library, register lifecycle and memory callbacks, or call native functions. The app continues to start.
- A new static getter, `MapigradeLayer.isSupported`, returns whether the native library is available in the process. An application reads it to decide whether to place `MapigradeLayer` or another layer.
- When the native library isn't available, a `MapigradeLayer` placed in the tree reports a `LayerCreateException` to `onError` and occupies the viewport without drawing anything, as it does for any map that can't be created. It doesn't throw.
- The README replaces the limitation "arm64 only on every platform" with the supported architectures, how to check `isSupported` and display another layer, and, for apps that don't want a fallback, how to restrict the app to arm64 with `abiFilters`.

Non-goals:

- No native library for `armeabi-v7a`, `x86` or `x86_64`.
- No change on macOS and iOS. There the plugin is linked into the app, and a build for x86_64 fails when it is linked, so no app can run without the native code. `isSupported` returns true on those platforms in every app that builds.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: a new requirement, "Unsupported architectures", covers app startup without the native library, `MapigradeLayer.isSupported`, and the creation failure that the layer reports when the native library isn't available.

## Impact

- Dart API: a static getter on `MapigradeLayer`. The set of exported names doesn't change.
- Code: `packages/flutter_mapigrade/android/src/main/kotlin/.../MapigradePlugin.kt`, `lib/src/layer/mapigrade_layer.dart`, `lib/src/texture/map_texture_controller.dart`, a new internal file for the availability check, `lib/src/testing.dart`, `README.md`, `CHANGELOG.md`, and tests in `test/`.
- Test harness: a build option that leaves the native library out of the APK, to check the Android path on an arm64 device.
- Dependencies: this change starts after `public-api`, which adds `MapigradeLayer`, `LayerCreateException` and the failure reporting that this change uses. The change `tile-cache-maximum-size` adds `MapigradeLayer.maximumCacheSizeBytes`. Its setter must not call native code when `isSupported` is false.
