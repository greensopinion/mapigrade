## 1. FFI build (D57)

- [x] 1.1 Add `MAPLIBRE_FFI_ANDROID_PRESETS="android-arm64-egl"` to `scripts/maplibre_ffi.lock`, and extend `build_maplibre_ffi.sh` to build Android presets (NDK 30.0.16248370, `ANDROID_HOME`, the Rust target `aarch64-linux-android` through mise) into `third_party/maplibre-native-ffi/<preset>/` without adding them to the xcframework; verify that `scripts/build_maplibre_ffi.sh android-arm64-egl` installs `libmaplibre-native-c.so` and the license files, that `llvm-readelf -l` shows 16 KB (0x4000) segment alignment, and that a rebuild of the Apple presets still produces the same xcframework slices
- [x] 1.2 Build the patched `rustls-platform-verifier` Android AAR from the FFI checkout and install it into `third_party/maplibre-native-ffi/android-maven/`; verify that the repository contains the AAR and a POM, and that the AAR contains `org/maplibre/nativeffi/internal/rustlsplatformverifier/CertificateVerifier` (the FFI's patch moves the package from `org.rustls.platformverifier`) and the license files

## 2. Plugin module and symbol resolution (D54, D56, D57)

- [x] 2.1 Create `packages/flutter_mapigrade/android/` (Gradle library module, Kotlin plugin class, CMake build of `src/core/` with a stub Android target that registers no texture), add the `android` platform to `pubspec.yaml`, and create `example/android/` with `flutter create --platforms android` (`minSdk` 29, `arm64-v8a`); verify that `flutter build apk --debug` in `example/` succeeds and that the APK contains both libraries for `arm64-v8a` only
- [x] 2.2 Implement `JNI_OnLoad` and the one-time native init (`JavaVM`, `TextureRegistry` and application `Context` global references, `mln_android_init`, cache directory); verify on the emulator that the example starts and logs a successful `mln_android_init`
- [x] 2.3 Verify whether the unchanged `@Native` bindings resolve on Android in debug and release builds (call `map_texture_process_thread_count` from the example); if not, apply the first option of D56 that works and record which one in this design; verify with the release build on the emulator

## 3. Core: surface target and pacing (D52, D53)

- [x] 3.1 Split `RenderTarget` into the buffer kind (Apple, unchanged behavior) and the surface kind, with `MapTexture::MaybeRender()` branching once; send `FRAME_DISPLAYED` with `display_time_us = -1` after each rendered frame of a surface target; verify that the C++ core tests pass, with new tests for the surface kind using a fake target, and that the macOS integration tests still pass
- [x] 3.2 Pace surface targets to one render per display refresh interval and count deferred renders in `interval_waits` (C ABI and `MapTextureStats`); verify with a core test using a fake clock that a pending render starts no earlier than one interval after the previous start, and that an idle map renders nothing

## 4. Android render target (D51, D54)

- [x] 4.1 Implement the Android surface target: create the `SurfaceProducer` and its `ANativeWindow` on the main thread, create the EGL display, config and window surface on the map thread, and attach with `mln_opengl_surface_attach` (EGL, dedicated); verify on the emulator that the example shows the map with a style and tiles loaded over HTTPS, and that the camera controls move it
- [x] 4.2 Implement resize (`setSize`, new `Surface`, `mln_opengl_surface_set_target` with the new extent, old window surface destroyed after the switch); verify on the emulator by rotating between portrait and landscape and by the resize integration test that the map fills the widget without stretching
- [x] 4.3 Implement `onSurfaceCleanup` (park on a pbuffer surface, destroy the window surface, wait for the map thread) and `onSurfaceAvailable` (replace the surface, render the pending frame), and a test hook that makes the producer receive `onTrimMemory(TRIM_MEMORY_BACKGROUND)`; verify with an integration test that after cleanup and restore a frame with the most recent camera is reported without a new style-loaded event, and by hand that `adb shell am send-trim-memory <package> BACKGROUND` while the app is in the background, followed by a return to the foreground, shows the map without errors
- [x] 4.4 Implement dispose for the surface target (release the session, EGL objects, window, producer and global references); verify that the 50 create/dispose cycles test keeps the thread count and memory bounded on the emulator

## 5. Lifecycle, memory and measurement functions (D55, D58)

- [x] 5.1 Pause on `onActivityStopped` and resume on `onActivityStarted` (and pause at once if the activity is already stopped), and reduce memory use on `onTrimMemory(level >= TRIM_MEMORY_BACKGROUND)` and `onLowMemory`; verify with the lifecycle integration tests on the emulator and by sending the app to the background during a pan: `paused_renders` increases and `rendered_frames` doesn't
- [x] 5.2 Implement the Android measurement functions as D58 states; verify that the memory and thread-count tests report plausible values on the emulator (thread count returns to its baseline after dispose)
- [x] 5.3 Make `FrameCamera.displayTime` nullable and document that `copyFree` has no effect on Android; update the Dart unit tests and the Apple-side users of `displayTime`; verify with `flutter analyze`, the package unit tests, and the macOS integration tests

## 6. Example and tests on Android (D59)

- [ ] 6.1 Make the integration tests run on the emulator, skipping with a stated reason only the display-time, timing-probe and released-buffer tests; verify that `map_texture_test.dart`, `map_layer_test.dart` and `static_alignment_test.dart` pass on the emulator
  - Status 2026-10-12: on the API 37 emulator, `map_layer_test.dart` and `static_alignment_test.dart` pass, and `map_texture_test.dart` passes except "rapid camera updates do not build up a backlog". That test's 500 ms latency check fails because the emulator forces software GLES (render_update about 0.4 s). We accepted the failure until the Pixel run; complete 6.1 when the test passes there.
- [x] 6.2 Make `alignment_benchmark.dart` and `timing_probe.dart` print that they need display times and exit on Android, and check that `benchmark.dart` runs there; verify with a release run of each on the emulator
- [x] 6.3 Run the color check on the emulator; verify that the map's colors match the Flutter swatches within 2/255 per channel, or record the difference and its cause in `limitations.md`

## 7. Reference device and Stage 4 (D60)

- [ ] 7.1 Connect the Pixel and record its model, Android version, refresh rate and Flutter renderer; verify that the test harness's release build starts, resolves every native function and shows the map (if the Android version is below 10, stop and ask for a decision as the design's Risks state)
- [ ] 7.2 Run the continuous pan (30 s, portrait, release) and the 5-minute run over central London, and measure the memory and the app size increase; verify that the results are recorded in `docs/benchmarks.md` with the conditions the concept document lists
- [ ] 7.3 Check alignment by hand on the `flutter_map` page with the default alignment (pan, fling, stop, reverse) and record what you observe; verify that `docs/limitations.md` states the result and the device's refresh rate
- [ ] 7.4 Record the Stage 4 decision in roadmap row 4 of the concept document, and update `README.md`, `docs/limitations.md` (Android sizes, licenses including the Rust crates and the verifier, findings, known limitations) and the Purpose of `openspec/specs/map-texture/spec.md` to name Android; verify with `git grep -n 'macOS and iOS'` that no current document still describes the plugin as Apple-only
