## 0.0.1

Initial release. The library `package:flutter_mapigrade/flutter_mapigrade.dart` exports:

- `MapigradeLayer`: displays a MapLibre Native map as the base layer of a `flutter_map` map, with the parameters `styleUrl`, `styleJson`, `alignment`, `onStyleLoaded` and `onError`.
- `LayerAlignment`: how the layer aligns the map with the overlays while the camera changes: `LayerAlignment.prediction()` (the default) or `LayerAlignment.none`.
- `LayerException` and its subclasses `LayerLoadException`, `LayerRenderException` and `LayerCreateException`: the failures that the layer reports to `onError`.

Supported platforms: Android (API level 29, arm64), iOS 15.5 (arm64) and macOS 14.3 (arm64).
