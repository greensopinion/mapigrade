## 1. Sequencing

- [x] 1.1 Update the proposal and the design's Context and Risks: this change is implemented before `android-texture-vertical-slice` is archived, and is archived after it; verify with `openspec validate repo-layout --strict`

## 2. Move (D75)

- [x] 2.1 Delete the ignored IDE files (`*.iml`, `.idea/`) and build output in `example/`, and run `git mv example packages/test_harness`; verify that `git status` shows the tracked files as renamed and that `example/` no longer exists
- [x] 2.2 Rename the Dart package to `test_harness`, change the plugin dependency to `path: ../flutter_mapigrade`, and change imports of `package:flutter_mapigrade_example/` to `package:test_harness/`; verify that `flutter analyze` in `packages/test_harness/` reports no errors

## 3. Platform identifiers (D76)

- [x] 3.1 Set the iOS and macOS bundle identifiers to `com.greensopinion.mapigradeTestHarness` (tests `.RunnerTests`), the macOS `PRODUCT_NAME` to `test_harness`, and the iOS display name to `Mapigrade Test Harness`; verify with `git grep` that no Xcode project or plist under `packages/test_harness/` contains `mapigradeExample` or `flutter_mapigrade_example`
- [x] 3.2 Set the Android `namespace` and `applicationId` to `com.greensopinion.mapigrade_test_harness`, the label to `Mapigrade Test Harness`, and move `MainActivity.kt` to the matching package directory; verify that `flutter build apk --debug` in `packages/test_harness/` succeeds

## 4. Workspace and analysis options (D77, D78)

- [x] 4.1 Record the `flutter analyze` findings of both packages, add the root `pubspec.yaml` with both members, add `resolution: workspace` to the members, remove `packages/test_harness/pubspec.lock` and the members' `.dart_tool/`, and run `flutter pub get` at the root; verify that the root `pubspec.lock` and `.dart_tool/package_config.json` exist and that no member has its own lockfile
- [x] 4.2 Add the root `analysis_options.yaml` and make both members include it; verify that `flutter analyze` in each member reports the same findings as recorded in 4.1
- [x] 4.3 Run the plugin's Dart unit tests and the test harness's unit tests; verify that they pass

## 5. Documents and references (D79)

- [x] 5.1 `git mv` `benchmarks.md` and `limitations.md` into `docs/`, and update links to them; verify that every relative link to them in Markdown files outside `openspec/changes/archive/` resolves to an existing file
- [x] 5.2 Update references to the old paths and identifiers in the root `README.md`, `docs/`, `camera_alignment.dart`, `alignment_capture.swift`, and the in-flight changes `android-texture-vertical-slice` (open tasks and design), `tile-cache-maximum-size` and `public-api`; verify that searching outside `openspec/changes/archive/` for `example/`, `flutter_mapigrade_example`, `mapigradeExample`, and root-level `benchmarks.md` or `limitations.md` finds only the main spec `map-texture` (updated when this change is archived), this change's own artifacts, `packages/flutter_mapigrade/example/` mentioned as the future example, and records of finished work: the completed tasks, proposal and spec delta of `android-texture-vertical-slice`, and measurement results that name the app they were measured with

## 6. Builds and tests on each platform

- [ ] 6.1 On macOS, run the integration tests `map_texture_test.dart` and `map_layer_test.dart` from `packages/test_harness/`, and build and start the release app; verify that the tests pass and the release app shows the map
- [ ] 6.2 On the Android emulator, run `map_texture_test.dart`, and build and start the release APK; verify that the test passes and the release app shows the map with a style and tiles loaded over HTTPS
- [ ] 6.3 On the iPhone, build and install the release app, then remove the app with the old identifier; verify that the app starts and shows the map
- [ ] 6.4 Run the macOS continuous pan benchmark from `packages/test_harness/`; verify that its median frame rate is within the range recorded in `docs/benchmarks.md` for the same conditions
