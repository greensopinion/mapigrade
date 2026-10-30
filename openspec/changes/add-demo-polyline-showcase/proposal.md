## Why

`add-mapigrade-polyline-layer` adds `MapigradePolylineLayer`, which draws polylines in the map below the style's 3D buildings and labels. The demo has no screen that shows this, so a developer who builds the demo can't see where the polylines are drawn, or how they differ from `flutter_map`'s `PolylineLayer`, which draws over the whole map.

## What Changes

- A third showcase, "Polylines", in the gallery after "Flyover" and "Inspect features".
- Its screen shows downtown New York in Liberty, whose tall 3D buildings hide parts of the streets beside them, with routes along streets drawn by `MapigradePolylineLayer`: a solid route with a border, a dashed ferry route over the water, a route with a gradient, and a route with a width in meters.
- A control switches the routes' placement between `LayerPlacement.belowLabels()`, below the buildings and labels, and `LayerPlacement.top()`, above them, so that the developer sees the buildings and labels hide the routes or not.
- The screen offers the demo's styles, as the other showcases do.
- `packages/demo/README.md` gets one sentence for the showcase.

This change depends on `add-mapigrade-polyline-layer`, including its `belowLabels` rule that places polylines below the first `fill-extrusion` layer, and is applied after it.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `demo-app`: the gallery lists a third showcase, and a new requirement describes the polyline screen.

## Impact

- `packages/demo/lib/main.dart`: the gallery entry.
- `packages/demo/lib/src/polylines/`: the screen and the route data.
- `packages/demo/test/polylines/`: tests.
- `packages/demo/README.md`.
- No change to `flutter_mapigrade`.
