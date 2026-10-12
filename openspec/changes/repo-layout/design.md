## Context

See proposal.md for motivation and scope, and specs/map-texture/spec.md for the changed scenarios. The change `public-api` uses decisions D65 to D74; decisions here are numbered from D75.

This change starts after `android-texture-vertical-slice` is archived. The delta in specs/map-texture/spec.md copies that change's versions of "Supported platforms" and "Copy-free rendering by default" and changes only the names of the app and the path of the color check. If that change modifies these requirements again before it is archived, the delta is rewritten from its final version.

Current state, as checked in this repository on 2026-10-12:

- `example/` is the Dart package `flutter_mapigrade_example`. It depends on the plugin with `path: ../packages/flutter_mapigrade`. Its `pubspec.lock` and `.metadata` are tracked; its `.iml` files and `.idea/` are ignored, and one of them (`flutter_map_maplibre_texture_example.iml`) has a name from before the project was renamed.
- Platform identifiers: iOS and macOS `PRODUCT_BUNDLE_IDENTIFIER` `com.greensopinion.mapigradeExample` (and `.RunnerTests`), macOS `PRODUCT_NAME` `flutter_mapigrade_example`, iOS `CFBundleDisplayName` "Flutter Map Maplibre Texture Example", Android `namespace` and `applicationId` `com.greensopinion.flutter_mapigrade_example`, Android `android:label` `flutter_mapigrade_example`.
- The plugin's `analysis_options.yaml` and the example's both include `package:flutter_lints/flutter.yaml` and exclude build and platform directories; neither enables or disables a rule.
- Paths to `example/`, `benchmarks.md` or `limitations.md` appear in the root `README.md` (build and run commands, the `xctrace` app path), the four documents in `docs/`, `packages/flutter_mapigrade/lib/src/layer/camera_alignment.dart` (a doc comment), `example/tool/alignment_capture.swift` (its build command), the main spec `map-texture`, and the in-flight changes `tile-cache-maximum-size` and `public-api`.

## Goals / Non-Goals

**Goals:**
- After the move, every build, test and measurement command works from the new location, with the same results.
- Each Dart package of the repository resolves its dependencies in one workspace.

**Non-Goals:**
- No change to the plugin's code, API or lint rules (`public-api` changes those).
- No new example app (`public-api` creates it).
- Archived changes keep their paths.

## Decisions

### D75. `packages/test_harness/`, Dart package `test_harness`

`git mv example packages/test_harness`, so that history follows the files. The directory name equals the Dart package name, as for `packages/flutter_mapigrade/`. The dependency on the plugin becomes `path: ../flutter_mapigrade`. Imports of `package:flutter_mapigrade_example/` become `package:test_harness/`. The ignored IDE files (`*.iml`, `.idea/`) are deleted, not moved.

Alternatives: `apps/test_harness/`, which separates applications from libraries. Rejected while the repository has one application. The repository root, which we used before. Rejected: every other Dart package is under `packages/`.

### D76. Platform identifiers

| Setting | New value |
|---|---|
| iOS and macOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.greensopinion.mapigradeTestHarness` (tests: `.RunnerTests`) |
| macOS `PRODUCT_NAME` | `test_harness` |
| iOS `CFBundleDisplayName`, Android `android:label` | `Mapigrade Test Harness` |
| Android `namespace`, `applicationId` | `com.greensopinion.mapigrade_test_harness` |
| Android `MainActivity.kt` | moves to `kotlin/com/greensopinion/mapigrade_test_harness/` with that package |

Apple bundle identifiers don't allow underscores, so the Apple and Android identifiers differ in form, as they do today. The development team (`2J9XYBV642`) and the signing settings don't change; automatic signing creates a profile for the new identifier.

### D77. Pub workspace

The root `pubspec.yaml`:

```yaml
name: mapigrade_workspace
publish_to: none
environment:
  sdk: ^3.13.4
workspace:
  - packages/flutter_mapigrade
  - packages/test_harness
```

Each member adds `resolution: workspace`. `flutter pub get` runs at the root and writes the root `pubspec.lock` and `.dart_tool/package_config.json`. The root lockfile is tracked, because the root isn't published. `packages/test_harness/pubspec.lock` is deleted from the repository, and the members' `.dart_tool/` directories are deleted locally. `public-api` adds `packages/flutter_mapigrade/example` as a member.

Alternative: melos. Rejected: the workspace gives one resolution without another tool, and the repository has no scripts that run across packages.

### D78. Shared analysis options

The root `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` and excludes `**/build/**`. Each member's `analysis_options.yaml` includes `../../analysis_options.yaml` and keeps its own excludes of platform directories. The enabled rules are the same as today; `public-api` adds rules to the plugin's file.

### D79. Documents and references

`git mv benchmarks.md docs/benchmarks.md` and `git mv limitations.md docs/limitations.md`. Links to them, including relative links inside `docs/`, are updated. Every reference listed in Context is updated to `packages/test_harness/`, `test_harness` or the new identifiers; the root `README.md` describes the test harness, not an example. The `MLT_KEEP_AWAKE` environment variable keeps its name.

## Risks / Trade-offs

- [The Flutter tool, Gradle or Xcode may read `.flutter-plugins-dependencies` or `package_config.json` from the app directory, which a workspace moves to the root] → Build and run the test harness on macOS, on the iPhone and on the Android device, in debug and release mode, before the change is complete. The Android build also runs the plugin's build hook, which has to find the code asset.
- [An installed app with the old identifier stays on the reference devices, and Instruments or `devicectl` scripts may start the wrong app] → Remove the old app from the iPhone and the Android device after the first install of the renamed app, and update the commands in the README.
- [A path reference is missed] → After the move, search the repository, excluding `openspec/changes/archive/`, for `example/`, `flutter_mapigrade_example`, `mapigradeExample`, `benchmarks.md` and `limitations.md`, and check each result.
- [Moving the directory while another change edits files in it produces conflicts] → Start after `android-texture-vertical-slice` is archived and the working tree is clean, and make the move its own commit, without content edits, so that Git detects the renames.

## Migration Plan

1. Commit the move (D75) with no other edits.
2. Commit the identifier renames (D76), the workspace (D77), the analysis options (D78) and the documents (D79).
3. Run the integration tests and one benchmark on each platform from `packages/test_harness/`, and compare the benchmark with its last result in `docs/benchmarks.md`.

To revert, revert both commits; the workspace has no effect outside the repository.
