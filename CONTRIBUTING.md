# Contributing

This guide is for developers who build, test and measure Mapigrade. The [README](README.md) has the short build and run steps for the demo app; the architecture is in [docs/architecture.md](docs/architecture.md).

## Repository layout

```
packages/mapigrade/                      Flutter plugin (macOS, iOS, Android): native code, map
                                         controller, polylines; doesn't depend on flutter_map
  maplibre_ffi.lock                      the pinned FFI commit, its release if any, and presets
packages/flutter_mapigrade/              MapigradeLayer, the flutter_map layer; no native code
packages/demo/                           demo app: a gallery of showcases on your devices (Android,
                                         iOS, macOS): a Tour de France Femmes flyover with styles
                                         and frame rates, and a feature inspector
packages/test_harness/                   test harness app: integration tests, benchmarks, color check
docs/                                    architecture, packaging, measurements, limitations, concept
                                         and follow-up documents
pubspec.yaml                             pub workspace of the Dart packages
scripts/build_maplibre_ffi.sh            builds MapLibre Native FFI locally (required while no release contains the pinned commit)
scripts/set_version.sh                   sets the version of both packages
third_party/                             fetched FFI release, and the local FFI checkout and build output (gitignored)
```

## Prerequisites

- An Apple silicon Mac with macOS 14.3 or later
- Xcode 26.6 with the macOS and iOS SDKs, and an iOS simulator runtime
- Flutter 3.47.5 with macOS desktop support
- For an iPhone: iOS 15.0 or later, an Apple account added in Xcode (Settings > Accounts) for automatic signing, and the device paired with Xcode. The test harness's iOS project uses development team `2J9XYBV642`; change it in Xcode (Runner > Signing & Capabilities) for another team
- For a local FFI build (see Build MapLibre Native FFI): git and [mise](https://mise.jdx.dev) (`brew install mise`). The build script installs the tools that the FFI's mise configuration pins, including Rust, CMake and Ninja; you don't need them on your path
- CMake for the C++ unit tests (`brew install cmake`)
- For Android: the Android SDK with NDK 30.0.16248370 (Android Studio's SDK Manager, or `sdkmanager "ndk;30.0.16248370"`). The FFI build and Gradle find the SDK through `ANDROID_HOME`; the FFI build uses `~/Library/Android/sdk` when it isn't set, and installs the NDK and CMake versions that the FFI pins into it
- For an Android device: `arm64-v8a`, `armeabi-v7a` or `x86_64`, Android 10 (API 29) or later, with USB debugging turned on and this Mac authorized on the device. For the emulator: an arm64 system image of API 29 or later; we used `sdk_gphone16k_arm64` (API 37, 16 KB pages)

## Pinned versions

| Component | Version |
| --- | --- |
| MapLibre Native FFI | commit `4371ff607e0bd22115d390de27d72a54987cc6c7` on `main`, which no release contains, so every build needs a local FFI build of the presets `macos-arm64`, `ios-arm64`, `ios-simulator-arm64` and `android-arm64` (`packages/mapigrade/maplibre_ffi.lock`) |
| Flutter | 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4 |
| Xcode | 26.6 (17F113), macOS and iOS SDKs; deployment targets macOS 14.3 and iOS 15.0 |
| Android NDK | 30.0.16248370, the version that the FFI's `mise.toml` pins; `minSdk` 24 (the map needs API level 29), ABIs `arm64-v8a`, `armeabi-v7a` and `x86_64` |

The plugin uses Swift Package Manager, the native build integration that the Flutter 3.47.5 plugin template uses by default. It has no podspec, so CocoaPods builds are not supported.

## Run the test harness

The test harness shows the map with a control panel above it: style selection (OpenFreeMap Liberty, MapLibre demo tiles, and an invalid URL that shows the reported failure), zoom, rotate and pan buttons, and a continuous pan switch that changes the camera on every Flutter frame. `--dart-define=LOG_FRAMES=true` prints every displayed frame with its camera, and `--dart-define=CONTINUOUS_PAN=true` starts continuous pan at launch. On iOS, launching through `xcrun devicectl device process launch -e '{"MLT_KEEP_AWAKE":"1"}'` keeps the device from locking during scripted measurements. On Android, keep the device unlocked with the screen on during a measurement: when the activity stops, the plugin pauses rendering.

```sh
# At the repository root
flutter pub get

cd packages/test_harness
flutter run -d macos
flutter run -d <simulator id>             # iOS simulator (Apple silicon Macs only)
flutter run --release -d <iPhone id>      # iPhone; `flutter devices` lists the ids
flutter run --release -d <Android id>     # Android device or emulator, API level 29 or later
```

## Tests

```sh
# C++ unit tests for the core, on the real FFI with headless Metal targets.
# They link a local FFI build if there is one, or else the pinned release's
# framework, which scripts/fetch_ffi_release.sh unpacks when the lock names a
# release.
scripts/build_maplibre_ffi.sh macos-arm64
cd packages/mapigrade
cmake -S test/native -B build/native-tests
cmake --build build/native-tests
ctest --test-dir build/native-tests --output-on-failure

# Dart unit tests of both packages (including the check that mapigrade doesn't import flutter_map)
flutter analyze
flutter test
cd ../flutter_mapigrade
flutter analyze
flutter test

# Integration tests for the spec scenarios (about 40 s each, needs network access)
cd ../test_harness
flutter test integration_test -d macos
flutter test integration_test -d <simulator id>
# On an iPhone, use flutter drive in profile mode, one test file per run: flutter test can't
# start the app over a wireless connection, and since Xcode 27.2 a debug build doesn't start on
# the iPhone. Profile builds have no asserts, so "Polyline layer outside a map layer" fails.
# Keep the iPhone unlocked with the screen on during the run.
flutter drive --profile -d <iPhone id> --driver=test_driver/integration_test.dart \
  --target=integration_test/map_texture_test.dart
# Android device or emulator. Keep the device unlocked with the screen on during the run.
flutter test integration_test -d <Android id>
```

On Android the tests that need display times or plugin-owned display buffers are skipped, and each skip states its reason. On the emulator, "rapid camera updates do not build up a backlog" fails, because the emulator renders OpenGL ES in software; it passes on a device.

The iOS and Android lifecycle tests use test hooks (`package:mapigrade/src/testing.dart`) that call the same functions as the background, foreground and memory warning handlers. The real notifications were checked on an iPhone (design D13, result). On Android, a test hook also makes Flutter remove the map's surface, as it does when the app goes to the background.

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

`packages/mapigrade/maplibre_ffi.lock` pins an FFI commit that no release contains, so the package and the repository's apps build only with a local FFI build. Release-mode builds, which take the FFI from a release through Swift Package Manager or Maven Central, fail with a message that names `scripts/build_maplibre_ffi.sh`. Once the lock names a release, a local build is optional: build one to test an FFI commit that has no release, after setting `MAPLIBRE_FFI_COMMIT` in the lock file. While it exists, the apps of the repository use it in place of the release on every platform; delete `third_party/maplibre-native-ffi/` and the manifest cache (below) to use the release again.

```sh
scripts/build_maplibre_ffi.sh                  # all presets, about 10 minutes
scripts/build_maplibre_ffi.sh ios-arm64        # one preset
```

`scripts/build_maplibre_ffi.sh` builds the FFI at the commit and presets pinned in `packages/mapigrade/maplibre_ffi.lock`: the Apple presets in `MAPLIBRE_FFI_PRESETS` and the Android presets in `MAPLIBRE_FFI_ANDROID_PRESETS`. A preset name as argument builds only that preset; an unknown name fails with the list of known ones.

The script:

1. clones `https://github.com/maplibre/maplibre-native-ffi.git` into `third_party/maplibre-native-ffi-src/` and checks out the pinned commit;
2. trusts the checkout's mise configuration and runs `mise bootstrap --yes --only tools`, which installs the tools that the FFI pins, including Rust and its targets, CMake and Ninja. It leaves out the rest of the FFI's bootstrap, which installs Homebrew packages for bindings that this build doesn't use;
3. for each preset, runs the FFI's `mise run build <preset>` (`mise -E android run build <preset>` for an Android preset), which syncs the FFI's submodules, compiles mln-rs with Cargo and installs the library, and copies the install tree into `third_party/maplibre-native-ffi/<preset>/`;
4. combines the `Frameworks/MaplibreNativeC.framework` that the install of each Apple preset creates into `MaplibreNativeC.xcframework` for the Flutter plugin; Android presets are not part of it;
5. deletes Swift Package Manager's manifest cache, `~/Library/Caches/org.swift.swiftpm/manifests/manifest.db*`.

`darwin/mapigrade/Package.swift` uses `MaplibreNativeC.xcframework` when the symlink `Frameworks/MaplibreNativeC.xcframework` resolves, and otherwise downloads the xcframework zip that `packages/mapigrade/maplibre_ffi.lock` names. Swift Package Manager caches its choice by the manifest's contents, so after you remove or rename `third_party/maplibre-native-ffi/MaplibreNativeC.xcframework`, delete `~/Library/Caches/org.swift.swiftpm/manifests/manifest.db*` before the next build. Otherwise the build fails with "does not contain a binary artifact". After you change the zip's URL or checksum in the lock file, run `scripts/update_ffi_pins.sh`, which writes them into `Package.swift`.

Output in `third_party/maplibre-native-ffi/` (gitignored):

- `<preset>/lib/libmaplibre-native-c.dylib`, `<preset>/include/maplibre_native_c.h` and `<preset>/share/maplibre-native-c/` (the FFI license and third-party notices)
- `android-arm64/lib/libmaplibre-native-c.so`, with the same `include/` and `share/maplibre-native-c/` as the Apple presets; the plugin's Gradle build links it and packages it in the APK
- `MaplibreNativeC.xcframework` with three slices: `macos-arm64`, `ios-arm64` and `ios-arm64-simulator`

Measured on an Apple M2 Max, macOS 26.6.2, Xcode 26.6, from an empty `third_party/` (2026-11-27): the four presets took about 10 minutes, including the clone and the tool installation. Configure and build: `macos-arm64` 159 s, `ios-arm64` 131 s, `ios-simulator-arm64` 137 s, `android-arm64` 160 s. `libmaplibre-native-c.dylib` is about 13 MB per Apple preset, and `libmaplibre-native-c.so` 15 MB.

## Update the FFI

To update MapLibre Native FFI to a new upstream release:

1. In `packages/mapigrade/maplibre_ffi.lock`, set `MAPLIBRE_FFI_VERSION` to the release's version, `MAPLIBRE_FFI_COMMIT` to the commit of its tag (`v<version>`; releases before 0.202610.2 were tagged `core/v<version>`), `MAPLIBRE_FFI_XCFRAMEWORK_URL` to the URL of the release's `MaplibreNativeC.xcframework.zip`, and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` to `swift package compute-checksum` of that zip.
2. Run `scripts/update_ffi_pins.sh`, which writes the URL and checksum into `Package.swift`.
3. Run `scripts/fetch_ffi_release.sh`, which downloads the release's tarballs and `MaplibreNativeC.xcframework.zip` into `third_party/maplibre-native-ffi-release/<version>/` and unpacks the framework there for the native tests.
4. Run `scripts/copy_ffi_notices.sh`, which copies the notices of the tarballs into `packages/mapigrade/notices/`.
5. Run the tests. If you keep a local build (below), run `scripts/build_maplibre_ffi.sh` to rebuild it at the new commit.

`packages/mapigrade/notices/` is committed. Commit it with every change to `packages/mapigrade/maplibre_ffi.lock`, so that the review of an FFI update shows its changes to the notices. The package's test `test/notices/ffi_notices_test.dart` fails when the committed notices differ from those of the fetched release, or, while the lock names no release, of the local build. A notice that the Apple and the Android presets have with the same content is in `notices/common/`; otherwise the Apple presets' copy is in `notices/darwin/`, which only macOS and iOS builds contain, and the Android presets' copy in `notices/android/`, which only Android builds contain. The script copies an HTML notice, such as `rust-std.html`, as its text in a `.txt` file, which `scripts/html_notice_to_text.py` writes, so that the license page shows no markup. The script copies every notice file of the tarballs, and the package lists the notice files that an app's build contains, so a release that adds or removes a notice file needs no change to the code or the tests. Review such a change in the diff of `notices/`: check that a removed notice's component is gone from the release's libraries, and what an added notice covers. To give a new notice's entry a name other than its file name, add the file to `noticeNames` in `lib/src/notices/third_party_notices.dart`.
