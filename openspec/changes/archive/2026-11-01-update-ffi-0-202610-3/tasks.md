## 1. FFI pin

- [x] 1.1 Set `MAPLIBRE_FFI_VERSION` to 0.202610.3, `MAPLIBRE_FFI_COMMIT` to `6c065d9613438bea56ad67d706c4893df14a2b32`, `MAPLIBRE_FFI_XCFRAMEWORK_URL` to the release's `MaplibreNativeC.xcframework.zip` and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` to its `swift package compute-checksum` in `packages/flutter_mapigrade/maplibre_ffi.lock`, and run `scripts/update_ffi_pins.sh`; verify that `test/ffi_pins_test.dart` passes and that `Package.swift` names the new URL and checksum
- [x] 1.2 Run `scripts/fetch_ffi_release.sh`; verify that it checks every tarball and the xcframework zip against `SHA256SUMS` and unpacks the framework
- [x] 1.3 Rewrite `scripts/copy_ffi_notices.sh` to copy every notice file of the tarballs without a table, and to replace `notices/` as a whole (D217); verify that it runs for 0.202610.3, that the diff of `packages/flutter_mapigrade/notices/` removes the three Android files D208 names and changes `android/rust.md`, and that it fails for two notice files with the same name and different content
- [x] 1.4 Make `lib/src/notices/third_party_notices.dart` list the notice assets from the asset manifest, with a table of known names and the file name as fallback, and register them through one `dartPluginClass`, `MapigradeNotices`, in the package's `pubspec.yaml` (D217); verify that `flutter analyze` reports no issues
- [x] 1.5 Rewrite `test/notices/third_party_notices_test.dart` to check the entries against the files in `notices/`, and make `test/notices/ffi_notices_test.dart` also fail for a file in `notices/` that no tarball contains (D217); verify that both pass, and that no test names a notice file
- [x] 1.6 Rewrite `packages/test_harness/integration_test/notices_test.dart` to check the registry against the notice assets of the build (D217); verify that it passes on macOS here, and on the iOS simulator and the Android emulator in task 6.1
  - 2026-11-01: passed on macOS, on the iOS simulator (iPhone 17) and on the Android emulator (Pixel_10a AVD, API 37).

## 2. Core port

- [x] 2.1 Port `src/core/` to the 0.202610.3 C API: renames, zeroed option structs (D209), `out_map` (D212), `mln_render_session_dispose` and the frame result view (D213), the `mln_camera` record, and the log callback signature (D214); verify that `map_texture.cpp` and `map_texture_api.cpp` compile against the 0.202610.3 headers without errors or warnings
  - 2026-11-01: both compile without errors. With `-Wall -Wextra`, `map_texture.cpp` has the same 6 unused-parameter warnings as `main` against 0.202610.2, and no new ones; `mln_wake` has a new `queue` member, which the core sets to `MLN_HANDLE_NULL`.
- [x] 2.2 Set `MLN_FRAME_DEMAND_FORCE` for unconditional demands (D210); verify with a native test that a paint transition renders more than one frame without a camera change
  - 2026-11-01: `StyleTransitionRendersMoreThanOneFrame` loads a style with a 500 ms transition and checks that it renders more than one frame. That check alone also passed with flags 0, the defect D210 describes, as did the whole native suite: MapLibre publishes a map update for each frame of the transition, so its demands render with or without `FORCE`. The test therefore also checks the demand flags that the core passes to the FFI, recorded by a wrapper of `mln_render_session_request_frame` (as D187 records other calls): at least one demand during the transition carries `FORCE`, and none carries `FORCE` with `WAIT_FOR_UPDATE`. With flags 0 the test fails; with D210 it passes.
- [x] 2.3 Set `MLN_MAP_OPTION_EVENT_MASK` in the map options (D211); verify with a native test that the event handler receives no camera events while the camera changes
  - 2026-11-01: `CameraChangesDeliverNoCameraEvents` records the event types that the FFI delivers through a wrapper of `mln_runtime_set_event_handler`. It passes with the field bit, and fails without it, with camera events.
- [x] 2.4 Check each 0.202610.2 default that wasn't zero against the 0.202610.3 meaning of zero (D209), and set the members whose meaning changed; verify by listing each member and its outcome in this task
  - Map options: `initial_extent` 256x256 at scale 1 — the core sets it; `map_mode` CONTINUOUS is 0; `event_mask` all — the core sets its mask with `MLN_MAP_OPTION_EVENT_MASK` (D211).
  - Attach options: `driver` — the core sets it, and it is required; `requested_texture_ring_depth` 2 — zero selects 2, and borrowed rings ignore it; `producer_sync_kind` CPU_COMPLETE is 0.
  - Camera update: `mode` JUMP and `gesture_phase` NONE are 0; `camera.size` is set.
  - Frame demand: `MLN_FRAME_DEMAND_IF_NEEDED` — replaced by D210.
  - GPU sync: CPU_COMPLETE — a null `consumer_completion` now means CPU completion.
  - HTTP header rule: `kinds` all — the core sets `MLN_RESOURCE_KIND_FLAG_ALL`.
  - Metal borrowed descriptor (glue): extent and physical size 256 — the glue sets them.
  - Metal owned descriptor (native tests only): `pixel_format` RGBA8 — required in 0.202610.3, so the tests set `MTLPixelFormatRGBA8Unorm` (task 3.2).
  - OpenGL surface descriptor (Android glue): extent 256 — the glue sets it; context `platform`, `ownership` and `client_api` — the glue sets them.
  - Runtime options, rendered feature query options and GeoJSON source options: the 0.202610.2 defaults were zero.

## 3. Platform glue and native tests

- [x] 3.1 Port `MapTextureMetal.mm` and `android/src/main/cpp/map_texture_android.cpp`; verify that the example builds for macOS, iOS (`--no-codesign`) and Android
- [x] 3.2 Port `test/native/` (`ffi_headless_test.mm`, `ffi_wrappers.*`, `ffi_redirect.h`, `map_texture_tests.mm`), including the interposed functions that were renamed; verify that `ctest --test-dir build/native-tests` passes
- [x] 3.3 Run `flutter test` in `packages/flutter_mapigrade`; verify that it passes

## 4. Android cleartext HTTP

- [x] 4.1 Add the network security configuration that allows cleartext traffic to `127.0.0.1` only to the test harness, and name it in its manifest (D215); verify that the existing tests in `resource_test.dart` pass on the Android emulator
  - 2026-11-01, Android emulator (Pixel_10a AVD, API 37): the header rule tests and the asset tests of `resource_test.dart` passed against the local servers on `127.0.0.1`.
- [x] 4.2 Add a test to `resource_test.dart` that runs only on Android and requests `http://localhost:<port>/style.json` from the local server; verify that it reports a load failure, that the server receives no request, and that the test passes on the emulator
  - 2026-11-01, same emulator: passed; the load failure's message was "loading style failed: java.io.IOException: Cleartext HTTP traffic to localhost not permitted", and the server received no request. Skipped on the iOS simulator, as intended.
- [x] 4.3 Check that the header rule tests in `resource_test.dart` pass on the Android emulator, which covers the scenario "Header rules on Android"; verify by their results
  - 2026-11-01, same emulator: "are sent to a matching prefix and not to another prefix", "come from the first matching rule" and the managed-header test passed.

## 5. Documentation

- [x] 5.1 Add a `CHANGELOG.md` entry for FFI 0.202610.3 that marks the Android cleartext HTTP change as breaking, and state in `packages/flutter_mapigrade/README.md` and `docs/limitations.md` that on Android an `http://` URL needs the application to allow cleartext traffic to its host; verify by reading each changed line
- [x] 5.2 Update the FFI release that `CONTRIBUTING.md` and `docs/packaging.md` name; verify that `git grep 0.202610.2` finds no current statement of the pinned release outside `openspec/changes/archive` and dated records
- [x] 5.3 Update the notices paragraph of `CONTRIBUTING.md` ("Update the FFI") and the notices table of `docs/limitations.md` for D217 and the removed Android notices; verify by reading each changed line, and that neither names the three removed files as current

## 6. Verification

- [x] 6.1 Run the test harness's integration tests, including `notices_test.dart`, on macOS, the iOS simulator and the Android emulator; verify that they pass, and record any failure with whether it also fails on `main`
  - 2026-11-01, Flutter 3.47.7:
    - macOS: every file passed: feature_query 19, map_layer 15, map_texture 30 (1 skipped), notices 1, polyline_layer 33, resource 8 (1 skipped), static_alignment 14; unsupported skipped; engines_test.dart 4, with `flutter drive`, as on macOS it must. Within one `flutter test` run, every macOS app launch after the first failed with "The log reader stopped unexpectedly", so each file ran in its own `flutter test` run.
    - iOS simulator (iPhone 17): 121 passed, 3 skipped, 2 failed: "onStyleLoaded is called once after the style has loaded" (called twice) and "Translucent line with a border" (0 px of the line mix). Both also fail on `main` (`bbbc764`, FFI 0.202610.2) on the same simulator: the first in 1 of 3 runs on `main` and 2 of 3 on the change, the second in every run on both.
    - Android emulator (Pixel_10a AVD, API 37): 110 passed, 3 skipped, 13 failed. The 10 failures of feature_query_test.dart (timeouts waiting for MapIdle) didn't recur: the file passed on a rerun, on the change and on `main`. The other 3 — "rapid camera updates do not build up a backlog", "the polyline is where the displayed frame draws it" and "the map shows the converted camera after a camera move stops" — failed in 2 of 2 runs each on both the change and `main` on this emulator.
- [x] 6.2 Run `scripts/build_maplibre_ffi.sh` for the Android preset only to record whether the local Android build works with 0.202610.3 (D208); record the outcome in this task without fixing the script
  - 2026-11-01: the script fails for every preset at 0.202610.3. After the clone, it calls `.mise/bin/sync-submodules`, which the FFI moved to `tools/deps/sync-submodules`. For Android presets it then calls `sync-rustls-platform-verifier` and builds the verifier's AAR, which 0.202610.3 removed (#1184), and the plugin's Gradle local mode depends on that AAR. Fixing the script is its own change (D208). No local build was installed, so `third_party/maplibre-native-ffi/` doesn't exist and builds use the release; the clone in `third_party/maplibre-native-ffi-src/` is at `6c065d96`. Before the run, the user had the leftover `third_party/maplibre-native-ffi-src/`, which held only .NET `obj/` output, deleted.
- [x] 6.3 Run the frame-rate and alignment benchmarks on the Mac, `main` at `bbbc764` against the change, as D216 describes, and add the results to `docs/benchmarks.md`; verify that the section states the builds, the conditions and the ranges over 3 runs
  - 2026-11-01: 3 alternating runs of each build of each benchmark on the Mac; the section "FFI release 0.202610.3" of `docs/benchmarks.md` has the results. The ranges of `main` and the change overlap in every measure, and every alignment phase of both builds had a drawn error of 0 px at max.
- [x] 6.4 Present the Mac results to the user, and ask whether the iPhones and the Pixel run the benchmarks; record the decision in this task
  - 2026-11-01: the user decided not to run the benchmarks on the iPhones and the Pixel, because the Mac showed no difference.
