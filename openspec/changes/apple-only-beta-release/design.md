## Context

`maplibre_ffi.lock` pins FFI commit `4371ff6` with an empty `MAPLIBRE_FFI_VERSION`, `MAPLIBRE_FFI_XCFRAMEWORK_URL` and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` (design D219 of `port-ffi-gesture-recognizer`). Repository builds use the local FFI build that `scripts/build_maplibre_ffi.sh` installs in `third_party/maplibre-native-ffi/`, including `MaplibreNativeC.xcframework` for macOS, iOS and the iOS simulator. The FFI's Apple presets build with `CMAKE_BUILD_TYPE` Release.

- `darwin/mapigrade/Package.swift` uses the local xcframework when it exists, and otherwise a remote binary target with the URL and checksum that `scripts/update_ffi_pins.sh` copies from the lock; with an empty URL it stops with a `fatalError`.
- `android/build.gradle.kts` depends on `org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android:$MAPLIBRE_FFI_VERSION` unless the Gradle property `mapigrade.ffiDir` names a local build.
- On Android, `nativeLibraryAvailable` opens `libmapigrade.so` and asks whether the plugin initialized it; when the library is missing, opening it throws and the value is false. `unsupported_test.dart` covers an APK without the library.
- `ffi_pins_test.dart` fails while the lock names no release. `docs/releasing.md` requires an FFI release. `scripts/set_version.sh` accepts only `major.minor.patch` and sets `flutter_mapigrade`'s constraint to the range up to the next patch version, which `version_test.dart` checks.
- `scripts/consumer_build.sh` builds an application from the files of the packages' dry runs, and checks that the APK contains the FFI and plugin libraries for three ABIs.

## Goals / Non-Goals

**Goals:**
- Publish `0.2.0-beta.1` of both packages, which builds from pub.dev on iOS and macOS with the mln-rs-based FFI.
- Android applications that depend on the beta build and run, and report that the map isn't supported.
- `main` keeps building and testing on Android with the local FFI build.
- A stable version can't be published without an FFI release.

**Non-Goals:**
- Android in the beta: we can't publish the FFI's Android runtime under its Maven namespace, and a repository of our own would need every application to add it.
- Automating the xcframework build or its upload in CI.
- Changing the FFI.

## Decisions

### D250. The prerelease is published from a release branch

The commits that only the prerelease needs, the version, the undeclared Android platform and the prerelease's README and CHANGELOG text, go on a branch `release/0.2.0-beta`. The runbook creates it from `main`. For `0.2.0-beta.1` we create it from `mapigrade-map`, which has the FFI port, the package split and `MapigradeMap` and isn't merged into `main` yet, so in this change "`main`" means `mapigrade-map` (user decision, 2026-11-27). The packages are published from a clean clone of that branch, and the published commit is tagged `v0.2.0-beta.1`. Everything that `main` can also use, the scripts, the tests, the lock's xcframework URL and checksum, and `docs/releasing.md`, goes on `main` first.

`main` keeps `android` among `mapigrade`'s plugin platforms, so the test harness, the demo and the examples still build for Android with `mapigrade.ffiDir`. When an FFI release contains the mln-rs port, `main` pins it, and the next release comes from `main` as before; the branch isn't merged back.

Alternatives: dropping Android on `main` stops the repository's Android builds, including the Pixel runs, until the FFI release. Editing the pubspec in the release clone without a commit publishes files that no commit records.

### D251. The xcframework is the local build at the pinned commit, hosted as a GitHub release asset

`scripts/package_xcframework.sh --local` zips `third_party/maplibre-native-ffi/MaplibreNativeC.xcframework` with `MaplibreNativeC.xcframework/` at the zip's top level, as for a release, and prints its SHA-256, which is the checksum that `swift package compute-checksum` computes. Before packaging, the script checks that the local build is of the lock's `MAPLIBRE_FFI_COMMIT` and has the three Apple slices; `scripts/build_maplibre_ffi.sh` records the commit it built.

The zip is an asset named `MaplibreNativeC.xcframework.zip` of a GitHub prerelease of `greensopinion/mapigrade` with the tag `maplibre-native-ffi-<short commit>`, for example `maplibre-native-ffi-4371ff6`. The release notes name the FFI commit and its repository, and state that the build is not an official MapLibre release. Once a published package or a commit on `main` references an asset, the asset is never replaced: a new build gets a new tag, because SwiftPM rejects an archive whose checksum changed. Before that, a defective asset is replaced under the same tag; the first asset of `maplibre-native-ffi-4371ff6` was, because its zip contained the frameworks' extended attributes as `._` files (user decision, 2026-11-27). The FFI's third-party notices for the commit are already in `mapigrade` (designs D227 and D248), and applications show them through the license registry, so the zip contains only the xcframework.

The user creates the GitHub release and uploads the asset; Claude prepares the zip, the checksum and the release notes.

Alternative: the FFI's own release workflow on a fork. It runs on runners that a fork doesn't have, and produces more than the xcframework.

### D252. The lock states the commit and the hosted archive

On `main`, the lock keeps `MAPLIBRE_FFI_VERSION` empty and gets the hosted URL and checksum; `scripts/update_ffi_pins.sh` writes them into `Package.swift`. A checkout without a local FFI build then builds for iOS and macOS from the hosted archive. A local build still takes precedence.

`ffi_pins_test.dart` replaces "the lock file names an FFI release" with these rules, read from the lock and `mapigrade`'s pubspec:
- With an FFI release version, the tests are as before.
- Without one, the pubspec's version must have a prerelease suffix, the pubspec must not declare `android` under `flutter.plugin.platforms`, and the URL must be a release asset of `github.com/greensopinion/mapigrade`. Each failure names the value.

So the test fails on `main`, which declares Android with version `0.1.0`, as it does now, and passes on the release branch.

### D253. Android in the prerelease

On the release branch, `mapigrade`'s pubspec has no `android` entry under `flutter.plugin.platforms`, and `flutter_mapigrade`'s pubspec, whose `platforms` equal those of `mapigrade`'s plugin (`platforms_test.dart`), has no `android` entry either. `third_party_notices_test.dart` requires the Android registration of the notices only when the lock names an FFI release or the pubspec declares Android. Flutter then doesn't add the plugin's Gradle project to an Android build, so the empty FFI version is never resolved, and the APK has no `libmapigrade.so`. The build hook still declares the code asset by name, `nativeLibraryAvailable` is false, and both widgets report a `MapigradeCreateException` and build their children, as on an Android device without a supported ABI. The license registration of the FFI notices, a `dartPluginClass` of the Android entry, also stops on Android, which is right for an APK without the FFI.

`android/` stays in the archive, so that the branch's archive differs from `main`'s only in the pubspec. If the dry run warns about it, `.pubignore` on the branch excludes it.

`scripts/consumer_build.sh` reads the lock: without an FFI release version it expects the APK to build without either library.

### D254. The prerelease's version and constraint

`scripts/set_version.sh` accepts a version with a prerelease suffix that ends with a number. For a prerelease, it sets `flutter_mapigrade`'s constraint on `mapigrade` to the range up to the next prerelease, `'>=0.2.0-beta.1 <0.2.0-beta.2'`, because the range to the next patch version, `<0.2.0`, would also allow `0.2.0-beta.2`. `version_test.dart` checks the same rule. We first chose the exact version, `mapigrade: 0.2.0-beta.1`; the dry run of `flutter_mapigrade` then warned that the dependency should allow more than one version, which the `package-distribution` requirement "Published archive contents" doesn't allow. The minor version increases because the renames of `split-mapigrade-package` break the API.

### D255. The prerelease states its platforms

On the release branch, both READMEs say under "Supported platforms" that `0.2.0-beta.1` supports iOS and macOS only, because its FFI has no release yet, and that `0.1.0` supports Android. Both CHANGELOG entries start with that statement. `docs/releasing.md` gets a section "Prerelease without an FFI release" with the branch, the xcframework and the pin steps.

## Risks / Trade-offs

- [Applications depend on an FFI build that MapLibre didn't publish] → The release notes, READMEs and CHANGELOGs state it; the beta is a prerelease, which pub only resolves when an application asks for it.
- [An Android application that opts into the beta loses the map that 0.1.0 shows] → The READMEs and CHANGELOGs state it, and `isSupported` lets the application show another layer.
- [The hosted asset disappears or changes] → Never replace an asset (D251); a changed archive fails the checksum, which is the build failure that the spec requires.
- [The release branch diverges from `main`] → It holds only the prerelease's files (D250), and is abandoned at the FFI release.
- [Without the Android entry, pub.dev's platform detection differs from what we expect] → Check the package page after publishing, as the runbook already requires.

## Open Questions

None.
