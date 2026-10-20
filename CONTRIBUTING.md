# Contributing

This guide is for developers who build, test and measure Mapigrade. The [README](README.md) has the short build and run steps; the architecture is in [docs/architecture.md](docs/architecture.md).

## Prerequisites

- An Apple silicon Mac with macOS 14.3 or later
- Xcode 26.6 with the macOS and iOS SDKs, and an iOS simulator runtime
- Flutter 3.47.5 with macOS desktop support
- For an iPhone: iOS 15.5 or later, an Apple account added in Xcode (Settings > Accounts) for automatic signing, and the device paired with Xcode. The test harness's iOS project uses development team `2J9XYBV642`; change it in Xcode (Runner > Signing & Capabilities) for another team
- git and [mise](https://mise.jdx.dev) (`brew install mise`); the build script installs CMake, Ninja, Rust and cargo-about through mise
- CMake for the C++ unit tests (`brew install cmake`)
- For Android: the Android SDK with NDK 30.0.16248370 (Android Studio's SDK Manager, or `sdkmanager "ndk;30.0.16248370"`). The FFI build and Gradle find the SDK through `ANDROID_HOME`; the FFI build uses `~/Library/Android/sdk` when it isn't set. The FFI build installs the Rust target `aarch64-linux-android` and the JDK for its Gradle build through mise
- For an Android device: arm64, Android 10 (API 29) or later, with USB debugging turned on and this Mac authorized on the device. For the emulator: an arm64 system image of API 29 or later; we used `sdk_gphone16k_arm64` (API 37, 16 KB pages)

## Pinned versions

| Component | Version |
| --- | --- |
| MapLibre Native FFI | commit `44d24a1cfd9cb1b1b25a8c36e8e2472f0e392e18` (`unstable-native-snapshot` of 2026-10-18), presets `macos-arm64-metal`, `ios-arm64-metal`, `ios-simulator-arm64-metal` and `android-arm64-egl` (`packages/flutter_mapigrade/maplibre_ffi.lock`) |
| Flutter | 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4 |
| Xcode | 26.6 (17F113), macOS and iOS SDKs; deployment targets macOS 14.3 and iOS 15.5 |
| Android NDK | 30.0.16248370, the version that the FFI's `mise.toml` pins; `minSdk` 29, ABI `arm64-v8a` |

The plugin uses Swift Package Manager, the native build integration that the Flutter 3.47.5 plugin template uses by default. It has no podspec, so CocoaPods builds are not supported.

## Run the test harness

The test harness shows the map with a control panel above it: style selection (OpenFreeMap Liberty, MapLibre demo tiles, and an invalid URL that shows the reported failure), zoom, rotate and pan buttons, and a continuous pan switch that changes the camera on every Flutter frame. `--dart-define=LOG_FRAMES=true` prints every displayed frame with its camera, and `--dart-define=CONTINUOUS_PAN=true` starts continuous pan at launch. On iOS, launching through `xcrun devicectl device process launch -e '{"MLT_KEEP_AWAKE":"1"}'` keeps the device from locking during scripted measurements. On Android, keep the device unlocked with the screen on during a measurement: when the activity stops, the plugin pauses rendering.

## Tests

```sh
# C++ unit tests for the core (no MapLibre)
cd packages/flutter_mapigrade
cmake -S test/native -B build/native-tests
cmake --build build/native-tests
ctest --test-dir build/native-tests --output-on-failure

# Dart unit tests (including the check that lib/src/texture/ doesn't import flutter_map)
flutter analyze
flutter test

# Integration tests for the spec scenarios (about 40 s each, needs network access)
cd ../test_harness
flutter test integration_test -d macos
flutter test integration_test -d <simulator id>
# On an iPhone, flutter test can't start the app over a wireless connection; use flutter drive.
# Keep the iPhone unlocked with the screen on during the run.
flutter drive -d <iPhone id> --driver=test_driver/integration_test.dart \
  --target=integration_test/map_texture_test.dart
# Android device or emulator. Keep the device unlocked with the screen on during the run.
flutter test integration_test -d <Android id>
```

On Android the tests that need display times or plugin-owned display buffers are skipped, and each skip states its reason. On the emulator, "rapid camera updates do not build up a backlog" fails, because the emulator renders OpenGL ES in software; it passes on a device.

The iOS and Android lifecycle tests use test hooks (`package:flutter_mapigrade/src/testing.dart`) that call the same functions as the background, foreground and memory warning handlers. The real notifications were checked on an iPhone (design D13, result). On Android, a test hook also makes Flutter remove the map's surface, as it does when the app goes to the background.

## Measurements

The benchmark and the memory and color measurements are described, with their commands and results, in [docs/benchmarks.md](docs/benchmarks.md).

## README video

The video in the [README](README.md) is a 20 s recording of the demo's flyover on macOS. `packages/demo/tool/record_readme.sh` makes it without input: it builds the demo in release mode, starts it in its recording mode, captures the demo's window, adds a title card, and writes `packages/demo/build/readme_demo.mp4`. Make it again when a change to the demo or the styles changes what the video shows.

Before the first run:

- Install the tools: `brew install ffmpeg imagemagick librsvg`. The script also needs `swiftc`, from Xcode or the Xcode command line tools.
- Grant Screen Recording permission to the app that you run the script from (Terminal, iTerm or VS Code) in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen that app. When the permission is missing, the script asks macOS for it and stops before it builds. macOS can ask for the permission again later.

Run the script from the repository root:

```sh
packages/demo/tool/record_readme.sh
```

A run takes about 3 minutes: about 1 minute to build, 21 s of warm-up, 20 s of recording and about 1 minute to encode. The demo's window opens without a title bar. You can use the Mac during the run, because the capture records the demo's window even where other windows cover it. The script stops without changing the video when a tool or the permission is missing, or when the video is over 10,000,000 bytes at CRF 24, 25 and 26; 10 MB is the limit for a video attachment on GitHub's free plan.

To publish the video, edit `README.md` on github.com, drag `packages/demo/build/readme_demo.mp4` into the editor, and replace the earlier video's URL with the `https://github.com/user-attachments/assets/...` URL that GitHub inserts, on a line of its own. GitHub doesn't list or delete attachments, so the earlier video stays at its URL.

## Build MapLibre Native FFI

`scripts/build_maplibre_ffi.sh` builds the FFI at the commit and presets pinned in `packages/flutter_mapigrade/maplibre_ffi.lock`: the Apple presets in `MAPLIBRE_FFI_PRESETS` and the Android presets in `MAPLIBRE_FFI_ANDROID_PRESETS`. A preset name as argument builds only that preset.

The script:

1. clones `https://github.com/maplibre/maplibre-native-ffi.git` into `third_party/maplibre-native-ffi-src/` and checks out the pinned commit;
2. applies the local patches in `scripts/patches/maplibre-native-ffi-*.patch`, if any (currently none; the last one, needed by copy-free maps, was merged upstream as [maplibre-native-ffi#807](https://github.com/maplibre/maplibre-native-ffi/pull/807) and is in the pinned commit);
3. runs the FFI repository's `.mise/bin/sync-submodules`, which fetches MapLibre Native and the vendor submodules the build needs and applies the FFI's patches;
4. for Android presets, checks that the pinned NDK is installed under `ANDROID_HOME`, adds the Rust target, and runs the FFI's `.mise/bin/sync-rustls-platform-verifier`, which provides the patched `rustls-platform-verifier` source;
5. for each preset, runs `cmake --preset <preset>` and `cmake --build … --target install`, with CMake, Ninja, Rust and cargo-about installed by `mise exec` at the versions the FFI repository's `mise.toml` pins, and copies the install tree into `third_party/maplibre-native-ffi/<preset>/`;
6. for Android presets, builds the FFI's patched `rustls-platform-verifier` Android component with the FFI's Gradle build, and installs its AAR with a POM into a file-based Maven repository;
7. combines the `Frameworks/MaplibreNativeC.framework` that the install of each Apple preset creates into `MaplibreNativeC.xcframework` for the Flutter plugin; Android presets are not part of it;
8. deletes Swift Package Manager's manifest cache, `~/Library/Caches/org.swift.swiftpm/manifests/manifest.db*`.

`darwin/flutter_mapigrade/Package.swift` uses `MaplibreNativeC.xcframework` when the symlink `Frameworks/MaplibreNativeC.xcframework` resolves, and otherwise downloads the xcframework zip that `packages/flutter_mapigrade/maplibre_ffi.lock` names. Swift Package Manager caches its choice by the manifest's contents, so after you remove or rename `third_party/maplibre-native-ffi/MaplibreNativeC.xcframework`, delete `~/Library/Caches/org.swift.swiftpm/manifests/manifest.db*` before the next build. Otherwise the build fails with "does not contain a binary artifact". After you change the zip's URL or checksum in the lock file, run `scripts/update_ffi_pins.sh`, which writes them into `Package.swift`.

Output in `third_party/maplibre-native-ffi/` (gitignored):

- `<preset>/lib/libmaplibre-native-c.dylib`, `<preset>/include/maplibre_native_c.h` and `<preset>/share/maplibre-native-c/` (the FFI license and third-party notices)
- `android-arm64-egl/lib/libmaplibre-native-c.so` (16 KB segment alignment), with the same `include/` and `share/maplibre-native-c/` as the Apple presets; the plugin's Gradle build links it and packages it in the APK
- `android-maven/org/maplibre/nativeffi/rustls-platform-verifier-android/<version>/`, the verifier's AAR and POM, where `<version>` is the first 12 characters of the FFI commit; the AAR's classes are in `org.maplibre.nativeffi.internal.rustlsplatformverifier`, where the FFI's patch moves them. The plugin's Gradle build adds the repository and depends on the AAR, and `mln_android_init` needs it at run time
- `MaplibreNativeC.xcframework` with three slices: `macos-arm64` (a versioned framework, install name `@rpath/MaplibreNativeC.framework/Versions/A/MaplibreNativeC`, minimum macOS 14.3), `ios-arm64` and `ios-arm64-simulator` (flat frameworks, install name `@rpath/MaplibreNativeC.framework/MaplibreNativeC`, minimum iOS 15.5); each has the headers, a module map with the submodules `CallbackAdapter` and `Plugin`, `PrivacyInfo.xcprivacy` and the FFI's license notices, as the FFI's CMake install creates them

Measured on an Apple M2 Max, macOS 26.6.2, Xcode 26.6, from a clean checkout:

- `macos-arm64-metal` (2026-10-09): total wall time 239 s (clone, submodules, mise tool install, configure and build); configure and build alone 123 s
- `ios-arm64-metal` (2026-10-09): configure and build 88 s; `ios-simulator-arm64-metal`: 96 s
- `libmaplibre-native-c.dylib`: about 13 MB per preset (macOS 13,242,488 bytes, iOS 13,153,664 bytes, simulator 13,242,264 bytes), arm64 only

### Check the build with the upstream example

```sh
cd third_party/maplibre-native-ffi-src/examples/swift-map
export PKG_CONFIG_PATH="$PWD/../../build/macos-arm64-metal/install/share/pkgconfig"
swift build --product swift-map --scratch-path .build/macos-arm64-metal \
  -Xlinker -rpath -Xlinker "$PWD/../../build/macos-arm64-metal/install/lib"
.build/macos-arm64-metal/debug/swift-map borrowed-texture
```

The window shows a map of San Francisco.

## Update the FFI

To update MapLibre Native FFI to a new upstream release:

1. In `packages/flutter_mapigrade/maplibre_ffi.lock`, set `MAPLIBRE_FFI_VERSION` to the release's version, `MAPLIBRE_FFI_COMMIT` to the commit of its tag, `MAPLIBRE_FFI_XCFRAMEWORK_URL` to the URL of the release's `MaplibreNativeC.xcframework.zip`, and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` to `swift package compute-checksum` of that zip.
2. Run `scripts/update_ffi_pins.sh`, which writes the URL and checksum into `Package.swift`.
3. Run `scripts/fetch_ffi_release.sh`, which downloads the release's tarballs into `third_party/maplibre-native-ffi-release/<version>/`.
4. Run `scripts/copy_ffi_notices.sh`, which copies the notices of the tarballs into `packages/flutter_mapigrade/notices/`.
5. Run the tests. If you keep a local build (below), run `scripts/build_maplibre_ffi.sh` to rebuild it at the new commit.

`packages/flutter_mapigrade/notices/` is committed. Commit it with every change to `packages/flutter_mapigrade/maplibre_ffi.lock`, so that the review of an FFI update shows its changes to the notices. The package's test `test/notices/ffi_notices_test.dart` fails when the committed notices differ from those of the fetched release. `scripts/copy_ffi_notices.sh` fails when a tarball has a notice file that the script doesn't list; add the file to the script, to `lib/src/notices/third_party_notices.dart` and, for a new directory, to the package's `pubspec.yaml`.
