## Unreleased

- First release. The package contains the native code of `flutter_mapigrade` 0.1.0 and the types that its map widgets share, with these changes since `flutter_mapigrade` 0.1.0:
  - The map is drawn by mln-rs, the Rust port of MapLibre Native, through MapLibre Native FFI <release>. Rendering details such as anti-aliasing can differ from `flutter_mapigrade` 0.1.0.
  - The license page lists mln-rs, the Rust standard library and the Rust crates of the app's platform in place of MapLibre Native, ICU, FastPFOR, nunicode, PMTiles and the Android NDK C++ runtime.
  - `LayerController`, `LayerException` and its subclasses, `LayerMetrics`, `LayerMetricsSnapshot` and `LayerPlacement` are named `MapigradeController`, `MapigradeException` and its subclasses, `MapigradeMetrics`, `MapigradeMetricsSnapshot` and `OverlayPlacement`.
