# Adoption gaps

What app developers need from the package that the publish-readiness change doesn't cover. The publish-readiness change covers distribution, CI, notices and the FFI release pin. This list was written on 2026-10-20 against commit 7b2ebc6, ordered by importance within each section.

## Gaps that prevent adoption

### No map on web

Since the web-build-compatibility change (commit 8e688cf), apps built for web build with the package, and `MapigradeLayer.isSupported` is false on web, so an app places another layer there. The layer draws no map on web. Two options for drawing one: `vector_map_tiles` with the same style, or maplibre-gl-js rendering into an offscreen canvas, with the layer drawing each frame as an image.

### Archived iOS and macOS builds fail without `STRIP_STYLE`

Without `STRIP_STYLE = non-global` on the `Runner` target, archived builds have no `map_texture_*` symbols in the executable, and the layer reports a `LayerCreateException`. The README documents the setting, but debug builds and `flutter run --release` don't show the failure, so a developer finds it only after a TestFlight or App Store build.

Options:

- Remove the dependency on symbol lookup in the process, for example by having the plugin pass a table of function pointers to Dart at registration.
- Report the missing setting in debug and profile builds, for example by checking for the exported functions in a way that matches the archived build's behavior.

### The application settings are long

An app needs `minSdk = 29`, the iOS and macOS deployment targets, `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`, `ARCHS = arm64`, `STRIP_STYLE = non-global`, the macOS network client entitlement, and Swift Package Manager on iOS and macOS. Each setting is a step where a developer can fail. For every setting that the plugin can't apply itself, provide a checklist or a script that checks an app.

The package doesn't support Intel Macs, including the iOS simulator on Intel Macs, because the FFI's xcframework has arm64 slices only. State this in the plugin README's installation section.

### The minimum Flutter version is high

The package requires Flutter 3.47.0 and Dart 3.13.4. Many production apps use older releases. Test the package against the oldest Flutter release that supports its build hooks, and lower the constraints to that release.

## Gaps for production apps

### No attribution

`limitations.md` states that a product must show the OpenStreetMap attribution. The layer doesn't expose the attribution of the style's sources. Expose it, so that an app can show it with `flutter_map`'s `RichAttributionWidget`, or add an example that does.

### Device coverage

- Android ran on one GPU, the Adreno 620 of the Pixel 4a (5G). Mali and PowerVR GPUs, Samsung devices and devices with little memory weren't tested. A Firebase Test Lab matrix that runs the integration tests would cover them.
- The `armeabi-v7a` and `x86_64` builds haven't run on a device or emulator (tasks 8.2 and 9.2 of the publish-readiness change).
- The iPhone checks of the publish-readiness change are deferred (tasks 12.1 and 12.2).
- The thermal behavior with rendering ahead and the battery use weren't measured.

### Map features

The package has no API to show or hide style layers, set filters, add a GeoJSON source, query the features at a point, or download offline regions. `flutter_map` overlays cover markers and polylines, but apps that move from `maplibre_gl` need querying and runtime style changes. Feature queries at a tapped point would make the package usable for more apps than any of the other features.

### No guidance on choosing between this package and vector_map_tiles

`vector_map_tiles` is the alternative for `flutter_map` users who want vector maps. Write a short guide that compares the two (rendering fidelity, app size, platforms, web support) and describes how to migrate.

## Smaller items

- Run `pana` before publishing 0.0.1, to see the pub points (documentation coverage, example, platform tags) before pub.dev scores the package.
- Add GitHub issue templates that ask for the device, GPU, Flutter version and FFI version.
- State in the README what "experimental" means: whether 0.x versions can change the API without notice, and how soon the package adopts new FFI releases.
- Document in the plugin README that the release APK is 86.1 MB with all three ABIs, and how to build for fewer ABIs (`abiFilters` with `disable-abi-filtering=true`). This is in `limitations.md` only.
