## 1. FFI release 0.202610.2 (D186)

- [x] 1.1 Pin FFI release 0.202610.2 in `maplibre_ffi.lock` (version, the URL of `MaplibreNativeC.xcframework.zip` under the tag `v0.202610.2` with its `swift package compute-checksum` value, commit `a27e607357aef2cc9c9c89d10ebba7b3bde26fe8`) and run `scripts/update_ffi_pins.sh`, with no snapshot handling left from the earlier version of D186; verify that `ffi_pins_test.dart` passes, and that `flutter pub publish --dry-run` in a clean checkout reports no warnings
- [x] 1.2 Make `scripts/fetch_ffi_release.sh` build the release URL from `v<version>`, and download, check against `SHA256SUMS` and unpack the release's `MaplibreNativeC.xcframework.zip`; run it and `scripts/copy_ffi_notices.sh`; verify that `test/notices/ffi_notices_test.dart` runs its comparison and passes, and that the diff of `notices/` shows the changes of 0.202610.2
- [x] 1.3 Make the native tests link the fetched release's framework when no local FFI build exists; verify that `ctest --test-dir build/native-tests` passes in a checkout without a local build
- [x] 1.4 Update `CONTRIBUTING.md` for 0.202610.2: the pinned version, the release tag, and fetching the release before the native tests; verify that its steps build the test harness and the native tests from a clean checkout
- [x] 1.5 Run `scripts/consumer_build.sh` for android, ios and macos; verify that it passes against 0.202610.2

## 2. Native test target (D187)

- [x] 2.1 Write a native test that creates a map thread's runtime, map and session against a headless FFI target on macOS (a session-owned Metal texture ring), renders one frame demand and disposes everything, linked against the snapshot or a local FFI build; verify that it passes locally, or record why it can't, and record the outcome of D187 (headless or fake) in design.md

## 3. Native core (D180, D181, D185, D189)

- [x] 3.1 Port runtime and map creation, the session attachment with the caller-graphics-thread driver, the map thread's wait on its command queue with the session's wakes, style loading, events, log attribution, HTTP header rules, the cache size and teardown in `src/core/` to #760, without the experiment's `MLN760_*` diagnostics; verify that the test harness builds for macOS and shows a map with its style
- [x] 3.2 Port rendering to frame demands, service calls and frame results, with the frame's camera from the result's view, camera commands with `mln_map_update_camera`, the wait for each camera command's completion, and each frame's `seq` from the completion's `render_update_generation`; verify on macOS that "camera change shows up in the frame camera" and "rapid camera updates do not build up a backlog" in `map_texture_test.dart` pass
- [x] 3.3 Port pausing, memory reduction (queued while paused, run when rendering resumes) and the camera-to-frame latency statistic; verify on macOS that the pause tests and "memory reduction keeps the map rendering" in `map_texture_test.dart` pass, and that a memory reduction requested while paused is reported after resume

## 4. Metal target (D182, D183)

- [x] 4.1 Port `MapTextureMetal.mm` to a borrowed ring of the 4 display buffers with frame acquisition and release, and the map with the copy to a ring of its render texture; verify on macOS that "idle copy-free map renders no frames for 10 seconds", "copy-free map renders frames without copies", "map with the copy renders frames with copies" and "idle map with the copy renders no frames for 10 seconds" pass, that `core_tests` (the slot states of "Chosen slot is not overwritten") passes, that no render error "the session rendered into a slot that isn't free" occurs during `map_texture_test.dart`, and that a continuous pan displays frames from at least 3 display slots
- [x] 4.2 Port the resize: a barrier for an outstanding demand, the release of every acquired frame, the buffer swap with the fallback buffer, and the ring replacement; verify on macOS that "resizing on every frame for 10 seconds", "display buffers replaced by resizes are freed afterwards" and "resize keeps the selected frame until a new-size selection" pass

## 5. Android target (D184)

- [x] 5.1 Port `map_texture_android.cpp` to #760's surface session, with the frame's presentation time and the scissor workaround before every service call, surface switches on replacement and park, and a new session after a lost target; verify on the Pixel 4a (5G) that `map_texture_test.dart` passes, including "resizing on every frame for 10 seconds" and "surface removal and restore keep the map and its style"

## 6. Native tests (D187)

- [x] 6.1 Move the tests in `test/native/` to the target that task 2.1 chose: the headless FFI target, or a fake of the asynchronous API in place of `fake_mln.*`; verify that `ctest --test-dir build/native-tests` passes, and that the tests cover the map thread's commands, the camera's `seq`, the buffer states and teardown as the tests on `main` do

## 7. Docs (D179, D188)

- [x] 7.1 Move `docs/maplibre-pr-760-port-findings.md` from the branch `experiment-maplibre-pr-760-port` (commit `a7be839`) to `docs/`, with a note at its top that it records the experiment and that its result lines are on that branch; verify that the links in design.md to the findings resolve on this branch
- [x] 7.2 Update the docs that describe the synchronous FFI API or the FFI pin (`docs/maplibre-native-ffi-flutter-texture-concept.md`, `docs/limitations.md`, `CONTRIBUTING.md`) to #760's execution model; verify with `grep` that no doc outside `openspec/changes/archive/` and the findings names `mln_runtime_pump`, `mln_map_jump_to` or `mln_render_session_render_update` as current API

## 8. Verification

- [x] 8.1 Run `map_texture_test.dart`, `map_layer_test.dart` and `engines_test.dart` (with `flutter drive`) on macOS, and `map_texture_test.dart` and `map_layer_test.dart` on the iOS simulator, the iPhone 15 Pro Max and the Pixel 4a (5G); verify that every test passes or is skipped as on `main`
- [x] 8.2 Run the frame-rate benchmark on the Mac, the iPhone 15 Pro Max, the iPhone 13 and the Pixel 4a (5G), and the alignment benchmark (`ALIGNMENT_CHILDREN=1`, phases `pan100,pan500,pan1000,stop,fling,reverse`) on the Mac, the iPhone 15 Pro Max and the iPhone 13, 3 runs each, alternating with `main`, on cable power where available (the iPhone 15 Pro Max ran over Wi-Fi); verify that `docs/benchmarks.md` records the results against `main`, the drawn error is 0 px in every phase, and the frame rates are within the ranges of D188, or record each difference
- [x] 8.3 Run the CI consumer build on the branch's pull request; verify that it passes against 0.202610.2
- [x] 8.4 Run `openspec validate adopt-ffi-core-executor` and confirm that the delta specs describe the merged behavior; verify that validation passes
