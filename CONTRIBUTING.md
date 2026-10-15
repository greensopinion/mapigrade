# Contributing

This guide is for developers who build, test and measure Mapigrade. The [README](README.md) has the short build and run steps; the architecture is in [docs/architecture.md](docs/architecture.md).

## Prerequisites

- An Apple silicon Mac with macOS 14.3 or later
- Xcode 26.6 with the macOS and iOS SDKs, and an iOS simulator runtime
- Flutter 3.47.5 with macOS desktop support
- For an iPhone: iOS 15.5 or later, an Apple account added in Xcode (Settings > Accounts) for automatic signing, and the device paired with Xcode. The test harness's iOS project uses development team `2J9XYBV642`; change it in Xcode (Runner > Signing & Capabilities) for another team
- git and [mise](https://mise.jdx.dev) (`brew install mise`); the build script installs CMake, Ninja, Rust and cargo-about through mise
- CMake for the C++ unit tests (`brew install cmake`)

## Pinned versions

| Component | Version |
| --- | --- |
| MapLibre Native FFI | commit `677a1cfdf1ab2b914f633d4abc790b7136d3a321`, presets `macos-arm64-metal`, `ios-arm64-metal` and `ios-simulator-arm64-metal` (`scripts/maplibre_ffi.lock`) |
| Flutter | 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4 |
| Xcode | 26.6 (17F113), macOS and iOS SDKs; deployment targets macOS 14.3 and iOS 15.5 |

The plugin uses Swift Package Manager, the native build integration that the Flutter 3.47.5 plugin template uses by default. It has no podspec, so CocoaPods builds are not supported.

## Run the test harness

The test harness shows the map with a control panel above it: style selection (OpenFreeMap Liberty, MapLibre demo tiles, and an invalid URL that shows the reported failure), zoom, rotate and pan buttons, and a continuous pan switch that changes the camera on every Flutter frame. `--dart-define=LOG_FRAMES=true` prints every displayed frame with its camera, and `--dart-define=CONTINUOUS_PAN=true` starts continuous pan at launch. On iOS, launching through `xcrun devicectl device process launch -e '{"MLT_KEEP_AWAKE":"1"}'` keeps the device from locking during scripted measurements.

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
```

The iOS lifecycle tests use test hooks (`package:flutter_mapigrade/src/testing.dart`) that call the same functions as the background, foreground and memory warning handlers. The real notifications were checked on an iPhone (design D13, result).

## Measurements

The benchmark and the memory and color measurements are described, with their commands and results, in [docs/benchmarks.md](docs/benchmarks.md).

## Build MapLibre Native FFI

`scripts/build_maplibre_ffi.sh` builds the FFI at the commit and presets pinned in `scripts/maplibre_ffi.lock`. A preset name as argument builds only that preset.

The script:

1. clones `https://github.com/maplibre/maplibre-native-ffi.git` into `third_party/maplibre-native-ffi-src/` and checks out the pinned commit;
2. applies the local patches in `scripts/patches/maplibre-native-ffi-*.patch`, if any (currently none; the last one, needed by copy-free maps, was merged upstream as [maplibre-native-ffi#807](https://github.com/maplibre/maplibre-native-ffi/pull/807) and is in the pinned commit);
3. runs the FFI repository's `.mise/bin/sync-submodules`, which fetches MapLibre Native and the vendor submodules the build needs and applies the FFI's patches;
4. for each preset, runs `cmake --preset <preset>` and `cmake --build … --target install`, with CMake, Ninja, Rust and cargo-about installed by `mise exec` at the versions the FFI repository's `mise.toml` pins, and copies the install tree into `third_party/maplibre-native-ffi/<preset>/`;
5. runs `scripts/copy_ffi_notices.sh` with the presets it built, which copies each preset's `share/maplibre-native-c/LICENSE` and `licenses/` unchanged into `packages/flutter_mapigrade/notices/`; the package shows them in Flutter's license registry (`docs/limitations.md`, "Licenses and third-party notices");
6. wraps each installed preset's dylib in a framework and combines them into `MapLibreNativeC.xcframework` for the Flutter plugin.

Output in `third_party/maplibre-native-ffi/` (gitignored):

- `<preset>/lib/libmaplibre-native-c.dylib`, `<preset>/include/maplibre_native_c.h` and `<preset>/share/maplibre-native-c/` (the FFI license and third-party notices)
- `MapLibreNativeC.xcframework` with three slices: `macos-arm64` (a versioned framework, install name `@rpath/MapLibreNativeC.framework/Versions/A/MapLibreNativeC`), `ios-arm64` and `ios-arm64-simulator` (flat frameworks, install name `@rpath/MapLibreNativeC.framework/MapLibreNativeC`, minimum iOS 15.5); each has the headers and a module map

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

To update MapLibre Native FFI, change the commit in `scripts/maplibre_ffi.lock`, run `scripts/build_maplibre_ffi.sh`, and run the tests.

`packages/flutter_mapigrade/notices/` is committed. Commit it with every change to `scripts/maplibre_ffi.lock`, so that the review of an FFI update shows its changes to the notices. The package's test `test/notices/ffi_notices_test.dart` fails when the committed notices differ from those of a preset installed at the pinned commit. `scripts/copy_ffi_notices.sh` fails when a preset installs a notice file that the script doesn't list; add the file to the script, to `lib/src/notices/third_party_notices.dart` and, for a new directory, to the package's `pubspec.yaml`.
