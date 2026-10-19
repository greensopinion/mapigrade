## Why

We want to publish `flutter_mapigrade` to pub.dev, and the package can't build outside this repository. `android/build.gradle.kts` reads the MapLibre Native FFI library, its headers, the `rustls-platform-verifier-android` Maven repository and `scripts/maplibre_ffi.lock` from `../../..`, which in a consumer's pub cache is `~/.pub-cache/hosted/`. On Apple platforms `flutter pub publish --dry-run` follows the `Frameworks/MapLibreNativeC.xcframework` symlink into the git-ignored `third_party/`, so the archive contains 37 MB of binaries only when it is created on a machine that has run `scripts/build_maplibre_ffi.sh`. The package also declares `publish_to: none` and no `repository`.

The MapLibre Native FFI project now publishes what the package needs: a monthly GitHub release with one tarball per preset and a `SHA256SUMS` file, and on Maven Central the AAR `org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android`, which contains `libmaplibre-native-c.so` for `arm64-v8a`, `armeabi-v7a` and `x86_64`, the patched verifier classes, their keep rules and their notices. If the package takes its native libraries from those releases, we don't build or host binaries, and Android apps gain two ABIs. Until #838, which upstream merged on 2026-10-18, the upstream releases didn't contain an xcframework, which Swift Package Manager needs. The next release contains `MaplibreNativeC.xcframework.zip`.

## What Changes

- The package depends on one released version of the MapLibre Native FFI, recorded in a lock file inside the package. The first published version waits for an upstream release that contains the fixes this repository pins today (#807, #808).
- Android: the plugin depends on the upstream runtime AAR from Maven Central. Gradle packages its `libmaplibre-native-c.so`; the plugin's CMake build links `libflutter_mapigrade.so` against the same file. The local Maven repository, the `rootProject.allprojects` repository block and the jniLibs copy task are used only when the plugin builds against a local FFI build.
- Android: the plugin builds `libflutter_mapigrade.so` for `arm64-v8a`, `armeabi-v7a` and `x86_64`. **BREAKING** for apps that relied on the APK containing only `arm64-v8a` libraries: APKs and app bundles get two more ABIs unless the app sets its own `abiFilters`.
- Apple: `Package.swift` declares `MaplibreNativeC` as a remote binary target with the URL and checksum of the `MaplibreNativeC.xcframework.zip` of the upstream native release. Upstream added the zip in #838, after our proposal (#822).
- Repository development keeps using `scripts/build_maplibre_ffi.sh`: when a local FFI build exists, the package uses it in place of the released artifacts. Published archives never contain a local FFI build.
- The committed notice files come from the pinned upstream release in place of the local build.
- `pubspec.yaml` gets `repository`, `issue_tracker` and `topics`, and loses `publish_to: none`. A `.pubignore` excludes local FFI builds.
- A CI job reproduces the published archive outside the repository, builds a new consumer app against it for Android, iOS and macOS, and fails if the build reads anything from the repository.

Non-goals:

- No build of the FFI from source in consumer builds, and no binaries in the published archive.
- No CocoaPods support.
- No new platforms (Linux, Windows, web), although upstream publishes presets for them.
- No 32-bit x86 Android: upstream doesn't publish it, so `MapigradeLayer.isSupported` stays false there.
- Publishing 0.0.1 is not part of this change. The change ends when a dry run of `flutter pub publish` reports no warnings and the CI job passes.

## Capabilities

### New Capabilities

- `package-distribution`: what the published package contains, where its native libraries come from, how one FFI version is pinned across platforms, and the check that the package builds in an app from the published archive alone.

### Modified Capabilities

- `map-texture`: the requirement "Supported platforms" adds Android on `armeabi-v7a` and `x86_64`.
- `map-layer`: the requirement "Unsupported architectures" changes its example of an unsupported device from "no arm64 ABI" to an ABI outside `arm64-v8a`, `armeabi-v7a` and `x86_64`, and its "Supported device" scenario covers the new ABIs.
- `third-party-notices`: the requirement "Notices equal to the FFI build" compares the committed notices with the pinned upstream release in place of the local build at the commit in `scripts/maplibre_ffi.lock`.

The `map-texture` delta modifies the requirement "Supported platforms" as the in-progress change `android-texture-vertical-slice` states it. That change is archived before this one.

## Impact

- Package: `pubspec.yaml`, `.pubignore`, `android/build.gradle.kts`, `android/src/main/cpp/CMakeLists.txt`, `android/consumer-rules.pro`, `darwin/flutter_mapigrade/Package.swift`, a new FFI lock file and the FFI headers for Android, `notices/`, `README.md`, `CHANGELOG.md`.
- Scripts: `scripts/build_maplibre_ffi.sh` reads the lock file in the package; a new script writes the URL and checksum of the xcframework zip from the lock file; a new script assembles an xcframework zip from the upstream tarballs, as a fallback; `scripts/copy_ffi_notices.sh` reads the release.
- Upstream: the xcframework zip in the native release, which upstream added in #838 in place of our #822, and a Prefab module in the AAR (#820, #821).
- CI: a GitHub Actions workflow on a macOS runner.
- Consumers: the first build on a machine downloads the AAR (17 MB) from Maven Central and the xcframework zip from GitHub, so it needs network access. APK size grows by about 22 MB before compression for the two extra ABIs, unless the app filters ABIs.
- Documentation: `README.md` (installation, supported ABIs), `docs/limitations.md` (arm64-only statement).
