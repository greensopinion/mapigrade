## Why

The directory `example/` at the repository root holds the app we use for integration tests, benchmarks, probes and measurement tools. It is not a usage example, and it is outside the plugin package, so pub would not publish it as the package's example. The change `public-api` makes this app use internal APIs of the plugin, so the app needs a name and a location that state what it is. The repository also has Dart packages that resolve their dependencies separately, each with its own lockfile and analysis options.

## What Changes

- Move `example/` to `packages/test_harness/` with `git mv`, and rename its Dart package from `flutter_mapigrade_example` to `test_harness`. Update the imports of `package:flutter_mapigrade_example/...`.
- Rename the app's platform identifiers to match: the Android `namespace`, `applicationId` and the package path of `MainActivity.kt`, and the iOS and macOS `PRODUCT_BUNDLE_IDENTIFIER` and display names. The renamed app installs on devices as a new app.
- Add a pub workspace: a root `pubspec.yaml` (`publish_to: none`) that lists `packages/flutter_mapigrade` and `packages/test_harness` as members. Each member declares `resolution: workspace`. The root `pubspec.lock` replaces the members' lockfiles. The change `public-api` adds the plugin's new example as a third member.
- Add a root `analysis_options.yaml` that the members include, so that the lint configuration is in one place. The lint rules don't change in this change.
- Move `benchmarks.md` and `limitations.md` into `docs/`.
- Update references to `example/` and to the moved documents in the specs, the documents in `docs/`, the README, scripts, and the in-flight changes. Archived changes keep their references, because they describe the repository as it was when they were archived.
- The plugin's code and its Dart API don't change. The test harness keeps importing `package:flutter_mapigrade/testing.dart`.

This change is implemented after the work of `android-texture-vertical-slice` is committed, and before that change's remaining tasks (the emulator integration tests and the Pixel measurements) are done. Those tasks and that change's design are updated to the new paths. This change is archived after `android-texture-vertical-slice`, because its spec delta starts from that change's versions of the same requirements.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: the scenarios that name the example app and `example/lib/color_check.dart` name the test harness and its path instead. The requirements don't change. The delta is written against the spec as it is after `android-texture-vertical-slice` is archived, because that change modifies the same requirements.

## Impact

- Directories: `example/` becomes `packages/test_harness/`, including `android/`, `ios/`, `macos/`, `integration_test/`, `test/`, `test_driver/` and `tool/`.
- Build configuration: new root `pubspec.yaml`, `pubspec.lock` and `analysis_options.yaml`; the members' `pubspec.yaml` and `analysis_options.yaml`; Android Gradle files and `MainActivity.kt`; Xcode project settings and `Info.plist` files of iOS and macOS.
- Documents: `docs/benchmarks.md` and `docs/limitations.md` (moved), the other documents in `docs/`, the root `README.md`, `openspec/specs/map-texture/spec.md`, and the in-flight change `tile-cache-maximum-size`.
- Commands: integration tests and benchmarks run from `packages/test_harness/`. `flutter pub get` runs once, at the repository root.
- Devices: the test harness has new bundle and application IDs, so the app installed under the old IDs stays on the reference devices until it is removed.
