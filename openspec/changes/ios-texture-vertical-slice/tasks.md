## 1. Shared Darwin sources (D11)

- [x] 1.1 Move `packages/flutter_map_maplibre_texture/macos/flutter_map_maplibre_texture/` to `darwin/flutter_map_maplibre_texture/` with `git mv`, keep the `core` and `Frameworks/MapLibreNativeC.xcframework` symlinks working from the new location, and set `sharedDarwinSource: true` for `macos` (no `ios` entry yet) in the plugin's `pubspec.yaml`; verify that `ls -l` resolves both symlinks
- [x] 1.2 Replace the `FlutterMacOS` imports in the bridge sources and the public header with the `TARGET_OS_OSX` conditional import from D11; verify that `flutter analyze` passes and that the macOS example builds with `flutter build macos`
- [x] 1.3 Rerun the macOS integration tests (`flutter test integration_test -d macos`) and the native core tests after the move; verify that all of them pass before any iOS code is added, and commit the move on its own

## 2. iOS build and packaging (D12, D16)

- [x] 2.1 Extend `scripts/build_maplibre_ffi.sh` and `scripts/maplibre_ffi.lock` to build `macos-arm64-metal`, `ios-arm64-metal` and `ios-simulator-arm64-metal` into `third_party/maplibre-native-ffi/<preset>/`, wrap the iOS and simulator dylibs in flat frameworks with `MinimumOSVersion` 15.5, and combine all three into `MapLibreNativeC.xcframework`; accept an optional preset argument; verify that a clean run produces an xcframework whose `Info.plist` lists the `macos-arm64`, `ios-arm64` and `ios-arm64-simulator` libraries, and record the build time per preset
- [x] 2.2 Add `.iOS("15.5")` to `Package.swift`, add the `ios` platform with `pluginClass` and `sharedDarwinSource: true` to the plugin's `pubspec.yaml`, and add the iOS target to the example with `flutter create --platforms=ios .`, deployment target 15.5 and `CADisableMinimumFrameDurationOnPhone` set to true in `Info.plist` (D17); verify that `flutter build ios --simulator` succeeds and that macOS still builds
- [x] 2.3 Run the example on the iOS simulator (`flutter run -d <simulator>`); verify that the map appears, that the control panel is drawn above it and responds, and that the style switch and the invalid-style option work
- [ ] 2.4 Build the example in release mode for the iPhone 15 Pro Max (`flutter run --release -d <device>`) and run it; verify that the map appears (which shows that every `@Native` symbol resolved) and that `otool -L` on the app executable shows `MapLibreNativeC.framework` loaded from `@rpath` inside `Runner.app/Frameworks/`; if a symbol fails to resolve, apply the fallback in D16 and record which one was needed

## 3. Core: pause and memory reduction (D13, D14, D15)

- [x] 3.1 Implement the pause gate from D13 as a class in `src/core/` with no MapLibre dependency (pause waits for an in-progress render; a render doesn't start while paused; resume allows renders again) and use it in `MapTexture::MaybeRender()`; add C++ unit tests for the gate, including a pause that arrives during a render, and verify that they pass
- [x] 3.2 Add `MapTexture::SetPaused()`, `map_texture::SetAllPaused()` over the handle registry, and start new maps paused while the process is paused; verify with a native unit test or the integration test in 5.1 that `rendered_frames` doesn't increase while paused and that a camera set while paused is rendered after resume
- [x] 3.3 Add the `ReduceMemoryUse` command to the command queue and `map_texture::ReduceAllMemoryUse()`; the map thread calls `mln_render_session_reduce_memory_use()` and ignores `MLN_STATUS_INVALID_STATE`; verify with the command queue unit tests that the command is ordered with style and resize commands
- [x] 3.4 Add `map_texture_set_paused_for_testing` and `map_texture_reduce_memory_use_for_testing` to the C ABI and bind them in Dart, outside the public exports; verify that `flutter analyze` passes and that the boundary test (D9) still passes

## 4. iOS bridge

- [ ] 4.1 Observe `UIApplicationDidEnterBackgroundNotification` and `UIApplicationWillEnterForegroundNotification` in the iOS code path of the plugin and call `SetAllPaused(true)` and `SetAllPaused(false)` on the main thread (D13); verify by logging on the iPhone that both observers fire when the app is sent to the background and brought back
- [x] 4.2 Observe `UIApplicationDidReceiveMemoryWarningNotification` and call `ReduceAllMemoryUse()` (D14); verify with the simulator's Simulate Memory Warning command that the map thread calls `mln_render_session_reduce_memory_use()` and that the map keeps rendering
- [ ] 4.3 Run the color check (`example/lib/color_check.dart`) on the iPhone; verify that map colors match Flutter's within 2/255 per channel, and set the IOSurface color space explicitly if they don't

## 5. Verification

- [ ] 5.1 Add integration tests for the new spec scenarios using the test hooks (camera changes while paused, camera set while paused is displayed after resume, dispose while paused, memory reduction followed by a displayed frame), and run the whole suite on macOS, on the iOS simulator and on the iPhone (`flutter test integration_test -d <device>`); verify that all tests pass on all three
- [ ] 5.2 Rotate the iPhone between portrait and landscape with the map full screen, 10 times; verify that the map fills the new bounds without stretching after each rotation, and that the app doesn't crash
- [ ] 5.3 Measure the time `SetAllPaused(true)` blocks the main thread during continuous pan on the iPhone, over at least 20 transitions to the background; record the average and maximum in design.md
- [ ] 5.4 On the iPhone, with Metal API validation enabled in the Runner scheme, send the app to the background during continuous pan 10 times (home gesture, and by launching another app with `xcrun devicectl device process launch`), each time for at least 10 s; verify that the device log has no Metal background execution errors and no render error events, that the rendered-frame counter doesn't increase in the background, and that frames resume in the foreground
- [ ] 5.5 Record the app's memory (Xcode memory gauge or `footprint`) on the iPhone before and after a memory warning, with the map displayed after a pan over several zoom levels; record the result in `limitations.md`
- [ ] 5.6 Verify the idle scenario on the iPhone: after the map reaches idle, the rendered-frame counter doesn't increase over 10 seconds
- [ ] 5.7 Capture a Metal System Trace on the iPhone during continuous pan and confirm that there is no CPU readback, as in task 7.3 of the macOS slice; record the evidence in `benchmarks.md`

## 6. Measurement (D17)

- [ ] 6.1 Run the benchmark on the iPhone 15 Pro Max in a release build, full screen in portrait, and record in `benchmarks.md` the median, p95 and p99 displayed map frame intervals, the displayed map frame rate, the Flutter vsync interval, `render_update` and copy times, skipped renders, and the device, iOS, Xcode, Flutter and FFI versions; state the result against the 30 fps minimum and the 60 fps target
- [ ] 6.2 Run the 5-minute sustained pan on the iPhone 15 Pro Max and record the displayed frame rate for each 30 s interval and the thermal state at the start and end in `benchmarks.md`
- [ ] 6.3 Measure the release `Runner.app` size of the `flutter create` template app and of the example on iOS, and the size of `MapLibreNativeC.framework` in it; record them in `limitations.md` next to the macOS numbers
- [ ] 6.4 If the iPhone XR is available, run the benchmark from 6.1 on it and record the result in `benchmarks.md` as a slower-GPU data point outside the go/no-go; otherwise record that it wasn't run

## 7. Documentation and decision

- [ ] 7.1 Update the README for iOS: prerequisites (iOS SDK, simulator runtime, signing), the build script's presets, the `darwin/` layout, and exact commands for the simulator, the device and the benchmark; verify by following the iOS commands from a clean clone
- [ ] 7.2 Update `limitations.md`: iOS limitations and findings, the pause wait, memory warning results, app size on iOS, and what the Android slice can reuse from the core (pause gate and memory reduction command)
- [ ] 7.3 Before archiving, edit the Purpose of `openspec/specs/map-texture/spec.md` to say that the capability is specified for macOS and iOS
- [ ] 7.4 Record the Stage 2 decision (continue, adopt an existing solution, or stop) with the measured numbers in the Decision column of the roadmap in `docs/maplibre-native-ffi-flutter-texture-concept.md`
