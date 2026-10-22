## 1. Snapshot mode (D186)

- [ ] 1.1 Let `maplibre_ffi.lock` state the snapshot (`MAPLIBRE_FFI_VERSION=snapshot`) and add `scripts/fetch_ffi_snapshot.sh`, which downloads `MaplibreNativeC.xcframework.zip` of the FFI's `unstable-native-snapshot` release into `third_party/`, makes `Frameworks/MaplibreNativeC.xcframework` resolve to it, and prints the commit that the snapshot release states; verify that after the script, without a local FFI build, a macOS build of the test harness uses the snapshot's framework and doesn't check a checksum
- [ ] 1.2 In snapshot mode, make `android/build.gradle.kts` depend on `maplibre-native-ffi-runtime-opengl-android:0.1.0-SNAPSHOT` from the Maven snapshot repository and state the snapshot in its output; verify that an Android build of the test harness without a local FFI build resolves the snapshot runtime and prints that it uses the snapshot
- [ ] 1.3 Set `publish_to: none` in the package's `pubspec.yaml` and make `ffi_pins_test.dart` check, in snapshot mode, that the lock, `Package.swift` and `publish_to: none` agree; verify that `flutter pub publish` in the package directory refuses, and that `flutter test` passes in the package
- [ ] 1.4 Skip the comparison of `test/notices/ffi_notices_test.dart` in snapshot mode, and leave the notices of 0.202610.1 in place; verify that the test reports the skip and the notice files don't change
- [ ] 1.5 Make `scripts/consumer_build.sh` remove `publish_to` in a temporary copy before the dry run, and fetch the snapshot's framework into its copy of the package for iOS and macOS; verify that the script builds the consumer application for android, ios and macos on this Mac without a local FFI build, and that its checks of the APK and the Apple bundles pass
- [ ] 1.6 Set the lock to the snapshot, and describe snapshot mode, the fetch script and the release freeze in `CONTRIBUTING.md` next to the update to a release; verify that the steps in `CONTRIBUTING.md` build the test harness from a clean checkout

## 2. Native test target (D187)

- [ ] 2.1 Write a native test that creates a map thread's runtime, map and session against a headless FFI target on macOS (a session-owned Metal texture ring), renders one frame demand and disposes everything, linked against the snapshot or a local FFI build; verify that it passes locally, or record why it can't, and record the outcome of D187 (headless or fake) in design.md

## 3. Native core (D180, D181, D185, D189)

- [ ] 3.1 Port runtime and map creation, the session attachment with the caller-graphics-thread driver, the map thread's wait on its command queue with the session's wakes, style loading, events, log attribution, HTTP header rules, the cache size and teardown in `src/core/` to #760, without the experiment's `MLN760_*` diagnostics; verify that the test harness builds for macOS and shows a map with its style
- [ ] 3.2 Port rendering to frame demands, service calls and frame results, with the frame's camera from the result's view, camera commands with `mln_map_update_camera`, the wait for each camera command's completion, and each frame's `seq` from the completion's `render_update_generation`; verify on macOS that "camera change shows up in the frame camera" and "rapid camera updates do not build up a backlog" in `map_texture_test.dart` pass
- [ ] 3.3 Port pausing, memory reduction (queued while paused, run when rendering resumes) and the camera-to-frame latency statistic; verify on macOS that the pause tests and "memory reduction keeps the map rendering" in `map_texture_test.dart` pass, and that a memory reduction requested while paused is reported after resume

## 4. Metal target (D182, D183)

- [ ] 4.1 Port `MapTextureMetal.mm` to a borrowed ring of the 4 display buffers with frame acquisition and release, and the map with the copy to a ring of its render texture; verify on macOS that "idle copy-free map renders no frames for 10 seconds", "copy-free map renders frames without copies", "map with the copy renders frames with copies" and "idle map with the copy renders no frames for 10 seconds" pass, and that an alignment benchmark run reports frames in all 4 display slots
- [ ] 4.2 Port the resize: a barrier for an outstanding demand, the release of every acquired frame, the buffer swap with the fallback buffer, and the ring replacement; verify on macOS that "resizing on every frame for 10 seconds", "display buffers replaced by resizes are freed afterwards" and "resize keeps the selected frame until a new-size selection" pass

## 5. Android target (D184)

- [ ] 5.1 Port `map_texture_android.cpp` to #760's surface session, with the frame's presentation time and the scissor workaround before every service call, surface switches on replacement and park, and a new session after a lost target; verify on the Pixel 4a (5G) that `map_texture_test.dart` passes, including "resizing on every frame for 10 seconds" and "surface removal and restore keep the map and its style"

## 6. Native tests (D187)

- [ ] 6.1 Move the tests in `test/native/` to the target that task 2.1 chose: the headless FFI target, or a fake of the asynchronous API in place of `fake_mln.*`; verify that `ctest --test-dir build/native-tests` passes, and that the tests cover the map thread's commands, the camera's `seq`, the buffer states and teardown as the tests on `main` do

## 7. Docs (D179, D188)

- [ ] 7.1 Move `docs/maplibre-pr-760-port-findings.md` from the branch `experiment-maplibre-pr-760-port` (commit `a7be839`) to `docs/`, with a note at its top that it records the experiment and that its result lines are on that branch; verify that the links in design.md to the findings resolve on this branch
- [ ] 7.2 Update the docs that describe the synchronous FFI API or the FFI pin (`docs/maplibre-native-ffi-flutter-texture-concept.md`, `docs/limitations.md`, `CONTRIBUTING.md`) to #760's execution model; verify with `grep` that no doc outside `openspec/changes/archive/` and the findings names `mln_runtime_pump`, `mln_map_jump_to` or `mln_render_session_render_update` as current API

## 8. Verification

- [ ] 8.1 Run `map_texture_test.dart`, `map_layer_test.dart` and `engines_test.dart` (with `flutter drive`) on macOS, and `map_texture_test.dart` and `map_layer_test.dart` on the iOS simulator, the iPhone 15 Pro Max and the Pixel 4a (5G); verify that every test passes or is skipped as on `main`
- [ ] 8.2 Run the frame-rate benchmark on the Mac, the iPhone 15 Pro Max, the iPhone 13 and the Pixel 4a (5G), and the alignment benchmark (`ALIGNMENT_CHILDREN=1`, phases `pan100,pan500,pan1000,stop,fling,reverse`) on the Mac and the iPhone 15 Pro Max, 3 runs each, alternating with `main`, on cable power; verify that `docs/benchmarks.md` records the results against `main`, the drawn error is 0 px in every phase, and the frame rates are within the ranges of D188, or record each difference
- [ ] 8.3 Run the CI consumer build on the branch's pull request; verify that it passes against the snapshot
- [ ] 8.4 Run `openspec validate adopt-ffi-core-executor` and confirm that the delta specs describe the merged behavior; verify that validation passes
