## Context

See proposal.md for motivation and scope, and specs/map-texture/spec.md for the requirements. The concept document (`docs/maplibre-native-ffi-flutter-texture-concept.md`, sections 5, 7 and 13) and the designs of the earlier changes apply, except where a decision here replaces one. This change starts after remove-camera-transform. Decisions here are numbered from D51.

Current state, as checked on 2026-10-12:

- **Core.** `src/core/` has no platform dependencies. A platform implements `RenderTarget` and three free functions (`render_target.h`). `RenderTarget` assumes the Apple model: the plugin owns a set of display buffers, the map thread renders into a free one (or copies into it), and Flutter's raster thread takes the latest one through `CopyBufferLocked` from `MapTexture::Present()`. `Present()` drives pacing (the next render waits until Flutter has taken the latest frame), render ahead (D19) and the `FRAME_DISPLAYED` event with its display time. The measurement functions (`map_texture_process_thread_count`, `_thermal_state`, `_memory_footprint`, `_released_buffers_*`) and `PlatformCachePath()` are implemented in `darwin/.../MapTextureMetal.mm`. The lifecycle hooks (`SetAllPaused`, `ReduceAllMemoryUse`) are called from `MapigradePlugin.mm`.
- **Dart.** The `@Native` bindings resolve symbols from the process, because the Apple plugin is linked into the app (`lib/src/texture/bindings.dart`). The package has no build hook.
- **Flutter 3.47.5, Android embedding.** `TextureRegistry.createSurfaceProducer()` returns a producer that hands out a `Surface`. On API 29+ it is backed by `ImageReader` (`FlutterRenderer.ImageReaderSurfaceProducer`): 7 images, `USAGE_GPU_SAMPLED_IMAGE`. On each queued image, a listener on the main looper acquires it, keeps at most the 2 newest per reader, and schedules an engine frame. The raster thread takes the newest. `setSize` makes the next `getSurface()` create a new `ImageReader` of that size. On `onTrimMemory(level >= TRIM_MEMORY_BACKGROUND)` the producer calls `onSurfaceCleanup()` and closes its readers; on the activity's resume it calls `onSurfaceAvailable()`. There is no callback when Flutter takes an image. The merged platform and UI thread is the default (`Settings::MergedPlatformUIThread::kEnabled`), so Dart's UI isolate runs on Android's main thread.
- **FFI at 6f5a662.** Presets `android-arm64-egl` and `android-arm64-vulkan` (API 24, `c++_static`, NDK 30.0.16248370 in its `mise.toml`). `mln_opengl_surface_attach` with an EGL context descriptor and an `EGLSurface`. A *dedicated* session builds its own context from the display and config and keeps it current on the attaching thread. The session presents with `eglSwapBuffers`. `mln_opengl_surface_set_target` replaces the surface (made current on the next render), so a session can move to another surface without being recreated. The FFI's `examples/android-map` moves a session to a 1x1 pbuffer surface while the window is gone. `mln_android_init(env, class, context)` is required once per process and needs the patched `rustls-platform-verifier` Android component (`bindings/rustls-platform-verifier-android`) in the APK.
- **Machine.** Android SDK with NDKs up to 30.0.16248370; an arm64 emulator with 16 KB pages (`sdk_gphone16k_arm64`, API 37). The reference device is an older Pixel; its model and Android version are not known yet.

## Goals / Non-Goals

**Goals:**
- The example and the `flutter_map` layer run on Android with the same Dart code as on Apple, with no CPU readback.
- A Stage 4 go/no-go decision from the frame rate on the reference device and a manual alignment check.
- The Apple bridge and its measured behavior don't change.

**Non-Goals:**
- Vulkan, other ABIs, API levels below 29, an alignment measurement on Android (manual check only, decided 2026-10-12), Play Store packaging, rendering ahead on Android.

## Decisions

### D51. EGL window surface on the `SurfaceProducer`'s `Surface`

The Android target creates a `SurfaceProducer`, makes an `ANativeWindow` from its `Surface`, and creates an `EGLSurface` on it with an OpenGL ES 3 config that also supports pbuffers. The map thread attaches the session with `mln_opengl_surface_attach`, platform EGL, ownership dedicated. The session renders into the window's buffers, which are the `ImageReader`'s `HardwareBuffer`s that Flutter samples, so the plugin makes no copy.

*Alternatives:*
- Vulkan surface (`android-arm64-vulkan`). The concept document names it as a candidate if it is faster. On 2026-10-12 we decided to use EGL for the best device compatibility: OpenGL ES drivers are mature on every Android device, while Vulkan drivers on older devices are less reliable (Flutter itself falls back to OpenGL ES on some GPUs). EGL also works with both of Impeller's backends, and the FFI example covers its surface replacement. We change to Vulkan only if there is a good reason, for example if `render_update` on a device is limited by CPU time on the map thread, which Vulkan can reduce. A comparison would be its own change.
- Plugin-owned `HardwareBuffer`s rendered through borrowed GL textures and handed to Flutter with `ImageTextureEntry.pushImage`. This keeps the Apple model, but a pushed image is not a displayed image either, it needs an `ImageWriter` or `HardwareBuffer` import path that few plugins use, and it's more code.
- Shared ownership with a host share context. The plugin has no GL work of its own, so a dedicated session is simpler.

### D52. A second kind of render target in the core

`RenderTarget` gets a sibling kind for targets that present through a surface. `MapTexture::MaybeRender()` branches once on the kind:

- **Buffer target** (Apple): unchanged.
- **Surface target** (Android): no buffer set, no `Present()`, no copy, no `SelectBuffer`. After `mln_render_session_render_update` returns a rendered frame (the session has called `eglSwapBuffers`, so the frame is queued), the map thread sends `MAP_TEXTURE_EVENT_FRAME_DISPLAYED` with the frame's camera and size and `display_time_us = -1`. The event keeps its name. On Android it means the frame was queued for display.

The surface target's operations: attach to the current window, replace the window (resize or a new surface after cleanup), park on a pbuffer surface, and release. `PrepareBuffers`, `SwapBuffersLocked`, `CopyBufferLocked`, `CopyToBuffer`, `SelectBuffer` and `RendersIntoBuffers` move to the buffer kind.

*Alternative:* implement the buffer interface on Android with no-op methods. `Present()` would never be called, pacing would wait forever, and every buffer method would carry a meaning it doesn't have on Android.

### D53. Pacing by display refresh interval on Android

Queueing a frame never blocks (7 images, and the main looper acquires each one as it arrives), so `eglSwapBuffers` doesn't pace the map.

*Correction (2026-10-12):* queueing doesn't block only while the main thread runs. On the emulator, `eglSwapBuffers` dequeues the next buffer and waited in `BufferQueueProducer::waitForBufferRelease` while the main thread was blocked in `Dispose()` joining the map thread, and the app hung (ANR). Every main-thread wait for the map thread (dispose, surface cleanup, pause) can deadlock this way. The target therefore sets swap interval 0 (`eglSwapInterval`) on each window surface it makes current: the window then queues in async mode, a new frame replaces a queued frame that Flutter hasn't acquired, and a dequeue never waits for Flutter. With this, the integration tests ran without the hang. Without pacing, the map would render as fast as the GPU allows, as the Apple slice did before its pacing (about 1,200 fps). The surface target therefore starts a render no earlier than one display refresh interval after the start of the previous render. The interval comes from `map_texture_set_display_refresh_rate` (60 Hz until it is set). A render that has to wait stays pending, and the map thread waits on its wake source until the interval ends. Deferred renders are counted in a new statistics field, `interval_waits`. `waits_for_display`, `render_ahead_frames`, `pickup_wait_*` and `present_to_render_*` stay 0 on Android.

*Alternatives:*
- `AChoreographer` frame callbacks that wake the map thread on each vsync. This pacing is locked to the display's vsync phase, but it needs a looper thread. We switch to it if the reference device shows uneven frame intervals with time-based pacing.
- Dart frame callbacks. Frames that only update the texture are rasterized without a Dart build, so Dart sees no callback for them.

### D54. Threads and JNI

- `JNI_OnLoad` stores the `JavaVM`. The Kotlin plugin's `onAttachedToEngine` passes the `TextureRegistry` and the application `Context` to native code once. Native code keeps global references, calls `mln_android_init(env, nullptr, context)` once per process, and stores `Context.getCacheDir()` for `PlatformCachePath()`.
- The producer is created with `SurfaceLifecycle.resetInBackground`. With the default, `manual`, Flutter never removes its surface, and `onSurfaceCleanup` and `onSurfaceAvailable` are never called. With `resetInBackground`, `FlutterActivity.onStop` calls `onTrimMemory(TRIM_MEMORY_BACKGROUND)` and `onResume` calls `restoreSurfaceProducers()`, so the surface is removed and provided again on every stop and resume, not only under memory pressure.
- `map_texture_create` and `map_texture_resize` run on Android's main thread, because Dart's UI thread is merged with it. The target calls `createSurfaceProducer`, `setCallback`, `setSize` and `getSurface` there through JNI, and passes the `ANativeWindow` (with its reference acquired) to the map thread as an ordered command. If `map_texture_create` is called on another thread (the merged thread turned off), it fails with `MAP_TEXTURE_ERROR_CREATE_FAILED` and logs why.
- `onSurfaceCleanup` (main thread) sends a command that moves the session to the pbuffer surface and destroys the window surface, and waits until the map thread has done it, so that the plugin no longer uses the `Surface` when the callback returns. The wait is bounded by one render, as the iOS pause is (D13). `onSurfaceAvailable` gets the new `Surface` and sends the replacement command. The map is not recreated.
- The map thread never calls into Java and never waits for the main thread. The main thread waits for the map thread only in surface cleanup and dispose.
- `FrameAvailable()` does nothing on Android: the producer schedules an engine frame for each image it receives.

### D55. Lifecycle and memory pressure

The plugin implements `ActivityAware`. It registers `Application.ActivityLifecycleCallbacks` for the Flutter activity and calls `SetAllPaused(true)` in `onActivityStopped` and `SetAllPaused(false)` in `onActivityStarted`. If the activity is already stopped when the plugin attaches, it pauses at once, as the iOS plugin does at registration. It registers `ComponentCallbacks2` on the application context and calls `ReduceAllMemoryUse()` on `onTrimMemory(level >= TRIM_MEMORY_BACKGROUND)` and `onLowMemory()`.

*Alternatives:*
- Pause from Dart with `AppLifecycleListener`. The Apple plugins pause natively, and Dart's lifecycle state on Android comes from the same activity callbacks.
- `ProcessLifecycleOwner`. It adds an androidx dependency and reports a stop about 700 ms late.

### D56. Dart symbol resolution on Android

On Android the plugin's code is in `libflutter_mapigrade.so`, loaded by `System.loadLibrary`. We expect that its symbols are not in the global lookup scope that `@Native` without a code asset falls back to, but we haven't verified this. The first implementation task checks it, and the bindings stay as they are if it works. Otherwise, in this order:

1. `JNI_OnLoad` opens the library again with `RTLD_NOW | RTLD_GLOBAL`.
2. A build hook (`hook/build.dart`) declares the Gradle-built library as a bundled code asset under the bindings' asset id. `System.loadLibrary` of the same file returns the already loaded library, so Kotlin and Dart share one copy of the core.

Each option is verified in a release build on the emulator, which also checks the release-build scenario of "Supported platforms" for symbol resolution.

*Result (2026-10-12):* the unchanged bindings fail on Android ("No asset with id `package:flutter_mapigrade/src/texture/bindings.dart` ... Attempted to fallback to process lookup. undefined symbol"). Option 1 doesn't work either: after `dlopen(RTLD_NOW | RTLD_GLOBAL)`, `dlsym(RTLD_DEFAULT)` finds the symbol, but Dart's process lookup still doesn't. We use option 2 with one change: `hook/build.dart` declares the asset with link mode `DynamicLoadingSystem('libflutter_mapigrade.so')` rather than as a bundled file, so Flutter copies nothing into the APK and Dart's `dlopen` by name returns the library that `System.loadLibrary` already loaded. On macOS and iOS the hook declares no asset, and process lookup works as before. Verified with debug and release builds on the emulator. After the hook was added, `flutter build` skipped its `build_hooks` target as up to date until `flutter clean`.

### D57. Packaging and the FFI build

- `packages/flutter_mapigrade/android/` is a Gradle library module (Kotlin, `minSdk` 29, `ndkVersion` 30.0.16248370, `abiFilters` `arm64-v8a`). CMake (`externalNativeBuild`) builds `libflutter_mapigrade.so` from `src/core/` and `android/src/main/cpp/`, links the FFI's `libmaplibre_native_c.so` from `third_party/maplibre-native-ffi/android-arm64-egl/` as an imported library, and packages it through `jniLibs`. Both libraries link `c++_static`. This is safe because only the C ABI crosses between them.
- 16 KB pages: NDK r28 and later link with 16 KB segment alignment by default. The emulator has 16 KB pages, so a misaligned library fails to load there. The tasks check the alignment with `llvm-readelf -l`.
- `scripts/maplibre_ffi.lock` gets `MAPLIBRE_FFI_ANDROID_PRESETS="android-arm64-egl"`. `build_maplibre_ffi.sh` builds Android presets with the NDK and `ANDROID_HOME`, installs them into `third_party/maplibre-native-ffi/<preset>/`, and leaves them out of the xcframework. It builds the verifier's AAR with the FFI's Gradle build (after the FFI's dependency sync, which provides the patched source) and installs it into a file-based Maven repository, `third_party/maplibre-native-ffi/android-maven/`, which the plugin's Gradle build adds as a repository.
- The plugin's `pubspec.yaml` adds the `android` platform with its package and `pluginClass`.

*Alternative for the verifier:* a direct `.aar` file dependency. The Android Gradle plugin rejects direct `.aar` dependencies in library modules when it builds an AAR.

### D58. Dart API and measurement functions

- `FrameCamera.displayTime` becomes `int?`. It is null when the event's `display_time_us` is negative. `MapTextureStats` gets `intervalWaits`.
- The documentation of `copyFree` states that it has no effect on Android.
- Android implementations of the measurement functions: thread count from `/proc/self/task`; memory footprint as the process's PSS from `/proc/self/smaps_rollup`; thermal state from `AThermal_getCurrentStatus` (API 30+, mapped NONE to 0, LIGHT and MODERATE to 1, SEVERE to 2, CRITICAL and above to 3; -1 on API 29); the released-buffer functions return 0, because the plugin owns no display buffers on Android.

### D59. Example, tests and benchmarks

- `example/android/` is created with `flutter create --platforms android`, with `minSdk` 29 and `arm64-v8a`.
- The integration tests run on the emulator. Tests that need display times (the display-time scenario, the timing probe) or plugin-owned buffers (the released-buffer test) are skipped on Android, and the reason is stated in the skip. The lifecycle tests use `map_texture_set_paused_for_testing` and `map_texture_reduce_memory_use_for_testing`, as on iOS. A test of the new requirement "Surface replacement and removal on Android" drives `onTrimMemory(TRIM_MEMORY_BACKGROUND)` through a test hook in the plugin.
- `example/lib/benchmark.dart` runs on Android unchanged in procedure. Its frame rate counts the frame events, which on Android are queued frames. `alignment_benchmark.dart` and `timing_probe.dart` print one line that they need display times and exit on Android.
- The emulator's GPU forwards to the Mac's, so frame rates from it are not recorded as measurements.

### D60. Stage 4 procedure on the reference device

When the Pixel is connected: record model, Android version, refresh rate, Flutter version and renderer (Impeller with Vulkan or OpenGL ES, from the `flutter run` log), FFI commit and build mode. Run the continuous pan (30 s, portrait, release) and the 5-minute run over central London, as on the iPhone. Measure the memory and the app size increase. Check alignment by hand on the `flutter_map` page with the default alignment, at the device's refresh rate. Prediction was only measured at 120 Hz. Record the results in `benchmarks.md` and the decision in roadmap row 4.

## Risks / Trade-offs

- [The Pixel runs Android 9 or earlier, below `minSdk` 29] → Then the reference device needs another decision before Stage 4 can be measured: another device, or support for the `SurfaceTexture` path. This change doesn't build that path.
- [Time-based pacing drifts against vsync and shows uneven frame intervals] → The benchmark reports p95 and p99 frame durations. `AChoreographer` pacing (D53, alternative) is the planned change.
- [Impeller on the Pixel uses OpenGL ES, and sampling the `HardwareBuffer` involves a copy inside Flutter] → The plugin's frame path has no copy and no CPU readback either way. The renderer is recorded with every measurement, as the concept document requires.
- [The emulator's GPU behaves differently from a device (EGL configs, driver bugs)] → Functional tests run on the emulator. Measurements and the manual check run only on the Pixel.
- [`@Native` resolution fails in release builds only, through tree shaking or symbol stripping] → D56 verifies in a release build. The plugin's exported symbols keep `visibility("default"), used`.
- [Two static libc++ copies in one process] → No C++ types, exceptions or allocations cross the C ABI between the plugin and the FFI.
- [`mln_android_init` keeps the application context's `AssetManager`] → It's called with the application context, which outlives every activity.

## Migration Plan

No migration for applications: the Dart API is the same, except that `FrameCamera.displayTime` is nullable. Rolling back means reverting this change. The Apple builds don't use the Android code.

## Open Questions

- The reference Pixel's model, Android version and refresh rate. They don't change the approach unless the Android version is below 10 (see Risks).
