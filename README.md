<p align="center">
  <img src="assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# Mapigrade

Mapigrade is an experimental Flutter plugin that renders MapLibre Native maps into a Flutter `Texture` widget, for use as the base layer of a `flutter_map` map.

Because the map is part of Flutter's scene, it appears in screen captures and Flutter's effects apply to it. Mapigrade also keeps `flutter_map` overlays aligned with the displayed map frame, including while the camera moves.

The usual way to show a native map in Flutter is a platform view, which Flutter composites separately from its own widgets. Depending on the platform and configuration, this causes defects:

- Overlays move relative to the map while the camera moves.
- Captures with `RepaintBoundary.toImage` don't contain the map.
- Effects such as `ColorFiltered` and `ShaderMask` leave the map unchanged.

Mapigrade doesn't use a platform view, so it avoids these defects.

https://github.com/user-attachments/assets/fe764361-10ca-4e47-acc8-d8824cf6dbdf

## Status

Mapigrade runs on macOS and iOS (arm64), and on Android (API level 29 or later; `arm64-v8a`, `armeabi-v7a` and `x86_64`). We haven't yet validated it for production use.

Use Mapigrade in your app: [packages/flutter_mapigrade](packages/flutter_mapigrade/)

Try the demo: [packages/demo](packages/demo/)

## Documentation

- Architecture: [docs/architecture.md](docs/architecture.md)
- Limitations, licenses and findings: [docs/limitations.md](docs/limitations.md)
- Benchmarks: [docs/benchmarks.md](docs/benchmarks.md)
- Platform view comparison: [docs/platform-view-comparison.md](docs/platform-view-comparison.md)
- Build, tests, measurements and FFI updates: [CONTRIBUTING.md](CONTRIBUTING.md)
- Packaging and release build checks: [docs/packaging.md](docs/packaging.md)

## Repository layout

```
packages/flutter_mapigrade/    Flutter plugin
packages/demo/                 demo app
packages/test_harness/         integration tests and benchmarks
docs/                          architecture, benchmarks and limitations
```

The full layout is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Development requirements

Apps that use the plugin don't build MapLibre Native FFI. The plugin uses the prebuilt libraries of the pinned FFI release, through Swift Package Manager on iOS and macOS and from Maven Central on Android. The demo app, the example and the test harness in this repository use the same release. A local FFI build is optional; it is for testing an FFI commit that has no release ([CONTRIBUTING.md](CONTRIBUTING.md), "Build MapLibre Native FFI").

We develop and test on an Apple silicon Mac with macOS 14.3 or later, Xcode 26.6 and Flutter 3.47.5, and for Android, the Android SDK with NDK 30.0.16248370. These are the versions we test with, not minimum versions; other versions may work. The full list, including what an iPhone and an Android device need, and the pinned versions are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Build and run

```sh
# Get the Dart dependencies of the workspace, then run the demo app. The
# first build downloads the MapLibre Native FFI release.
flutter pub get
cd packages/demo
flutter run -d macos
flutter run -d <simulator id>             # iOS simulator (Apple silicon Macs only)
flutter run --release -d <iPhone id>      # iPhone; `flutter devices` lists the ids
flutter run --release -d <Android id>     # Android device or emulator, API level 29 or later
```

To work on the plugin, run the test harness instead; see [CONTRIBUTING.md](CONTRIBUTING.md).
