<p align="center">
  <img src="assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# Mapigrade

A proof of concept that renders a MapLibre Native map on the GPU into a Flutter `Texture` widget on macOS, iOS and Android, through MapLibre Native FFI, with no platform view and no CPU pixel readback. Flutter widgets placed above the map draw on top of it and receive input.

macOS, iOS and Android (arm64, Android 10 or later) are complete. For how to use the plugin in an app, see [packages/flutter_mapigrade/README.md](packages/flutter_mapigrade/README.md). To try it on your own devices, build the demo app: [packages/demo/README.md](packages/demo/README.md).

## Documentation

- Build, tests, measurements and FFI updates: [CONTRIBUTING.md](CONTRIBUTING.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- Packaging and release build checks: [docs/packaging.md](docs/packaging.md)
- Measurements: [docs/benchmarks.md](docs/benchmarks.md)
- Limitations, licenses and findings: [docs/limitations.md](docs/limitations.md)
- Follow-up for Flutter: [docs/flutter-texture-cache-followup.md](docs/flutter-texture-cache-followup.md)
- Requirements: `openspec/specs/` (`map-texture`, `map-layer`, `package-api`, `third-party-notices`); designs of finished changes: `openspec/changes/archive/`

## Repository layout

```
packages/flutter_mapigrade/              Flutter plugin (macOS, iOS, Android)
  lib/src/texture/                       Dart API: MapTextureController, MapTextureView, @Native bindings
  lib/src/testing.dart                   test hooks and measurement helpers (not for applications)
  lib/src/layer/                         flutter_map layer (MapigradeLayer)
  src/core/                              C++ core: map thread, commands, buffer state, C ABI (no platform dependencies)
  darwin/flutter_mapigrade/              Swift package shared by macOS and iOS: Metal render target,
                                         FlutterTexture, plugin class, iOS lifecycle observers
  android/                               Android plugin: Gradle module, Kotlin plugin class, EGL render target
                                         (src/main/cpp/), CMake build of the core
  hook/build.dart                        build hook that names the Android library for @Native
  example/                               usage example of the public API (Android, iOS, macOS)
  test/                                  Dart unit tests; test/native/ C++ unit tests for the core
packages/demo/                           demo app: styles, frame rates and a Tour de France Femmes
                                         flyover on your own devices (Android, iOS, macOS)
  tool/                                  the script that computes the stage routes
packages/test_harness/                   test harness app: integration tests, benchmarks, color check
  integration_test/                      spec scenarios (map_texture_test.dart), memory and color
                                         measurements (run with flutter drive)
  test_driver/                           driver for flutter drive
docs/                                    architecture, packaging, measurements, limitations, concept
                                         and follow-up documents
pubspec.yaml                             pub workspace of the Dart packages
scripts/build_maplibre_ffi.sh            builds the pinned MapLibre Native FFI, and on Android its verifier AAR
scripts/maplibre_ffi.lock                the pinned FFI commit and presets
third_party/                             FFI checkout and build output (gitignored)
```

## Prerequisites

An Apple silicon Mac with macOS 14.3 or later, Xcode 26.6, Flutter 3.47.5, git and [mise](https://mise.jdx.dev). For Android, also the Android SDK with NDK 30.0.16248370. The full list, including what an iPhone and an Android device need, and the pinned versions are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Build and run

```sh
# 1. Build MapLibre Native FFI for macOS, iOS, the iOS simulator and Android
#    (the Apple presets take about 7 minutes on an M2 Max from a clean clone; a
#    preset name as argument builds only that preset)
scripts/build_maplibre_ffi.sh

# 2. Get the Dart dependencies of the workspace, then run the test harness
flutter pub get
cd packages/test_harness
flutter run -d macos
flutter run -d <simulator id>             # iOS simulator (arm64 only)
flutter run --release -d <iPhone id>      # iPhone; `flutter devices` lists the ids
flutter run --release -d <Android id>     # Android device or arm64 emulator, API 29 or later
```
