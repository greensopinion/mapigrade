## Why

Applications draw routes and tracks with `flutter_map`'s `PolylineLayer`, which paints above the whole map, so a route covers road names and POI labels. It also projects, culls, simplifies and paints every polyline on the UI thread in every Flutter frame while the camera moves, which costs time for many or long polylines. MapLibre draws lines as style layers on the GPU from tiled GeoJSON, between the style's own layers, and the FFI already offers GeoJSON sources and runtime style layers.

## What Changes

- Add `MapigradePolylineLayer`, a widget that an application places in `MapigradeLayer.children`. It gives its polylines to MapLibre as one GeoJSON source and `line` style layers, so MapLibre draws them in the map frame.
- Add `MapigradePolyline`, the polyline model. It keeps `flutter_map`'s field names and defaults for the properties that MapLibre can draw: `points`, `color`, `strokeWidth`, `useStrokeWidthInMeter`, `borderStrokeWidth`, `borderColor`, `strokeCap` and `strokeJoin`. It adds `dashes`, in multiples of the stroke width, and `gradientColors` with `gradientStops`, a gradient along the length of the line. `MapigradePolyline.fromPolyline` converts a `flutter_map` `Polyline`, and fails an assertion in debug builds for a gradient, because `flutter_map`'s gradient means something else.
- Add `LayerPlacement`, which places the polylines among the style's layers: below the labels by default, below a named style layer, or above all style layers. When the named layer is missing, the polylines are drawn above all style layers and the layer reports a `LayerLoadException`.
- The rendering is MapLibre's, not a copy of `flutter_map`'s painter. The documentation states the differences: the gradient, dots drawn as dashes of length 0 with round caps, `PatternFit` ignored, and hit testing not available.
- Polylines stay on the map across style loads.
- The parts below the polyline translation take GeoJSON and style layer JSON of any geometry type, so that polygon or circle layers can be added later without new native work. No public layer for arbitrary GeoJSON is part of this change.
- Deferred: hit testing (`hitValue`, `LayerHitNotifier`), polygon and circle layers, a public GeoJSON layer, and synchronous tiling for frequent updates.

## Capabilities

### New Capabilities
- `polyline-layer`: the polyline model and its converter, the layer in `MapigradeLayer.children`, how each property is drawn, draw order, placement among the style's layers, the order of several polyline layers, style loads, and updates.

### Modified Capabilities
- `map-layer`: the requirement "Base layer of a flutter_map map" states that every child is drawn above the map; a `MapigradePolylineLayer` child is drawn in the map instead.
- `package-api`: the main library exports `MapigradePolyline`, `MapigradePolylineLayer` and `LayerPlacement`, and the naming rule allows exported names that start with `Mapigrade`, which it now allows only for `MapigradeLayer`.

## Impact

- Dart: the model, the layer and `LayerPlacement` under `packages/flutter_mapigrade/lib/src/`, an internal registration through which a widget in the children reaches the map, and FFI bindings for new C ABI functions.
- Native core (`packages/flutter_mapigrade/src/core/`): runtime GeoJSON sources and style layers, kept by the map and installed again after each style load, with the position among the style's layers resolved on the map thread.
- Tests: native tests, widget tests with a fake native side, and integration tests in `packages/test_harness` on macOS, iOS and Android.
- Documentation: the package README, `docs/architecture.md` and `CHANGELOG.md`.
- No FFI change is needed. The pinned release 0.202610.2 has the GeoJSON source and style layer functions.
