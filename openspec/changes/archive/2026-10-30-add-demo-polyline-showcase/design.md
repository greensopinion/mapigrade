## Context

The demo has two showcases, each a screen with its own map, listed by `Gallery` in `lib/src/gallery.dart` from `_showcases` in `lib/main.dart` (design D190). The screens share the style picker, the panel and the attribution in `lib/src/common/`.

Of the demo's styles, only Liberty has 3D buildings: its layer `building-3d` (`fill-extrusion`, from zoom 14). `add-mapigrade-polyline-layer` places polylines with `LayerPlacement.belowLabels()` below the first `fill-extrusion` layer when the style has one, otherwise above the last layer that isn't a `symbol` layer. In Liberty the routes are then below the buildings and the labels; in Bright and Positron, which have no 3D buildings, below the labels.

`flutter_map` has no pitch yet, so the map is always viewed from straight above. MapLibre draws 3D buildings with a perspective projection, so away from the center of the screen a tall building's sides are visible and cover the ground next to it (inferred from MapLibre's projection; task 2.2 checks it on the screen).

## Goals / Non-Goals

**Goals:**
- Show a developer where `MapigradePolylineLayer` draws polylines relative to 3D buildings and labels, and the polyline properties that MapLibre draws differently from `flutter_map`: borders, dashes, gradients along the line and widths in meters.

**Non-Goals:**
- Pitch. When `flutter_map` gets pitch, a follow-up can add a tilt control.
- A side-by-side comparison with `flutter_map`'s `PolylineLayer`. The "On top" placement shows the routes above everything, which is where `PolylineLayer` draws them.
- Hit testing on the routes, which `MapigradePolylineLayer` doesn't support.
- Changing the flyover's stage routes to `MapigradePolylineLayer`.

## Decisions

### D204: Screen

`lib/src/polylines/polyline_screen.dart` holds `PolylineScreen`: a `FlutterMap` with `MapigradeLayer` as its base layer, the style picker, a `SegmentedButton` for the placement, the legend in the demo's panel card, and the attribution. The camera opens at 40.7075, -74.0110, zoom 16, the Financial District between Broadway, Wall Street and West Street. The screen keeps the chosen style and placement in its state; a style change gives `MapigradeLayer` the new style URL and keeps the `MapigradePolylineLayer` child as it is, so the routes follow the new style's load (polyline-layer spec, "Polylines across style loads").

### D205: Route data

`lib/src/polylines/routes.dart` holds the four routes as `const` lists of `LatLng`, one point at each intersection or bend, and builds a `List<MapigradePolyline>` once, as a top-level `final`, so that rebuilds of the screen pass the same list and send nothing (polyline-layer spec, "Polyline updates"). The points are picked by hand along the street centerlines and checked against Liberty's road layer on a screenshot (task 1.2). Hand-picked points need no data download, and the attribution already names OpenStreetMap, from whose data the street positions are read.

| Route | Drawn as |
|---|---|
| Broadway | 6 px, blue, 3 px white border |
| Staten Island Ferry | 4 px, orange, dashes `[2, 2]` |
| West Street | 6 px, gradient from green to red |
| Wall Street | 12 m, purple, translucent |

The four routes have different caps and dashes in this order, so the layer draws them with separate runs; the order of the list, which is the draw order, puts the translucent Wall Street route last.

### D206: Placement control

The `SegmentedButton` has two segments, "Below buildings and labels" (`LayerPlacement.belowLabels()`) and "On top" (`LayerPlacement.top()`), and passes the chosen value as the `MapigradePolylineLayer`'s `placement`. A placement change moves the routes' style layers without sending their data again (polyline-layer design: a placement change moves layers).

Alternative considered: a third segment `LayerPlacement.belowLayer('building-3d')`. Rejected because it is the same as "Below buildings and labels" in Liberty, and in the other styles it draws on top and reports a load failure.

### D207: Gallery entry

The entry is third, titled "Polylines", with the sentence "See routes through downtown New York drawn in the map below its 3D buildings and labels, and draw them on top instead."

## Risks / Trade-offs

- [At zoom 16 and without pitch, buildings may hide too little of the routes to see] → Task 2.2 checks the scenario "Buildings hide the routes" on the screen. If the effect is too small, the camera opens at zoom 17 and closer to the tallest buildings beside Broadway, and the spec's opening zoom changes with it.
- [Hand-picked points drift off the streets] → Task 1.2 checks them against the road layer.
- [OpenFreeMap tiles change, or the network is unavailable] → The screen shows the failure as the other showcases do; the routes don't depend on the tiles.
