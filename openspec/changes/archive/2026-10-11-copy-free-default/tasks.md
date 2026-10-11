## 1. Implementation (done 2026-10-11, before this change was written)

- [x] 1.1 Move `scripts/maplibre_ffi.lock` to `6f5a662093873a5a690de34fe21f6329b58e77e3` and delete `scripts/patches/maplibre-native-ffi-set-target-same-extent.patch` (D40); verified: `scripts/build_maplibre_ffi.sh` builds all three presets from a clean build directory and creates the xcframework with 3 slices
- [x] 1.2 Add the `copy_free` argument to `map_texture_create`, pass it through `MapTexture::Create` to `CreatePlatformRenderTarget`, remove `map_texture_set_zero_copy_for_testing`, and count copies only when a frame is copied (D38); verified: the native core tests pass, and `flutter analyze` reports no issues
- [x] 1.3 Add `copyFree` to `MapTextureController.create` and `MapLibreTextureLayer`, defaulting to `true`, remove `setZeroCopyForTesting` (D37, D38); verified: the package's unit tests pass
- [x] 1.4 Switch the example's define to `COPY=true` and add the tests "map with the copy renders frames with copies" and "idle map with the copy renders no frames for 10 seconds" next to the two copy-free tests (D39); verified: `example/integration_test/map_texture_test.dart` passes on macOS with the default and with `--dart-define=COPY=true` (24 tests each), and the color check, `map_layer_test.dart` and `static_alignment_test.dart` pass on macOS
- [x] 1.5 Update `README.md` (frame path, thread diagram), `limitations.md` and the `copyFree` doc comments for the new default; verified by reading them against `benchmarks.md`

## 2. Measurements (done 2026-10-11)

- [x] 2.1 On the iPhone: `map_texture_test.dart` with copy-free maps (23 tests), the color check in both modes, and the memory measurement in both modes (2 runs each); recorded in `limitations.md`
- [x] 2.2 Frame rate in both modes on both devices (two sessions), render time per displayed frame, the 5-minute run in both modes on the iPhone, and the alignment benchmark in both modes on both devices; recorded in `benchmarks.md`

## 3. Remaining

- [x] 3.1 Run `map_texture_test.dart` on the iPhone with the default and with `--dart-define=COPY=true` (`flutter drive`), so that the two tests with the copy run on the device; verify that all 24 tests pass in both runs. The first default run failed "rapid camera updates do not build up a backlog": the test required the first sent camera to be displayed, which camera coalescing doesn't guarantee. The test now starts its ordering check at the first displayed frame that shows any sent camera, as its comment says; the default run then passed
- [x] 3.2 Measure the frame-rate benchmark with the default (copy-free) on the reference Mac (AC power, display at "More Space") and the reference iPhone, 3 runs each, and update the headline table "Frame rate during continuous pan" and the Setup's FFI commit in `benchmarks.md`; verify that the table states copy-free, the FFI commit and the date
- [x] 3.3 In `docs/maplibre-native-ffi-flutter-texture-concept.md`, record that decision 10's preferred path (rendering into the borrowed buffer textures) is the default since 2026-10-11, with the blit as the option `copyFree: false`; verify that decision 10 and section 7 no longer describe the blit as the only path in use
- [x] 3.4 Delete `docs/copy-free-adoption.md`, whose content this change's design now holds; verify with a search that no file refers to it
