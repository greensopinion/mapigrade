<p align="center">
  <img src="assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# Mapigrade

Mapigrade is an experimental Flutter plugin that renders MapLibre Native maps directly into a Flutter `Texture` widget, using MapLibre Native FFI and GPU rendering. It uses no platform view and no CPU pixel readback.

https://github.com/user-attachments/assets/fe764361-10ca-4e47-acc8-d8824cf6dbdf

`MapigradeLayer` draws its `flutter_map` overlays at the camera of the map frame that each Flutter frame displays, so markers and routes stay aligned with the map while the camera moves. In the alignment benchmark on macOS and iOS, no Flutter frame had an alignment error over 1 logical pixel during steady pans, flings, abrupt stops and reversals. On Android we checked alignment by hand. The map and the overlays still lag the live `flutter_map` camera together, by about one Flutter frame of camera movement.

Unlike a map in a platform view on iOS, the map can be captured with `RepaintBoundary.toImage`: our integration tests capture it on macOS, iOS and Android. The comparison with a platform view is in [docs/platform-view-comparison.md](docs/platform-view-comparison.md).

Mapigrade runs on macOS and iOS (arm64), and on Android (API level 29 or later; `arm64-v8a`, `armeabi-v7a` and `x86_64`). We haven't yet validated it for production use.

For how to use the plugin in an app, see [packages/flutter_mapigrade](packages/flutter_mapigrade/). To try it on your devices, build the demo app: [packages/demo](packages/demo/).

## Documentation

- Build, tests, measurements and FFI updates: [CONTRIBUTING.md](CONTRIBUTING.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- Packaging and release build checks: [docs/packaging.md](docs/packaging.md)
- Measurements: [docs/benchmarks.md](docs/benchmarks.md)
- Limitations, licenses and findings: [docs/limitations.md](docs/limitations.md)
- Platform view comparison: [docs/platform-view-comparison.md](docs/platform-view-comparison.md)

## Repository layout

```
packages/flutter_mapigrade/              Flutter plugin (macOS, iOS, Android)
  maplibre_ffi.lock                      the pinned FFI release, commit and presets
packages/demo/                           demo app: styles, frame rates and a Tour de France Femmes
                                         flyover on your devices (Android, iOS, macOS)
packages/test_harness/                   test harness app: integration tests, benchmarks, color check
docs/                                    architecture, packaging, measurements, limitations, concept
                                         and follow-up documents
pubspec.yaml                             pub workspace of the Dart packages
scripts/build_maplibre_ffi.sh            builds MapLibre Native FFI locally (optional), and on Android its verifier AAR
third_party/                             fetched FFI release, and the local FFI checkout and build output (gitignored)
```

## Development requirements

Apps that use the plugin don't build MapLibre Native FFI. The plugin uses the prebuilt libraries of the pinned FFI release, through Swift Package Manager on iOS and macOS and from Maven Central on Android. The demo app, the example and the test harness in this repository use the same release. A local FFI build is optional; it is for testing an FFI commit that has no release ([CONTRIBUTING.md](CONTRIBUTING.md), "Build MapLibre Native FFI").

We develop and test on an Apple silicon Mac with macOS 14.3 or later, Xcode 26.6 and Flutter 3.47.5, and for Android, the Android SDK with NDK 30.0.16248370. These are the versions we test with, not minimum versions; other versions may work. The full list, including what an iPhone and an Android device need, and the pinned versions are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Build and run

```sh
# Get the Dart dependencies of the workspace, then run the test harness. The
# first build downloads the MapLibre Native FFI release.
flutter pub get
cd packages/test_harness
flutter run -d macos
flutter run -d <simulator id>             # iOS simulator (Apple silicon Macs only)
flutter run --release -d <iPhone id>      # iPhone; `flutter devices` lists the ids
flutter run --release -d <Android id>     # Android device or emulator, API level 29 or later
```
