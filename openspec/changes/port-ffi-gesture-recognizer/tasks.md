## 1. Local FFI build

- [ ] 1.1 Rewrite `scripts/build_maplibre_ffi.sh` for the mln-rs build (D220): check out the pinned commit with its submodules, run the FFI's `mise bootstrap` (and `mise -E android` for the Android preset), build `macos-arm64`, `ios-arm64`, `ios-simulator-arm64` and `android-arm64`, combine the three Apple frameworks into `MaplibreNativeC.xcframework`, and remove the TLS helper step and the patches that no longer apply; verify that a run from a clean `third_party/` installs the xcframework and the Android library and headers where the example's builds look for them
- [ ] 1.2 Update `MAPLIBRE_FFI_PRESETS` and `MAPLIBRE_FFI_ANDROID_PRESETS` in `maplibre_ffi.lock` to the new preset names, and make the Gradle local mode and the Darwin local framework path find the new build's outputs; verify that `scripts/build_maplibre_ffi.sh ios-arm64` builds one preset and that an unknown preset name fails with the list of known ones
- [ ] 1.3 State in `CONTRIBUTING.md` that a local FFI build needs mise, and how to run the script; verify by following the steps from a shell without the FFI's tools on the path

## 2. FFI pin

- [ ] 2.1 Set `MAPLIBRE_FFI_COMMIT` to `4371ff607e0bd22115d390de27d72a54987cc6c7` and empty the release fields in `maplibre_ffi.lock` (D218, D219), and make `scripts/update_ffi_pins.sh` write a `Package.swift` and a Gradle release mode that fail with a message naming `scripts/build_maplibre_ffi.sh` when the lock has no release; verify that a release-mode build of the example fails with that message on macOS and Android
- [ ] 2.2 Run `test/ffi_pins_test.dart` and `scripts/consumer_build.sh`; verify that each fails only because the lock names no release, and record the failures in this task
- [ ] 2.3 Copy the notice files of the pinned commit from the local build's install into `packages/flutter_mapigrade/notices/` with `scripts/copy_ffi_notices.sh`, adapting the script to read an install instead of release tarballs if it must; verify the diff of `notices/` against 0.202610.3 and list the added and removed files in this task

## 3. Core port

- [ ] 3.1 Port `src/core/` to the C API of the pinned commit: renames, removed functions, the typed event payloads, the log callback that returns void, and the status codes of D225; verify that `map_texture.cpp` and `map_texture_api.cpp` compile against the pinned headers without errors, and with no warnings that `main` doesn't have
- [ ] 3.2 Render through a wrapped device and one target descriptor (D221, D222): in the core's render target interface, the Metal glue's borrowed ring of the four slots' textures, the one-texture ring and GPU copy for `copyFree: false`, and the Android glue's wrapped EGL context with an OpenGL surface target per `ImageReader`, keeping the presentation times of D184; verify that the example builds for macOS, iOS (`--no-codesign`) and Android
- [ ] 3.3 Port the frame path to `demand_frame`, acquiring the newest frame, waiting for its producer sync before publishing it, and releasing it with `MLN_GPU_SYNC_CPU_COMPLETE` when its slot becomes free (D223); verify with a native test that a frame is published only after its producer sync, and that a slot's frame is released only when the slot becomes free
- [ ] 3.4 Keep the GeoJSON text of each overlay source and send it with `mln_map_set_geo_json_source_data`, also when installing overlays again after a style load (D224); verify that `polyline_layer_test.dart` passes on macOS, including its tests of a style change
- [ ] 3.5 Copy `frame_projection` from each frame result into the published frame of its slot (D226); verify with a native test that the projection of a published frame equals the one in that frame's result
- [ ] 3.6 Update `docs/architecture.md` where it describes what this group changed: the device and target, the producer sync, and the overlays' GeoJSON text; verify that `git grep mln_geo_json_source_data_create docs` finds nothing

## 4. Native and Dart tests

- [ ] 4.1 Port `test/native/`, including the interposed functions that were renamed or removed; verify that `ctest --test-dir build/native-tests` passes
- [ ] 4.2 Run `flutter test` in `packages/flutter_mapigrade`; verify that every test passes except `ffi_pins_test.dart`, whose failure task 2.2 recorded

## 5. Behavior

- [ ] 5.1 Run the test harness's integration tests on macOS, the iOS simulator and the Android emulator; verify that they pass, and record each failure with whether it also fails on `main`
- [ ] 5.2 Run the integration tests on the iPhone and the Pixel, because mln-rs renders on a new code base; verify that they pass, and record each failure with whether it also fails on `main`
- [ ] 5.3 For each behavior that tasks 5.1 and 5.2 show the new C API changed, and that the specs state, present it to the user with a proposed delta spec; record each decision in this task, or record that none was found

## 6. Benchmarks

- [ ] 6.1 Run the frame-rate and alignment benchmarks on the Mac, `main` against the change, 3 alternating runs of each, and add a section to `docs/benchmarks.md`; verify that the section states the builds, the conditions and the ranges over 3 runs
- [ ] 6.2 Present the Mac results to the user, and ask whether the iPhones and the Pixel run the benchmarks; record the decision in this task

## 7. Documentation

- [ ] 7.1 Update `CONTRIBUTING.md` and `docs/packaging.md` where they name the pinned FFI, to state the pinned commit and that no release contains it; verify that `git grep 0.202610.3` finds no current statement of the pin outside `openspec/changes/archive` and dated records
- [ ] 7.2 Add an unreleased `CHANGELOG.md` entry for the move to the mln-rs-based FFI, with each behavior change from task 5.3; verify by reading the entry
