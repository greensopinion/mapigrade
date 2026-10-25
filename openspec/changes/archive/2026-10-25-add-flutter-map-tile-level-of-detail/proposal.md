## Why

On a pitched `flutter_map` map, the tile layer loads every tile in the bounding box of the visible ground, plus a buffer around that box, all at one zoom. At 60° and rotation 45° on a phone-sized viewport that is 132 tiles, where 28 tiles cover the visible ground at a suitable zoom and 64 with the pan buffer, so tiles take longer to appear, use more decoded image memory and transfer more data. Distant tiles are loaded at full resolution and drawn at 0.4 times their size, and the nearest tiles, which the user sees largest, are not loaded first. This is change 5 in `docs/map-pitch-concept.md`.

## What Changes

This change is implemented in our `flutter_map` fork (greensopinion/flutter_map), on the branch `map-pitch`. It changes nothing in mapigrade.

- The tile layer loads only tiles that cover the ground visible in the viewport, not the tiles in its bounding box.
- Far tiles use coarser zooms, chosen from their size on screen, so that a far tile is drawn at most √2 times its native size, as at the center of an unpitched map today. No tile is finer than today's tile zoom, so near tiles are as today. Applications that need sharp near ground on a pitched map can use vector tiles.
- The pan and keep buffers are tiles around the visible ground, at each tile's zoom.
- Tiles load in order of their distance on screen from the viewport center.
- An unrotated, unpitched map loads, draws and prunes the same tiles as before. A rotated, unpitched map no longer loads tiles beyond the buffer in the corners of the bounding box.
- No public API changes: the tile range, the tile image manager and their helpers are internal.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-map-pitch`: the tile layer covers the visible ground with tiles whose zoom follows from their size on screen; this replaces the single tile zoom that the requirement "Visible bounds and tiles of the visible ground" describes.

## Impact

- The fork: `TileLayer`, `TileRangeCalculator`, `TileImageManager`, `TileImageView`, the tile range and tile bounds classes, the `MapOptions.maxPitch` documentation about tile cost, and tests.
- A harness app outside the fork measures tile requests, bytes, decoded image memory and the time until the visible tiles have loaded, before and after the change, on the Pixel.
- mapigrade: no change. It draws its base map with MapLibre Native and doesn't use `TileLayer`.
