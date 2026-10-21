After each task, record its result in `docs/maplibre-pr-760-port-findings.md`, under the question (Q1 to Q7 in design.md) that it answers, with the #760 commit it used.

## 1. Findings and baseline

- [x] 1.1 Create `docs/maplibre-pr-760-port-findings.md` with a section for each of Q1 to Q7, a section for the pinned commit and its changes, a section for complexity (what moved where, with line counts per area against `main`), a section for what broke, and a section for feedback for #760; verify that the file exists and names commit `3b56ef916`
- [x] 1.2 Add camera-to-frame latency to `map_texture_stats` and the benchmarks' output (D171) as the branch's first commit, before any change for #760, so that the commit still uses the released FFI and is the baseline; verify that the native tests pass, then run the frame-rate benchmark (`benchmark.dart`) and the alignment benchmark with `ALIGNMENT_CHILDREN=1` and the phases `pan100,pan500,pan1000,stop,fling,reverse` on macOS, 3 runs each, and verify that the findings document has the baseline numbers and the commit they were measured at

## 2. Build against #760

- [x] 2.1 Set `MAPLIBRE_FFI_COMMIT` to `3b56ef916` in `maplibre_ffi.lock` and build `macos-arm64-metal` with `scripts/build_maplibre_ffi.sh` (D166); verify that `third_party/maplibre-native-ffi/MaplibreNativeC.xcframework` contains the macOS slice, and record any change that the script or the build needed
- [x] 2.2 Build `android-arm64-egl` the same way; verify that the Android preset installs into `third_party/maplibre-native-ffi/android-arm64-egl/`, or record why it doesn't

## 3. macOS minimal port

- [x] 3.1 Port runtime and map creation, teardown, style loading, HTTP header rules, the cache size and events in `src/core/map_texture.cpp` to #760, and replace `mln_runtime_pump` with a loop that waits on the command queue, signaled by `driver_work_wake` and `frame_wake` (D167); verify that the plugin builds for macOS with `flutter build macos` in `packages/test_harness`
- [x] 3.2 Port rendering to `request_frame`, `service_driver_work` and `drain_frame_results`, with the frame's camera from `result.view` and `seq` from the generation of each `update_camera` completion (D169); verify that the test harness on macOS shows the map and reports frames with cameras
- [ ] 3.3 Port the Metal target in `MapTextureMetal.mm` to a borrowed ring of one texture replaced before each render (D168); verify that the map renders into all 4 display slots during a pan, or record why it doesn't and try the alternatives of D168 in order
- [x] 3.4 Port pausing, resizing, memory reduction and engine detach (Q6); verify with `map_texture_test.dart`, `map_layer_test.dart` and `engines_test.dart` (with `flutter drive`) on macOS, and record each failure that `main` doesn't have
- [x] 3.5 Find a way to report glyph load failures per map (Q4); verify with the glyph failure scenario of `map_layer_test.dart`, or record that #760 offers no way
- [x] 3.6 Add `scripts/patches/maplibre-native-ffi-760-same-size-retarget.patch` (D173) and rebuild `macos-arm64-metal` with it; verify that "idle map renders no frames for 10 seconds" and "idle copy-free map renders no frames for 10 seconds" in `map_texture_test.dart` and "metrics stay the same while the map is at rest" in `map_layer_test.dart` pass on macOS

## 4. Measure on macOS

- [ ] 4.1 Run the benchmarks of task 1.2 on the branch, 3 runs each, alternating with the baseline commit of task 1.2; verify that the findings document compares frame rate, frame cycle, alignment error, lag and camera-to-frame latency for both
- [ ] 4.2 Run the alignment benchmark with camera prediction turned off and on, at the baseline commit and on the branch; verify that the findings document states whether prediction still reduces the lag under #760 (Q2)

## 5. Android

- [ ] 5.1 Port the surface target in `map_texture_android.cpp` (D170), with `WillRender` before `service_driver_work`; verify that the test harness on the Pixel 4a (5G) shows the map and that each frame's image arrives with its frame id, and record in Q5 whether one service call ever renders more than one frame
- [ ] 5.2 Verify that parking on the pbuffer and window replacement work by stopping and resuming the activity during a pan, and run `map_texture_test.dart` and `map_layer_test.dart` on the Pixel; record each failure that `main` doesn't have
- [ ] 5.3 Run the frame-rate benchmark and the alignment benchmark on the Pixel, 3 runs each, at the baseline commit and on the branch; verify that the findings document compares them

## 6. iOS

- [ ] 6.1 Build `ios-arm64-metal` and `ios-simulator-arm64-metal` (D166) and the test harness for the iPhone; verify that the xcframework has all three slices and that the test harness on the iPhone 15 Pro Max shows the map and reports frames with cameras
- [x] 6.2 Run the frame-rate benchmark and the alignment benchmark (`ALIGNMENT_CHILDREN=1`, the phases of task 1.2) on the iPhone, 3 runs each, alternating between the baseline commit (built in a worktree without the local FFI build, so that it uses the released FFI) and the branch, with auto-lock off, on cable power, and the thermal state recorded at the start and end of each run; verify that the findings document compares frame rate, frame cycle, alignment error, lag and camera-to-frame latency for both
- [ ] 6.3 Run `map_texture_test.dart` and `map_layer_test.dart` on the iOS simulator; record each failure that the baseline commit doesn't have

## 7. Conclusions and feedback

- [ ] 7.1 Write the conclusions for Q1 to Q7 in the findings document, each stating whether the result comes from #760 or from the port's shortcuts (D172), and what the real port would need; verify that every question has an answer or is listed as open
- [ ] 7.2 Draft one upstream issue per request for #760 (at least slot count or per-frame target replacement, and synchronous execution with the latency numbers), each with the commit and measurements; verify that the drafts are in the findings document, ready for the user to review before anything is posted
- [ ] 7.3 Prepare a stacked pull request against #760 (base branch `sargunv/binding-codegen`) from the patch of D173, with a C test that a same-size borrowed replacement leaves an idle render-if-needed demand waiting, and a description that links maplibre-native-ffi#807 and the findings' measurements; verify that the branch builds and the FFI's tests pass, and leave it for the user to review before anything is pushed or opened
