## Unreleased

- **BREAKING**: these types are renamed, without aliases for the old names:

  | 0.1.0 | Now |
  | --- | --- |
  | `LayerController` | `MapigradeController` |
  | `LayerException` | `MapigradeException` |
  | `LayerCreateException` | `MapigradeCreateException` |
  | `LayerLoadException` | `MapigradeLoadException` |
  | `LayerQueryException` | `MapigradeQueryException` |
  | `LayerRenderException` | `MapigradeRenderException` |
  | `LayerMetrics` | `MapigradeMetrics` |
  | `LayerMetricsSnapshot` | `MapigradeMetricsSnapshot` |
  | `LayerPlacement` | `OverlayPlacement` |

- `flutter_mapigrade` depends on the new package [`mapigrade`](https://pub.dev/packages/mapigrade), which contains the types above, and exports them: `package:flutter_mapigrade/flutter_mapigrade.dart` is still the only import you need.
- The map is drawn by mln-rs, the Rust port of MapLibre Native, through MapLibre Native FFI <release>. Rendering details such as anti-aliasing can differ from 0.1.0.
- Your app's license page lists `mapigrade`, mln-rs, the Rust standard library and the Rust crates of the app's platform, in place of MapLibre Native, ICU, FastPFOR, nunicode, PMTiles and the Android NDK C++ runtime.
- `MapigradeLayer.isSupported` and `MapigradeLayer.maximumCacheSizeBytes` are the same settings as `Mapigrade.isSupported` and `Mapigrade.maximumCacheSizeBytes` in `mapigrade`: setting the cache size through either class sets it for both.

## 0.1.0

- Updated MapLibre Native FFI to 0.202610.3.
- Breaking change on Android: the map sends HTTP requests through the platform's HTTP client, which applies the app's network security configuration. Android blocks cleartext HTTP by default, so a style URL or a URL in a style that starts with `http://` needs the app to allow cleartext traffic to its host. `https://` and `asset://` URLs work as before.
- The Android license entries for Kotlin and rustls-platform-verifier are removed, because the FFI's Android library no longer contains that code.
- Disposing a map no longer blocks the platform thread while the map thread stops. On Android this blocking caused an ANR.

## 0.0.4

- Added `MapigradePolylineLayer`, which an application places in the `children` of `MapigradeLayer`, and `MapigradePolyline`. The map draws the polylines among the style's own layers, by default below the labels, and keeps them across style loads. `LayerPlacement` places them below the labels, below a named style layer, or above all style layers.

## 0.0.3

- Lowered the plugin's Android `minSdk` from 29 to 24, so that apps with Flutter's default `minSdk` build without an override. The map still needs API level 29; below it `MapigradeLayer.isSupported` is false.
- Added `LayerController`, which `MapigradeLayer` takes as `controller`, to query the features that the map renders at a point or in a rectangle (`QueriedFeature`), and to set and remove their feature state, for example to identify and highlight the feature the user tapped.

## 0.0.2

- Lowered the minimum iOS version from 15.5 to 15.0.
- Updated MapLibre Native FFI to 0.202610.2.

## 0.0.1

Initial release. `MapigradeLayer` displays a MapLibre Native map as the base layer of a `flutter_map` map.

Supported platforms: Android API level 29 (`arm64-v8a`, `armeabi-v7a` and `x86_64`), iOS 15.5 (arm64) and macOS 14.3 (arm64).
