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
