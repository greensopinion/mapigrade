## 1. Reproduce the failure

- [x] 1.1 Add `test/web_imports_test.dart` (D163) and run it before any change under `lib/`; verify that it fails and names `map_texture_controller.dart` and `native_library.dart` with their import chains from the main library, and that a temporary file under `lib/src/` that imports `dart:io` behind an `if (dart.library.js_interop)` configuration to a pure-Dart file isn't reported (then delete the file)
- [x] 1.2 Add `test/unsupported_platform_test.dart` (D165); verify that `flutter test test/unsupported_platform_test.dart` passes on the macOS host, and that `flutter test --platform chrome test/unsupported_platform_test.dart` fails with the `dart:ffi` compile error. If the Chrome run fails for another reason, such as the build hook, record it in this task and apply the fallback in design.md, Risks, before section 2
  - Result (2026-10-20): the three tests passed on the macOS host. In Chrome the compilation failed with "Dart library 'dart:ffi' is not available on this platform" in `map_texture_controller.dart`, `native_library.dart`, `bindings.dart` and `package:ffi`; the build hook didn't prevent the run, so the fallback isn't needed.

## 2. Conditional imports

- [x] 2.1 Split `lib/src/texture/native_library.dart` into the shared file and `native_library_ffi.dart` and `native_library_web.dart`, with the FFI file as the default and the web file under `if (dart.library.js_interop)` (D161, D162); verify that `flutter analyze` reports no issues and that the existing tests in `test/` pass
- [x] 2.2 Turn `MapTextureController` into an abstract interface class in `lib/src/texture/map_texture_controller.dart`, which keeps the shared types, the members' documentation, and the checks of `nativeLibraryAvailable` in `create` and `setMaximumCacheSize`; move the FFI implementation to `map_texture_controller_ffi.dart`, and add `map_texture_controller_web.dart`, whose functions throw a `StateError` (D160); verify that `flutter analyze` reports no issues, that `lib/src/testing.dart` exports the same names as before, and that the tests in `test/` pass, including `api_test.dart` unchanged
  - Result (2026-10-20): `MapTextureStats` built itself from the FFI struct `MapTextureStatsStruct` through a private constructor, so it couldn't stay in the shared file as it was. Its `forTesting` constructor became the public unnamed constructor, the FFI file converts the struct with it, and the four test call sites use the new name. `flutter analyze` reported no issues in the package, the test harness, the demo app and the example; the 110 tests passed.
- [x] 2.3 Verify that `test/web_imports_test.dart` passes, and that `flutter test --platform chrome test/unsupported_platform_test.dart` passes
- [x] 2.4 Build the scratch app of the exploration again (a new app with `flutter_map`, `latlong2` and a path dependency on the package, placing `MapigradeLayer` behind `isSupported`); verify that `flutter build web` and `flutter build web --wasm` succeed, and that `flutter run -d chrome` shows the fallback `TileLayer`
  - Result (2026-10-20): both builds succeeded. In place of `flutter run -d chrome`, the dart2js release build was served locally and captured with headless Chrome at 800x600; the capture showed OpenStreetMap raster tiles over Vancouver, the fallback `TileLayer`. The wasm build wasn't run in a browser.

## 3. Native platforms unchanged

- [ ] 3.1 Run the test harness's integration tests on macOS, on the iOS simulator and on the Pixel 4a (5G), one file per `flutter test` call; verify that they pass as before the change
  - macOS (2026-10-20): `map_texture_test` (29 passed, 1 skipped), `map_layer_test` (15), `resource_test` (8), `notices_test` (1) and `engines_test` (with `flutter drive`) passed; `unsupported_test` skipped itself. In `static_alignment_test` 11 tests passed and "alignment at rest: integer zoom" failed at `controller!` (line 179) right after the first `pumpWidget`. The same test failed the same way in two runs at commit 7b2ebc6 without this change, so the failure predates it: the first map creation in the process waits for the engine token, and the test doesn't wait for the controller. The iOS simulator and the Pixel 4a (5G) are still open.
- [ ] 3.2 Run the demo app in release mode on macOS and on the Pixel 4a (5G); verify that the map appears with a style loaded over HTTPS and that `isSupported` is true

## 4. CI (after PR #1 is merged)

Another session is changing `scripts/consumer_build.sh` and `.github/workflows/consumer-build.yml` on the branch `consumer-build-ci`. Don't edit that branch or its worktree, `/Users/dgreen/git/mapigrade-consumer-build-ci`.

- [ ] 4.1 Verify that the branch `consumer-build-ci` (PR #1) is merged into `main` before this group starts, and rebase this change's branch onto `main`; if it isn't merged, stop and tell the user
- [ ] 4.2 Add the `web` target to `scripts/consumer_build.sh`, with the consumer app placing `MapigradeLayer` behind `isSupported` (D164); verify that `scripts/consumer_build.sh web` succeeds on the Mac, and that it fails when `native_library.dart` temporarily imports `native_library_ffi.dart` without the condition (then revert the change)
- [ ] 4.3 Add the two steps of D164 to the existing macOS job of `.github/workflows/consumer-build.yml` (the `web` target, and `flutter test --platform chrome test/unsupported_platform_test.dart`), and add `packages/flutter_mapigrade/lib/**` to its triggers; verify that the job passes on a branch

## 5. Documentation

- [ ] 5.1 Below the table "Supported platforms" of `packages/flutter_mapigrade/README.md`, state that apps built for web build with the package and see `isSupported == false`, and that Linux and Windows apps are expected to behave the same but are untested; widen the `isSupported` paragraph and its example from Android ABIs to web; add a line to `CHANGELOG.md` under 0.0.1; verify that the README's `isSupported` example uses the same names as the `isSupported` branch in `test/api_usage_test.dart`, which compiles under `flutter test`
- [ ] 5.2 In `docs/adoption-gaps.md`, replace "Apps that also target web can't use the package" with a note that apps build for web and that rendering on web is open; in `docs/limitations.md`, add the web behavior, and the untested Linux and Windows behavior, to "Known limitations"; verify by reading both against the spec delta
