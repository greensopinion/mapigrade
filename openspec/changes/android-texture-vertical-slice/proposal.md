## Why

Android is a required platform (concept document, decision 5), and Stage 4 of the roadmap is its vertical slice: a `SurfaceProducer` bridge, the surface lifecycle, packaging and measurements, with the go/no-go threshold of at least 30 fps on the reference Android device. Stages 1 to 3 are done on macOS and iOS. Since remove-camera-transform (which this change depends on), the `flutter_map` layer no longer needs the camera of the frame Flutter displays, which Android can't report exactly.

## What Changes

- The plugin supports Android on arm64 devices, API level 29 (Android 10) or later, with the same Dart API as on macOS and iOS.
- An Android bridge: a Kotlin plugin class and a native Android render target. MapLibre renders through an EGL window surface on the `Surface` of a Flutter `SurfaceProducer` (FFI preset `android-arm64-egl`). The bridge recreates the EGL surface when Flutter replaces or removes the `Surface`, and when the map is resized.
- Rendering on Android is paced to at most one frame per display refresh interval, because Flutter's `ImageReader` takes every queued image, so queueing a frame never blocks.
- The bridge pauses rendering while the Flutter activity is stopped, and asks the renderer to release cached resources when Android reports memory pressure.
- On Android, the report of each frame's camera is sent when the frame is queued for display, and it has no display time. **BREAKING** (unpublished API): `FrameCamera.displayTime` becomes nullable; it is null on Android.
- On Android, every map renders into the `SurfaceProducer`'s buffers. The copy option (`copyFree: false`) has no effect there.
- The FFI build script and lock file build the `android-arm64-egl` preset and the Rustls platform verifier's Android component. The plugin calls `mln_android_init` once per process.
- The example app gets an Android project. The integration tests run on Android, except the ones that need plugin-owned buffers or display times. The benchmark measures the frame rate on the reference device.
- Stage 4 is decided from the frame rate on the reference device (an older Pixel, connected later) and a manual alignment check of the `flutter_map` layer. Alignment is not measured on Android in this change.

Out of scope: the Vulkan preset (a possible comparison on the reference device later), 32-bit ARM and x86_64, an Android alignment measurement, Android versions before API 29 (`SurfaceProducer`'s `SurfaceTexture` path), Play Store packaging.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: "Supported platforms" adds Android. "Camera of each displayed frame" reports, on Android, the frame queued for display without a display time. "Frame rate" adds the reference Android device. "No rendering while the application is in the background" and "Memory warnings release cached renderer resources" cover Android. "Viewport size and pixel ratio" covers rotation on Android phones. "Copy-free rendering by default" limits the copy option to macOS and iOS. A new requirement covers the replacement and removal of the surface Flutter gives the plugin.

## Impact

- Code: new `packages/flutter_mapigrade/android/` (Gradle module, Kotlin plugin class, CMake build of `src/core/` with the Android render target); `src/core/` (a render target that presents through a surface, pacing by refresh interval, a new statistics field); `lib/src/texture/` (`displayTime` nullable); `pubspec.yaml` (Android platform); `scripts/build_maplibre_ffi.sh` and `scripts/maplibre_ffi.lock`.
- Dependencies: MapLibre Native FFI `android-arm64-egl` at the pinned commit 6f5a662; the FFI's patched `rustls-platform-verifier` Android component; NDK 30.0.16248370, the version the FFI pins.
- Example: new `example/android/`; `example/lib/benchmark.dart`, `alignment_benchmark.dart` and `timing_probe.dart` (they report that display times are unavailable on Android); the integration tests.
- Documentation: `README.md`, `limitations.md` (sizes, licenses, Android findings), `benchmarks.md`, roadmap row 4 of the concept document, and the map-texture spec's Purpose.
