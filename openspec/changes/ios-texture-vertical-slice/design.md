## Context

See proposal.md for motivation and scope, and specs/map-texture/spec.md for the requirements. The macOS design (`openspec/changes/archive/2026-10-09-macos-texture-vertical-slice/design.md`, decisions D1 to D10) applies unchanged unless a decision below amends it. Decisions here are numbered from D11.

Current state, as checked in this repository on 2026-10-09:

- The plugin's Apple code is in `packages/flutter_map_maplibre_texture/macos/flutter_map_maplibre_texture/`, a Swift package with `FlutterMapMaplibreTexturePlugin.mm`, `MapTextureMetal.mm` and `MapTextureRegistry.h`. `Sources/.../core` is a symlink to `src/core/`, and `Frameworks/MapLibreNativeC.xcframework` is a symlink to the build output in `third_party/`. The only macOS-specific APIs in these files are the `FlutterMacOS` import and `NSCachesDirectory` (which also exists on iOS). `CVPixelBuffer`, IOSurface, `CVMetalTextureCache`, `MTLBlitCommandEncoder`, `FlutterTexture` and `mach` thread enumeration are available on iOS.
- `src/core/` has no Apple dependencies. `map_texture_api.cpp` keeps all live maps in a handle registry.
- `scripts/build_maplibre_ffi.sh` builds one preset (`macos-arm64-metal`) and wraps the dylib in a versioned macOS framework inside `MapLibreNativeC.xcframework`.

Facts checked in MapLibre Native FFI at commit `dd97d20f8fab6990cd87c13f091ce00e662707bd`:

- `CMakePresets.json` has `ios-arm64-metal` (sysroot `iphoneos`) and `ios-simulator-arm64-metal` (sysroot `iphonesimulator`), both with `CMAKE_OSX_DEPLOYMENT_TARGET` 15.5.
- `cmake/platform/apple.cmake` sets `MLN_FFI_SHARED_SUPPORTED` for all Apple platforms, so the iOS presets build a shared library (and a static archive). Apple builds don't link the Rust platform component.
- `mln_render_session_reduce_memory_use(session)` asks the renderer to release cached resources. It must be called on the session's owner thread, which is the map thread (D2).
- The FFI's own Swift package runs its tests on the iOS simulator (`MaplibreNativeFFIIOSSimulatorTests`), so the library runs there.

Platform constraint: iOS doesn't allow an app to submit GPU work while it is in the background. A Metal command buffer committed in the background fails with a "background execution not permitted" error, and the system can terminate an app that keeps trying. Flutter's iOS engine itself disables its GPU work when the app enters the background and enables it again before the app enters the foreground.

## Goals / Non-Goals

**Goals:**
- One set of Apple bridge sources for macOS and iOS, so that fixes apply to both.
- A pause mechanism and a memory-reduction command in the platform-neutral core, which the Android slice can drive from its own lifecycle callbacks.
- Device measurements that are comparable with the macOS benchmark (same procedure, same style, same pan speed).

**Non-Goals:**
- Changing the Dart API. Lifecycle handling is native and needs nothing from the application.
- Recreating the map after a device pixel ratio change. iPhones have one fixed ratio.
- Optimizing for the iOS simulator. It is a functional test platform only.

## Decisions

### D11. Shared `darwin/` sources

Move `macos/flutter_map_maplibre_texture/` to `darwin/flutter_map_maplibre_texture/` and set `sharedDarwinSource: true` for both `ios` and `macos` in the plugin's `pubspec.yaml`. `Package.swift` declares `.macOS("14.3")` and `.iOS("15.5")`. The bridge sources import Flutter as:

```objc
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
```

The iOS-only code (D13, D14) is in `#if TARGET_OS_IOS` blocks or in a separate `MapTextureLifecycleIOS.mm` that compiles to nothing on macOS. The plugin class keeps the registrar's texture registry on both platforms.

*Alternative:* separate `ios/` and `macos/` directories, with the shared `.mm` files symlinked into both. We rejected it. Flutter supports shared Darwin sources for Swift Package Manager plugins, and two packages that point at the same files through symlinks are harder to follow than one package with a few conditionals.

### D12. One xcframework with three slices

`scripts/build_maplibre_ffi.sh` builds `macos-arm64-metal`, `ios-arm64-metal` and `ios-simulator-arm64-metal` from the same checkout, each into its own build directory, and installs each into `third_party/maplibre-native-ffi/<preset>/`. It wraps each dylib in a framework and combines the three frameworks with `xcodebuild -create-xcframework` into `third_party/maplibre-native-ffi/MapLibreNativeC.xcframework`, which is the path the existing symlink uses. The macOS framework keeps its versioned layout. The iOS and simulator frameworks use the flat iOS layout (binary, `Headers/`, `Modules/` and `Info.plist` at the framework root), with `MinimumOSVersion` 15.5 in `Info.plist`. The lock file lists the three presets. A preset can be selected with an argument, so that a developer who works on one platform doesn't have to build all three.

The FFI stays a dynamic framework on iOS, as on macOS. Xcode embeds and signs it in `Runner.app/Frameworks/`.

*Alternative:* link the FFI's complete static archive on iOS. It removes the embedded framework and lets the linker drop unused code, which may reduce app size. We rejected it for this slice, because it makes iOS packaging differ from macOS, and the static archive's system dependencies would have to be listed in `Package.swift` (the FFI's install metadata lists them). We record the dynamic framework's size (task 6.3), and can reconsider if the size matters for the decision.

### D13. Pause rendering in the background

The core gets a pause state for each map:

- `MapTexture::SetPaused(bool paused)`: callable from any thread. Pausing sets a flag under a mutex, then waits until the map thread is not inside a render (`render_update` plus `CopyToBuffer`). When it returns, the map thread doesn't submit GPU work until resumed. Resuming clears the flag and signals the wake source.
- The map thread checks the flag under the same mutex before it starts a render. While paused, it keeps running its loop: it pumps the runtime, applies commands and the camera slot, and drains events, but `MaybeRender()` returns without rendering and leaves `render_pending_` set. After resume, the next loop iteration renders with the latest camera, which satisfies the "camera set while in the background" scenario.
- Resize while paused allocates buffers but doesn't render. Allocating Metal textures and pixel buffers isn't GPU command submission, so it is allowed in the background.
- Dispose while paused works without change: the map thread stops, destroys the session, map and runtime, and releases buffers. None of that submits command buffers.

A function in `map_texture_api.cpp`, `map_texture::SetAllPaused(bool)`, applies the state to every map in the handle registry, and a newly created map starts paused if the process is currently paused.

On iOS, the plugin observes `UIApplicationDidEnterBackgroundNotification` and calls `SetAllPaused(true)` on the main thread before the notification handler returns, and observes `UIApplicationWillEnterForegroundNotification` and calls `SetAllPaused(false)`. This matches the points where Flutter's iOS engine disables and enables its own GPU work. The wait in `SetAllPaused(true)` is bounded by one render, which took 2.74 ms on average on the reference Mac.

*Result (tasks 4.1, 5.3 and 5.4, 2026-10-10):* on the iPhone 15 Pro Max, a release build panning continuously over San Francisco with Metal API validation enabled was sent to the background 20 times by launching Settings through `devicectl`, and 3 times with the home gesture. Both observers fired every time. `SetAllPaused(true)` blocked the main thread for 1.9 ms on average and 8.9 ms at most (21 transitions), the duration of the render in progress; with an idle map it returned in 1 to 2 µs. The rendered-frame count logged at each pause equalled the count logged before the following resume, so no frame was rendered in the background, and rendering resumed after each return (about 550 frames per 5 s in the foreground). The device log had no Metal background execution errors and no render errors. Because the example uses the scene lifecycle, the plugin also pauses at registration if the app is launched in the background (for example while the device is locked), when no did-enter-background notification arrives.

*Alternative:* pause from Dart, through `AppLifecycleListener` and a new C ABI call. We rejected it. Dart receives the lifecycle change asynchronously through a platform channel, so the map thread could still commit a frame after the app has entered the background. The native notification runs synchronously before the app is suspended.

*Alternative:* rely on Flutter no longer calling `copyPixelBuffer` in the background, which stops the map thread through the display pacing in D4. We rejected it. The pacing allows one more render after the last frame Flutter took, and that render would be GPU work in the background.

### D14. Memory warnings

The core gets a `ReduceMemoryUse` command in the ordered command queue (D5). The map thread handles it by calling `mln_render_session_reduce_memory_use(session_)` and ignoring `MLN_STATUS_INVALID_STATE` (no renderer yet). `map_texture::ReduceAllMemoryUse()` queues it for every map in the registry. On iOS, the plugin observes `UIApplicationDidReceiveMemoryWarningNotification` and calls it. It doesn't clear the tile cache database: that is on disk and doesn't count toward the app's memory.

*Alternative:* `mln_render_session_clear_data()`, which drops all renderer data and rebuilds it on the next frame. We rejected it as the response to a warning, because it forces a visible reload of the map. `reduce_memory_use` releases only what the renderer can spare.

### D15. Test hooks for lifecycle behavior

Integration tests can't send the app to the background or raise a memory warning. The C ABI gets two functions for tests, `map_texture_set_paused_for_testing(int32_t paused)` and `map_texture_reduce_memory_use_for_testing(void)`, which call `SetAllPaused` and `ReduceAllMemoryUse`, the same functions the notification observers call. The integration tests use them on every platform. The real notifications are verified by hand on the iPhone (task 5.4), because only that exercises the iOS background restrictions.

### D16. Symbol resolution for `@Native` on iOS

Dart binds the C ABI with `@Native` declarations resolved from the process (D5). On iOS, Swift Package Manager links the plugin as a static library into the `Runner` executable, so the `map_texture_*` functions must stay in the executable's export table in release builds, where the linker dead-strips unreferenced code and Xcode strips symbols. `MAP_TEXTURE_EXPORT` already marks them `visibility("default")` and `used`. Task 2.4 verifies a release build on the iPhone. If the symbols are missing, the fallback is to reference every exported function from the plugin's `+registerWithRegistrar:` (a table of function pointers), which keeps them through dead-stripping, and to check the example's `STRIP_STYLE`.

### D17. iOS measurement

- Device: the reference iPhone is an iPhone 15 Pro Max (iPhone16,2), with a 120 Hz ProMotion display. If an iPhone XR (iPhone11,8, 60 Hz, A12) is available, the benchmark is also run on it as a slower GPU, and the result is reported but isn't part of the go/no-go.
- Flutter on iOS limits frames to 60 Hz on ProMotion devices unless `Info.plist` sets `CADisableMinimumFrameDurationOnPhone` to true. The example sets it, and `benchmarks.md` records the measured vsync interval.
- Scenario: the same benchmark mode as macOS (`--dart-define=BENCHMARK=true`, same style, start position, zoom, pan speed in viewport widths per second, warm-up pass, measured 30 s pass), with the map full screen in portrait orientation. The app is started with `flutter run --release` and the `BENCHMARK_RESULT` line is read from the device log.
- Sustained run: a 5-minute continuous pan, recording `ProcessInfo.thermalState` at the start and end and the displayed frame rate for each 30 s interval. The concept doc lists thermal state as a metric; a short run on a phone doesn't show throttling.
- GPU time and readback check: a Metal System Trace on the device, as on macOS.
- App size: the size of `Runner.app` for a release build of the `flutter create` template app and of the example, measured the same way as for macOS in `limitations.md`.

### D18. Releasing replaced display buffers (amendment, 2026-10-10)

Found on the iPhone: every resize kept the replaced buffer set alive until the map was disposed. Three causes, measured by counting the released buffers' IOSurfaces that are still alive (details and measurements in `docs/flutter-texture-cache-followup.md`):

- The map thread is a `std::thread` with no autorelease pool, so each frame's autoreleased command buffer, and the buffer it copied into, stayed alive until the thread exited. *Change:* the core runs the map thread's setup, each loop iteration and teardown through `RunInPlatformScope()`, a platform function declared in `render_target.h`; on Apple platforms it is an `@autoreleasepool`.
- The bridge wrapped its buffers through its own `CVMetalTextureCache`, which keeps an IOSurface alive until the cache has been idle longer than its maximum age (1 s) and is used or flushed again. *Change:* the bridge creates each buffer's `MTLTexture` directly from its IOSurface (`newTextureWithDescriptor:iosurface:plane:`). This amends D3/D3b, which named `CVMetalTextureCache`.
- Flutter's Darwin embedders wrap each pixel buffer through their own `CVMetalTextureCache` in the same way and don't flush it per frame. *Workaround:* 1.1 s after the last resize, the core calls `RenderTarget::FrameAvailable()` once more, so that Flutter creates a texture after an idle period longer than the cache's maximum age and frees the aged entries. This doesn't help during a long continuous resize. The proper fix belongs in Flutter.

*Alternatives considered:* reusing buffer sets per size, and allocating buffers only after the size is stable. Both reduce how many buffers Flutter's cache sees but leave the causes in place; the first two causes are in the plugin and are fixed instead.

### D19. Render ahead while a frame takes longer than a refresh interval (amendment, 2026-10-10)

Over central London the iPhone displayed 40 to 57 map frames per second at the median second, depending on the run. The timing breakdown (stats `frame_cycle`, `pickup_wait`, `present_to_render`) showed where a frame's time went: `render_update` plus the copy, then the wait until Flutter took the frame at its next vsync (about 4 to 5 ms), and from then 0.1 ms until the next render started. Because the next frame started only after Flutter had taken the previous one (D4 amendment), a frame that takes longer than one refresh interval waits for the next vsync before the following frame can start.

A Metal System Trace showed a second effect. With this pacing the GPU idled between frames, and it ran in its minimum performance state for the whole 14 s trace; `render_update` took about 17 ms. Rendering the next frame without waiting kept the GPU busy, it ran in the medium or maximum state 80% of the time, and `render_update` took 8.4 ms for the same frames. The paced map is bistable: runs settled at either about 57 or about 40 fps.

*Change:* the map thread renders the next frame without waiting for Flutter to take the latest one while a frame (the smoothed `render_update` plus copy) costs more than a display refresh interval, and goes back to pacing when it costs less than 3/4 of one. `MapTextureView` passes the display's refresh rate (`Display.refreshRate`) to the core. A frame Flutter hasn't taken yet can then be replaced; about 1% of rendered frames weren't displayed. Faster rendering, as on the Mac (5.7 ms at 120 Hz), stays paced, so the map doesn't render frames that the display can't show. Result on the iPhone over London (2 runs): per-second p10 87, p50 99 to 100, p90 105, lowest second 85, against 33 to 37 / 40 / 53 to 57 with pacing in the same session.

*Alternative tried and rejected:* a render thread that owns the render session, with the map thread keeping the runtime and the map (D2, alternative, as in the FFI's pump-thread example). The FFI waits for the GPU inside `render_update`, so a render thread cannot overlap the encoding of one frame with the GPU work of the previous one; it can only remove the map thread's work between frames, which measured 0.08 ms on the iPhone and 0.14 ms on the Mac. Measured over London (3 runs), it displayed 40 to 52 fps at the median second, with `render_update` at 14 to 18 ms, no better than the paced single thread. A user-interactive QoS class for the map thread (2 runs) gave 40 fps. Both were removed.

### D20. Rendering directly into the display buffers (experiment, 2026-10-10)

The reason for the copy (D3b) is in the FFI: `render_session_set_target()` treats every target change as a resize. It resets the session's record of the rendered update and posts the size to the map, which then publishes a new render update, so switching among the display buffers before each frame made the map render without end. A local patch (`scripts/patches/maplibre-native-ffi-set-target-same-extent.patch`, applied by the build script) skips posting the size to the map when the logical width and height are unchanged; the session still resets its rendered state, so the next `render_update` draws the current map state into the new texture. (A first version that also kept the rendered state ended the loop too, but a host replacing a texture at the same size would then get no frame until the map changed; the measurements below used that first version.) With it, the bridge can make the free display buffer the session's target before each render (`RenderTarget::SelectBuffer`) and skip the copy; the integration suite and the color check pass on macOS in this mode, and the idle map renders no frames.

Measured on the iPhone over London (2 runs each): paced and copy-free, per-second p50 60 fps (11.3 ms `render_update`), against 40 with the copy; rendering ahead and copy-free, p50 96 to 99, the same as with the copy, because a copy-free frame cost (8.3 ms) is close to the 8.33 ms refresh interval and the map switched between rendering ahead and pacing. That run predates the hysteresis in D19.

*Result with the hysteresis (2026-10-10, 2 runs each, rendering ahead):* copy-free, per-second p10 105 to 106, p50 109 to 111, p90 116 to 117, lowest second 102 to 103, frame cycle 8.2 to 8.4 ms (`render_update` 7.8 ms); with the copy in the same session, p10 86 to 89, p50 102 to 103, p90 109 to 110, lowest second 84 to 86, frame cycle 9.8 ms. Removing the copy raises the slowest seconds by about 18 fps and the median second by about 8. A copy-free frame costs a little less than a refresh interval, so the map sometimes finishes a frame before Flutter has taken the previous one: 8% of rendered frames weren't displayed, against 2.4% with the copy. The Metal backend drops its renderable on each target change, so the depth and stencil textures are reallocated every frame; this is included in the measured `render_update`. The mode stays an experiment (`map_texture_set_zero_copy_for_testing`) until we decide whether to carry the FFI patch and offer it upstream.

## Risks / Trade-offs

- [The iOS embedder may hold a returned `CVPixelBuffer` longer than the macOS embedder] → Three buffers and "skip when no buffer is free" (D4) still prevent overwriting; the benchmark reports skipped renders. Increase to four buffers if skips are frequent.
- [`textureFrameAvailable:` threading differs on iOS] → The bridge already dispatches to the main queue (task 3.4 of the macOS slice), which is correct on either platform.
- [GPU work in the background from a source other than `render_update`, for example a style or tile load that triggers a renderer upload] → In this design all MapLibre GPU work happens inside `render_update` on the map thread, which the pause blocks. Task 5.4 runs the background scenario with Metal API validation and checks the device log for background execution errors.
- [The pause wait on the main thread delays the app's transition to the background] → The wait is bounded by one render. Task 5.3 measures it; if it exceeds a few milliseconds, record it.
- [Scene-based app lifecycle] → If the example uses `UIScene`, the `UIApplication` background and foreground notifications are still posted when the app's last scene changes state. Task 5.4 verifies the observers fire in the example as generated by Flutter 3.47.5.
- [Thermal throttling reduces the frame rate in sustained use] → The 5-minute run measures it. A result below 30 fps after throttling is reported as a finding, and the Stage 2 decision takes it into account.
- [The xcframework triples the FFI build time] → The build script accepts a preset argument (D12), and the README states the time for each preset.
- [Moving `macos/` to `darwin/` breaks the macOS build] → Task 1.3 rebuilds macOS and reruns the macOS integration tests before any iOS code is added.

## Migration Plan

There are no users of the package besides the example. The move from `macos/` to `darwin/` is done in one commit with a macOS rebuild and test run (task group 1), so that a regression on macOS is found before iOS work starts. A rollback is a revert of that commit.

## Open Questions

- Whether `mln_render_session_reduce_memory_use` releases a measurable amount of memory on iOS. This doesn't change the design; task 5.5 records the memory before and after a warning.
