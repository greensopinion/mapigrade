## 1. Move the files

- [x] 1.1 Create `packages/mapigrade/` with a `pubspec.yaml` (name `mapigrade`, version 0.1.0, `resolution: workspace`, no `flutter_map` dependency), LICENSE identical to the root's, and an empty CHANGELOG, and add it to the workspace in the root `pubspec.yaml`; verify that `flutter pub get` at the root resolves both packages
- [x] 1.2 Move the files that D228 lists with `git mv` only, renaming the shared type files after their types, and commit the move with no other edits; verify that `git log --follow` on `packages/mapigrade/src/core/map_texture.cpp` and on `packages/mapigrade/lib/src/mapigrade_controller.dart` shows their history before the move

## 2. Native code and plugin

- [x] 2.1 Declare the plugin, the notices' `dartPluginClass`, the notice assets and the build hook in `mapigrade`'s `pubspec.yaml`, and remove them from `flutter_mapigrade`'s (D232); verify that `flutter_mapigrade`'s `pubspec.yaml` has no `plugin` section, no assets and no build hook
- [x] 2.2 Rename the native names (D232): method channel `mapigrade`, `libmapigrade.so`, Android package `com.greensopinion.mapigrade`, Swift package directory `darwin/mapigrade/`, code asset `package:mapigrade/native`; verify that `git grep -n flutter_mapigrade -- packages/mapigrade` finds only documentation that names the other package
- [x] 2.3 Update the paths in `scripts/*.sh`, `android/build.gradle.kts` and `Package.swift`, and the native test build in `test/native/CMakeLists.txt`; verify that `scripts/build_maplibre_ffi.sh ios-arm64` installs where `mapigrade`'s builds look, and that `ctest --test-dir build/native-tests` passes

## 3. Dart API

- [x] 3.1 Rename the types in the proposal's table, including `LayerController` to `MapigradeController` as a `final class`, and rename the attach functions to `bindController`, `setControllerMap` and `releaseController` (D229); verify that `git grep -n -E "LayerController|LayerException|LayerMetrics|LayerPlacement" -- packages` finds no code
- [x] 3.2 Split `camera_projection.dart`: `ViewCamera` and the Mercator math in `mapigrade`, `viewCameraOf` and `flutterMapCameraOf` in `flutter_mapigrade` (D228); verify that no file of `mapigrade` imports `flutter_map`, with `git grep -n "package:flutter_map" -- packages/mapigrade`
- [x] 3.3 Write `package:mapigrade/mapigrade.dart` with the thirteen exports, `package:mapigrade/src/integration.dart` and `package:mapigrade/src/testing.dart` (D230), and make `flutter_mapigrade`'s main library export `MapigradeLayer` and `LayerAlignment` and re-export the thirteen names; verify that `flutter analyze` reports no issues in either package
- [x] 3.4 Make every file of `flutter_mapigrade` import `mapigrade` only through its main library and `src/integration.dart`, each integration import with `// ignore: implementation_imports`; verify with `git grep -n "package:mapigrade/src/" -- packages/flutter_mapigrade/lib`
- [x] 3.5 Move the advice about choosing between a `flutter_map` layer and a Mapigrade layer out of the doc comments of `mapigrade`, such as in `MapigradePolylineLayer`, into `flutter_mapigrade`'s README, phrased as when to use which layer; verify that `git grep -n "flutter_map" -- packages/mapigrade/lib` finds no doc comment that names a `flutter_map` class

## 4. Versions

- [x] 4.1 Set `flutter_mapigrade`'s dependency to `mapigrade: '>=0.1.0 <0.1.1'`, and write `scripts/set_version.sh <version>`, which sets both versions and the constraint (D231); verify that running it with 0.1.1 changes exactly those three values, and revert the run
- [x] 4.2 Add a unit test that fails, naming the value, when the two versions and the constraint aren't equal; verify that it passes, and that it fails when one of the three values is changed by hand

## 5. Tests

- [x] 5.1 Move the tests to the packages that D233 assigns, with an API test and an API usage test in each package that check the export lists and the naming rule of the `package-api` spec; verify that `flutter test` passes in both packages, apart from the failures that `port-ffi-gesture-recognizer` task 2.2 recorded
- [x] 5.2 Add the test of D230 to `flutter_mapigrade` that fails when a file under `lib/` imports a `src/` library of `mapigrade` other than `integration.dart`; verify that it passes, and that it fails with an added import of `package:mapigrade/src/testing.dart`
- [x] 5.3 Keep a web build test in each package (D234); verify that `flutter build web` succeeds for an app that imports `flutter_mapigrade` and for one that imports only `mapigrade`

## 6. Test harness and demo

- [x] 6.1 Make the test harness and the demo depend on both packages, import the internals through the two `src/testing.dart` libraries, and use the renamed types; verify that `flutter analyze` reports no issues in either
- [x] 6.2 Run the test harness's integration tests, including `notices_test.dart`, on macOS, the iOS simulator and the Android emulator; verify that they pass with the results of `port-ffi-gesture-recognizer` task 5.1, and record each new failure
  - Recorded 2026-11-27. One `flutter test` call per file; on macOS `engines_test` with `flutter drive`. The three devices ran at the same time. macOS: every file passed. iOS simulator (`mapigrade-iphone-17-pro`, iOS 27.2): every file passed. Android emulator (`mapigrade-api37`, API 37): every file passed except "Pan with polylines: the polyline is where the displayed frame draws it" (polyline_layer) and three "alignment at rest" tests after a resize (static_alignment). Both files passed in full when we ran them again with the emulator alone, so we attribute the failures to the load of the three runs on one Mac, not to this change. `unsupported_test` was skipped on all three, as on every run without the APK that omits the native library.
- [x] 6.3 Open the license page in the test harness on macOS; verify that it lists `mapigrade` and `flutter_mapigrade` with the BSD 3-Clause text and lists each FFI notice once

## 7. Distribution

- [x] 7.1 Run `flutter pub publish --dry-run` in both package directories; verify that each reports no warnings, and that `flutter_mapigrade`'s file list has no file under `android/`, `darwin/`, `ios/`, `macos/`, `src/` or `hook/`
- [x] 7.2 Update `scripts/consumer_build.sh` to copy both packages' file lists and resolve `mapigrade` from its copy with a dependency override (D233); verify that it gets as far as the FFI download, which fails until the FFI pin names a release, and record the result
  - Recorded 2026-11-27, from a scratch clone with the working tree committed, one run per platform. Both dry runs passed, and the script copied 101 files of `mapigrade` and 114 of `flutter_mapigrade`. Web: passed, JavaScript and WebAssembly. Android: failed in Gradle with "maplibre_ffi.lock names no MapLibre Native FFI release; build the FFI with scripts/build_maplibre_ffi.sh and set the Gradle property mapigrade.ffiDir". iOS and macOS: failed when Xcode resolved the packages, with `Package.swift:24: Fatal error: maplibre_ffi.lock names no MapLibre Native FFI release`. These are the failures that `port-ffi-gesture-recognizer` task 2.2 recorded.
- [x] 7.3 Run pana on both packages from a clean clone of the branch; record each package's platform tags and score, and add a `platforms` field with Android, iOS and macOS to `flutter_mapigrade`'s `pubspec.yaml`, with a unit test that it equals the platforms of `mapigrade`'s plugin
  - Recorded 2026-11-27, pana 0.23.19, scratch clone of the working tree. `mapigrade`: 130/160, platforms Android, iOS and macOS. Lost points: repository URL (GitHub's `main` has no `packages/mapigrade/pubspec.yaml` until this branch is merged), no example (comes with `add-mapigrade-map`), and a formatting issue in `lib/src/integration.dart`, since fixed. `flutter_mapigrade`: 50/160, and platform detection failed, because pana resolves `mapigrade` from pub.dev, where it isn't published. pana ignores `pubspec_overrides.yaml` and `dependency_overrides` in a copy of the package, so its platforms can't be checked before `mapigrade` is published. We declared them instead; pana uses a declared `platforms` field in place of inferring platforms (`DeclaredPlatformDetector` in pana 0.23.19).

## 8. Documentation

- [x] 8.1 Write `mapigrade`'s README (what it is, that `MapigradeMap` arrives in a later change, and that applications must not import `src/integration.dart`) and update `flutter_mapigrade`'s README for the shared types and the advice of task 3.5 on when to use which layer; verify by reading both
- [x] 8.2 Add the unreleased CHANGELOG entries: in `flutter_mapigrade`, a **BREAKING** entry with a table of each renamed type, and in `mapigrade`, its first entry; verify that the table lists every rename in the proposal
- [x] 8.3 Update `docs/releasing.md` for two packages, `scripts/set_version.sh` and the release order of D231, and update the package paths in `CONTRIBUTING.md`, `docs/architecture.md`, `docs/packaging.md` and `docs/limitations.md`; verify that `git grep -n "packages/flutter_mapigrade/\(src\|darwin\|android\|hook\|notices\|maplibre_ffi.lock\)" -- docs CONTRIBUTING.md` finds nothing
