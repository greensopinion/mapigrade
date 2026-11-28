<p align="center">
  <img src="https://raw.githubusercontent.com/greensopinion/mapigrade/main/assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# mapigrade

Renders a [MapLibre Native](https://github.com/maplibre/maplibre-native) map on its own thread into a Flutter `Texture` widget, through [MapLibre Native FFI](https://github.com/maplibre/maplibre-native-ffi). It doesn't depend on [`flutter_map`](https://pub.dev/packages/flutter_map).

The package contains the native code of Mapigrade and the types that its map widgets share:

- `MapigradeController`, which controls everything about a map except its camera: in this version, feature queries and feature state;
- `MapigradePolylineLayer` and `MapigradePolyline`, which the map draws among the style's own layers, and `OverlayPlacement`;
- `MapigradeMetrics`, `HttpHeaderRule`, `QueriedFeature`, and `MapigradeException` with its subclasses.

In this version the only map widget is `MapigradeLayer` of [`flutter_mapigrade`](https://pub.dev/packages/flutter_mapigrade), which displays the map as the base layer of a `flutter_map` map. To display a map, depend on `flutter_mapigrade`; its README describes the installation, the application settings and the usage. A later version adds `MapigradeMap`, a map widget that doesn't need `flutter_map`.

The package is pre-1.0: the API can change between 0.x releases. `mapigrade` and `flutter_mapigrade` always have the same version, and `flutter_mapigrade` depends on the `mapigrade` release with its own version and no other.

## Libraries

Import `package:mapigrade/mapigrade.dart`. It is the package's only API.

`package:mapigrade/src/integration.dart` is for `flutter_mapigrade` only. Applications must not import it: it isn't API, and it can change in any version. `package:mapigrade/src/testing.dart` is for the repository's test harness, and the same applies to it.

## Supported platforms

| Platform | Minimum version | Architecture |
| --- | --- | --- |
| Android | API level 29 (apps build from API level 24) | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| iOS | 15.0 | arm64 (devices, and the simulator on Apple silicon Macs) |
| macOS | 14.3 | arm64 |

On iOS and macOS the plugin supports Swift Package Manager only; it has no podspec. Apps built for web build with the package, but it draws no map there.

The package contains no native libraries of MapLibre Native FFI. The first build on a machine downloads them from the FFI release that the package pins; the `flutter_mapigrade` README lists the downloads.
