## Context

`docs/map-pitch-concept.md` section 8 (change 5) and decisions 21 to 25 record the decisions this design implements; the requirements are in `specs/flutter-map-pitch/spec.md`. The fork is checked out at `~/git/flutter_map`, on the local branch `map-pitch`, which isn't pushed; this change starts from `a581ef2` (change 4), and file references are to that commit.

Relevant current state, in `lib/src/layer/tile_layer/`:

- `TileLayer` chooses one tile zoom, `round(zoom)` clamped to the native zoom limits (`_clampToNativeZoom`). `TileRangeCalculator` turns the camera into a `DiscreteTileRange`, a rectangle of tiles at that zoom: today's centered rectangle at pitch 0, and the bounding box of the visible ground when pitched (change 1).
- The range is used for loading (`_loadTiles`: `createMissingTiles` over the range expanded by `panBuffer`, sorted by the distance of each tile's top-left corner to the range's center), drawing (`TileImageView.renderTiles`) and pruning and evicting (`TileImageView.staleTiles` and the error-tile lists, with a keep range expanded by `panBuffer + keepBuffer` or by the larger of the two).
- `TileImageView` draws ancestors (up to 5 levels up) or children (up to 2 levels down) of a tile in the range that isn't ready, to fill the gap. `Tile` positions a tile of any zoom with `scaledTileDimension(map.zoom, z)`. `build` sorts tiles by the distance of their zoom from the target zoom, so target-zoom tiles are drawn on top.
- `DiscreteTileRange.contains` compares x and y only, not the zoom, so a tile at another zoom counts as inside the range whenever its numbers fall inside it.
- `TileUpdateEvent` can override the center and zoom used for loading.
- `DiscreteTileRange`, `TileRangeCalculator`, `TileImageManager`, `TileImageView` and the tile bounds classes aren't exported from `flutter_map.dart`.

## Goals / Non-Goals

**Goals:**

- One code path for every map, which at pitch 0 without rotation computes today's tiles (decision 22).
- Keep the gap-filling and pruning rules; change only the set of tiles they apply to.

**Non-Goals:**

- Changing Flutter's image cache size, unless the measurement in design decision 7 shows the need.
- Hysteresis in the zoom rule (decision 24).
- A horizon, or pitch above 60° (change 6).

## Decisions

### 1. A tile cover replaces the tile range

An internal `TileCover` is a set of `TileCoordinates` at any zoom, with:

- `contains(coordinates)`, which compares the zoom as well as x and y, and wraps x at the coordinates' own zoom when the CRS repeats the world horizontally;
- `expand(count)`, which adds every tile within `count` tiles of a tile in the set, at that tile's zoom (decision 23), so `expand(n)` of a set at one zoom is today's `DiscreteTileRange.expand(n)` restricted to the same tiles; a cover from `TileCoverCalculator` adds only the tiles that don't intersect the visible ground (decision 5);
- iteration, and validity per tile through `TileBounds.atZoom(z)` for each zoom in the set.

`TileImageManager` and `TileImageView` take covers where they take ranges today, with the same buffers at the same call sites. `TileCover` is an interface that `DiscreteTileRange` implements as a cover at one zoom, so the existing `TileImageView` tests, which pass ranges, run unchanged. Comparing the zoom in `contains` differs from today only for tiles at another zoom whose x and y happen to fall in the range; those are already handled by the ancestor and children rules, and the existing `TileImageView` tests check it.

Alternative: keep `DiscreteTileRange` and pass one range per zoom. Rejected: the buffer ring around tiles of mixed zoom isn't a rectangle at any zoom, and every caller would loop over zooms.

### 2. The cover follows the visible ground

`TileCoverCalculator` replaces `TileRangeCalculator`. From a camera, with the center and zoom of the update event if overridden:

1. The visible ground is the polygon of the ground points under the four viewport corners. At pitch 0 it is the rotated viewport rectangle, computed from the center projected at the tile zoom and floored, as today's rectangle is, so that at rotation 0 it is exactly today's pixel bounds.
2. Start with the tiles that intersect the polygon at the coarsest zoom that rule 3 can give: the rule applied to the smallest scale in the polygon, at its far corners.
3. For each tile, clip the polygon to the tile and take the largest scale at the clipped polygon's vertices, which is at the tile's point nearest the camera, because the scale changes monotonically along the view direction. The tile's zoom is `round(zoom + log2(scale))`, clamped to the range from the minimum native zoom to the tile zoom, `round(zoom)` within the native zoom limits (decision 21). If that is finer than the tile, replace the tile by its children that intersect the polygon and repeat for each.
4. Intersection is a convex polygon against a square: a separating-axis test, with the half-open edges of `DiscreteTileRange.fromPixelBounds`, so that a tile touching the polygon only at its edge is treated as today.

At pitch 0 the scale is 1 everywhere, so every tile is at `round(zoom)` clamped, today's tile zoom, and at rotation 0 the cover is today's range.

The zoom isn't finer than the tile zoom, so near tiles are as today, and on a pitched map they can be drawn at more than √2 times their native size, as today. We first chose the zoom without that limit, so that every tile was drawn at most √2 times its native size. The tile counts of task 2.2's calculator, with a pan buffer of 1, on a 393 × 851 viewport without retina mode, showed that this loads more tiles than today at a zoom 0.45 above an integer, because the tile that contains the center has its nearest point below the center and becomes one level finer:

| Zoom, pitch, rotation | Today | Without limit, rings | Without limit, buffer outside the visible ground | With limit, buffer outside the visible ground |
|---|---|---|---|---|
| 14.0, 60, 45 | 132 | 95 | 77 | 64 |
| 14.0, 60, 0 | 91 | 83 | 69 | 58 |
| 14.45, 60, 0 | 60 | 75 | 65 | 48 |
| 14.45, 45, 0 | 35 | 49 | 44 | 32 |

With the limit the cover has no more tiles than today for every camera. Applications that need sharp near ground on a pitched map can use vector tiles.

Where a tile needs a finer zoom in part of it, all four children replace it, so a child far from that part can be drawn at 1/√2 or fewer screen pixels per tile pixel; a quadtree of tiles can't avoid this.

The scale at a ground point is the camera distance divided by the point's depth along the view direction, the factor that the world-to-screen transform of change 1 applies.

Alternative: MapLibre GL JS's approach of a desired zoom from the distance between the camera and the tile. Rejected: the screen scale is what decides how a tile is drawn, and it gives today's zoom at the center by construction.

### 3. Drawing order: coarser below finer

`build` sorts tiles by zoom, coarsest first, so a tile that fills a gap is never drawn over a finer tile that is ready. With mixed zooms, today's order by distance from the target zoom would draw a tile at the target zoom, filling a gap near the camera, over ready tiles one level finer. For an unpitched map this differs from today only while tiles load, when a filler one level coarser and a filler two levels finer overlap: today the coarser is drawn on top.

### 4. Load order

`_loadTiles` (decision 25) sorts the tiles to load by the distance on screen from the viewport center to each tile's center, converted with `latLngToScreenOffset` of the tile center at the tile's zoom. At pitch 0 this is close to today's order, which uses each tile's top-left corner and the center of the integer tile range; they can differ for tiles at almost the same distance.

### 5. Buffers

`panBuffer` and `keepBuffer` keep their meaning in tiles and apply through `TileCover.expand` at each tile's zoom: the load set is `cover.expand(panBuffer)`, and the keep sets are `cover.expand(...)` with today's sums at today's call sites. The expansion adds only tiles that don't intersect the visible ground: a neighbor that intersects it is covered by tiles at another zoom, and on a pitched map rings around the finer tiles overlap the coarser covering tiles (table in decision 2). At one zoom, every neighbor outside the cover is outside the visible ground, so an unpitched map's buffer is today's.

### 6. Documentation

The `MapOptions.maxPitch` item about the tile layer loading up to 7.5 times as many tiles at 60° changes to state that far ground uses coarser tiles. `TileLayer.panBuffer` and `keepBuffer` state that the buffers surround the visible ground, at each tile's zoom.

### 7. Verification approach

- Unit tests of `TileCoverCalculator`: at pitch 0 and rotation 0 the cover equals today's range for a set of cameras and tile sizes; at rotation 45 it excludes the bounding box's corners; at pitch 60 every tile satisfies the zoom rule at its nearest point; the native zoom limits; the antimeridian.
- Unit tests of `TileCover.expand` and `contains`, including zoom comparison and wrapping.
- The existing tile layer tests run unchanged.
- Widget tests for the spec scenarios: far tiles coarser, near tiles finer at a zoom 0.45 above an integer, load order at pitch 60, and the drawing order.
- Measurement, with the same harness and the same cameras before and after the change, results recorded in this design:
  - Location: a Flutter app in `~/git/tile-lod-harness`, outside both repositories and not committed, which depends on the fork through a path dependency on `~/git/flutter_map`. The baseline runs while the fork's working tree is at `a581ef2`, before any change in this design.
  - Tiles: a local HTTP server on the Mac, reached from the Pixel through `adb reverse`, generates a PNG tile of about 25 KB for each request, labelled with its z/x/y, and answers after a fixed delay of 50 ms, so that no public tile server is used and runs are repeatable. HTTP caching is disabled in the server's responses, and the harness's tile provider uses no persistent cache.
  - Cameras: center 45.52, −122.68 (Portland), zooms 14.0 and 14.45, pitch 0, 45 and 60, rotation 0 and 45, each with `retinaMode` off and on, in a full-screen map on the Pixel 4a (5G).
  - Each run starts from an empty image cache, jumps to the camera with `MapController.moveAndRotate` and `pitch`, and records: the number of tile requests, the bytes transferred, `imageCache.currentSizeBytes`, and the time from the camera change until the last tile request completes, with no new request for 1 s. This criterion works for both versions, because it doesn't depend on the tile layer's internals.
  - Android build: `flutter run` of the fork's example app fails on the development Mac, because Flutter runs Gradle with Java 25 and the example uses Gradle 8.14. A harness made with the current `flutter create` uses a newer Gradle; if it doesn't, build it with its Gradle wrapper and `JAVA_HOME` set to Java 21 (`/Library/Java/JavaVirtualMachines/amazon-corretto-21.jdk/Contents/Home`), and install it with `adb install`.

## Risks / Trade-offs

- [A gap shows while the cover changes level under a moving camera] → Gap-filling applies per tile, as when zooming today; the widget tests at pitch 60 check that every position shows a tile, and the device check looks for it.
- [Cover computation per frame costs build time] → The quadtree touches tens of tiles; the frame time on the Pixel at 60° is measured against change 1's numbers.
- [Comparing the zoom in `contains` changes which off-zoom tiles are pruned] → Off-zoom tiles are kept only by the ancestor and children rules, as intended; the existing `TileImageView` tests run unchanged.
- [Image cache pressure with retina tiles] → Fewer tiles reduce it; the measurement reads the decoded memory and decides whether the cache needs attention.

## Migration Plan

- Implement on the fork's local branch `map-pitch`, after `a581ef2`; no push without explicit approval.
- mapigrade needs no change.
- Rollback: revert the commit on the fork's branch.

## Measurements

Harness: `~/git/tile-lod-harness`, as described in decision 7, on the Pixel 4a (5G), in profile mode. Each row is one run. Requests are the tile requests that the camera change started; decoded is `imageCache.currentSizeBytes`; load is the time from the camera change until the last tile request completed. The frame times are of 6 s of rotation from 0° to 90° at pitch 60 and zoom 14.45, without retina mode, after the tiles of the start camera had loaded.

### Results, 2026-10-25

Each row is one run of the baseline, the fork at `a581ef2` from a separate worktree, then one run of the change, on the same day with the same harness. A first baseline run, before the change, used a harness that waited forever for requests that were aborted before their body was read, and that recorded the first camera after the app started (24 requests where later runs made 30 for the same camera). We fixed the harness and ran both versions again; the first run's numbers are not used.

| Retina | Zoom | Pitch | Rotation | Requests | Decoded MB | Load ms |
|---|---|---|---|---|---|---|
| off | 14.0 | 0 | 0 | 30 → 30 | 7.9 → 7.9 | 594 → 593 |
| off | 14.0 | 0 | 45 | 42 → 37 | 11.0 → 9.7 | 822 → 1162 |
| off | 14.0 | 45 | 0 | 40 → 40 | 10.5 → 10.5 | 759 → 794 |
| off | 14.0 | 45 | 45 | 64 → 58 | 16.8 → 15.2 | 1378 → 1398 |
| off | 14.0 | 60 | 0 | 91 → 58 | 23.9 → 15.2 | 1645 → 1143 |
| off | 14.0 | 60 | 45 | 146 → 82 | 38.3 → 21.2 | 2552 → 1518 |
| off | 14.45 | 0 | 0 | 24 → 24 | 6.3 → 6.3 | 502 → 497 |
| off | 14.45 | 0 | 45 | 30 → 28 | 7.9 → 7.3 | 607 → 569 |
| off | 14.45 | 45 | 0 | 35 → 33 | 9.2 → 8.7 | 690 → 659 |
| off | 14.45 | 45 | 45 | 42 → 38 | 11.0 → 10.0 | 817 → 767 |
| off | 14.45 | 60 | 0 | 60 → 48 | 15.7 → 12.6 | 1143 → 911 |
| off | 14.45 | 60 | 45 | 100 → 75 | 26.2 → 19.1 | 2091 → 1363 |
| on | 14.0 | 0 | 0 | 60 → 60 | 15.7 → 15.7 | 1109 → 1129 |
| on | 14.0 | 0 | 45 | 100 → 82 | 26.2 → 21.5 | 1833 → 1523 |
| on | 14.0 | 45 | 0 | 104 → 86 | 27.3 → 22.5 | 1877 → 1601 |
| on | 14.0 | 45 | 45 | 169 → 132 | 44.3 → 34.1 | 3014 → 2370 |
| on | 14.0 | 60 | 0 | 253 → 124 | 66.3 → 32.5 | 4305 → 2335 |
| on | 14.0 | 60 | 45 | 453 → 189 | 104.9 → 45.9 | 7586 → 3099 |
| on | 14.45 | 0 | 0 | 40 → 40 | 10.5 → 10.5 | 769 → 798 |
| on | 14.45 | 0 | 45 | 64 → 53 | 16.8 → 13.9 | 1207 → 1026 |
| on | 14.45 | 45 | 0 | 77 → 67 | 20.2 → 17.6 | 1434 → 1309 |
| on | 14.45 | 45 | 45 | 107 → 91 | 28.0 → 23.6 | 2160 → 1714 |
| on | 14.45 | 60 | 0 | 162 → 101 | 42.5 → 26.5 | 3003 → 1884 |
| on | 14.45 | 60 | 45 | 274 → 166 | 71.8 → 40.4 | 7926 → 2821 |

Frame times while rotating at pitch 60, baseline → change: build 3.0 → 7.3 ms median and 3.4 → 8.2 ms 90th percentile; raster 3.1 → 2.9 ms median and 3.2 → 3.1 ms 90th percentile; 362 and 361 frames; 49 and 36 tile requests during the rotation.

- Unpitched, unrotated maps make the same requests as before. At 60° the change makes 36% to 58% fewer requests, with as much less decoded memory, and the visible tiles load 20% to 64% sooner.
- In the baseline at 60°, rotation 45 and retina mode, the decoded tiles filled Flutter's default image cache of 100 MB.
- Each row is a single run; for example, the change's 1162 ms at zoom 14.0, pitch 0, rotation 45 is slower than the baseline's 822 ms with fewer requests, which we attribute to variation between runs.
- The build time per frame while rotating at 60° increased by about 4.3 ms, which is the cost of computing the cover, its buffer and its keep set on every camera change. Frames still complete within a 16.7 ms frame budget at 60 Hz.

### Device check, 2026-10-25

The example app's Pitch page on the iPhone 13, in profile mode: panning, rotating and pitching showed no gaps and no visible zoom switches, except one tile that stayed blank at one zoom and returned blank whenever the map came back to that zoom. Its cause was in `NetworkTileImageProvider`: an aborted load completes with a transparent image, and the provider removed it from Flutter's image cache only after the abort error arrived, so a tile for the same URL created in between shared the load and showed the transparent image. Tiles at the boundary between two zooms leave and re-enter the cover with small zoom changes (no hysteresis, decision 24), which made this frequent. The provider now removes a load from the image cache when its abort trigger fires before the image has loaded; `network_image_provider_abort_test.dart` covers it. After the fix, the check on the iPhone 13 showed no blank tiles. The Pixel was not checked on the Pitch page.
