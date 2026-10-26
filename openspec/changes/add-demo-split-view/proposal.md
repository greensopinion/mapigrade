## Why

The flyover screen shows what `MapigradeLayer` draws, but a developer who uses raster tiles today can't compare it with what they have now. A split view that shows mapigrade on the left half and raster tiles on the right half, as one map with a seam through the middle, shows the difference in the same place, at the same camera, while the camera moves.

## What Changes

- A new setting on the flyover screen, "Split view", off when the screen opens. When it is on, the left half of the map shows the chosen style through `MapigradeLayer`, and the right half shows OpenStreetMap's standard raster tiles.
- The two halves have the same camera in every frame, so roads, the stage overlays and the rider continue across the seam while the camera moves, during gestures and during the flyover. The overlays are drawn above both halves.
- A 1-pixel vertical line marks the seam, with a "Mapigrade" label to its left and a "Raster (OSM)" label to its right, at the bottom of the map. The line and the labels don't move with the map and don't take gestures.
- The style picker changes only the left half.

Non-goals:

- No raster style that matches the chosen vector style. No keyless raster rendition of the demo's styles exists, so the cartography changes at the seam.
- No draggable seam.
- No split view on the inspect and 3D view screens.
- No change to the recording mode or the README video: the split view is off there.
- No change to the package, the example or the test harness.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `demo-app`: adds the "Split view" requirement; the "Flyover screen" requirement lists it among the requirements of that screen.

## Impact

- Demo code: `packages/demo/lib/src/flyover/flyover_screen.dart` (the setting, and a raster `TileLayer` among the `MapigradeLayer` children), and a new file in `packages/demo/lib/src/flyover/` for the right-half clip and the seam's line and labels. A widget test for the seam's position in `packages/demo/test/flyover/`.
- Dependencies: none. `TileLayer` is part of `flutter_map`, which the demo depends on.
- Network: with the split view on, the demo loads tiles from `tile.openstreetmap.org`, with the demo's application ID as the user agent package name, as the OpenStreetMap tile usage policy requires. The OpenStreetMap attribution that the screen shows already covers the tiles.
- Documentation: `packages/demo/README.md` (the split view).
- Out of date, separate from this change: the doc comment of `MapigradeLayer.children` says that only macOS and iOS draw the children at the camera of the displayed map frame, but Android does too since 96a4ad7.
