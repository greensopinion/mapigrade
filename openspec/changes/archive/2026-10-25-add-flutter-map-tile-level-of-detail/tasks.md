## 1. Measurement baseline

- [x] 1.1 Write the local tile server (generated PNG tiles of a realistic size, a fixed delay per request) and the harness app outside the fork (design decision 7); verify on the Mac that it records requests, bytes, `imageCache.currentSizeBytes` and the time until the visible tiles have loaded for one camera
- [x] 1.2 Run the harness on the Pixel with the fork at `a581ef2`, at pitch 0, 45 and 60 and rotation 0 and 45, with retina mode off and on; record the results in design.md, and terminate the harness on the Pixel afterwards

## 2. Tile cover

- [x] 2.1 Add `TileCover` with `contains`, `expand` and per-zoom validity (design decision 1); verify unit tests, including zoom comparison, wrapping across the antimeridian, and that `expand` of a single-zoom cover equals `DiscreteTileRange.expand`
- [x] 2.2 Add `TileCoverCalculator`, and the expansion of its covers outside the visible ground (design decisions 2 and 5); verify unit tests that at pitch 0 and rotation 0 the cover equals today's `TileRangeCalculator` range for several cameras, zooms and tile sizes, that at rotation 45 it contains only tiles that the viewport touches, that at pitch 60 every tile coarser than the tile zoom is drawn at most √2 at its nearest point and no tile is finer than the tile zoom, that the native zoom limits apply, that the far edge across the antimeridian is covered on both sides, and that the buffer adds no tile that touches the visible ground

## 3. Tile layer

- [x] 3.1 Replace the range with the cover in `TileImageManager` and `TileImageView`, with the buffers at today's call sites (design decision 5); verify that the existing tile layer tests, including `tile_image_view_test.dart`, pass unchanged
- [x] 3.2 Use `TileCoverCalculator` in `TileLayer` for loading, drawing and pruning, including the overridden center and zoom of update events, and draw tiles coarsest first (design decision 3); verify widget tests for the spec scenarios Coarser tiles far away, No finer tiles near the camera, Maximum native zoom, Rotated map, Pitched and rotated map, and that every position in the viewport shows a tile at pitch 60 while tiles load
- [x] 3.3 Sort the tiles to load by their center's distance on screen from the viewport center (design decision 4); verify a widget test for the spec scenario Pitched load order

## 4. Documentation and integration

- [x] 4.1 Update the `MapOptions.maxPitch`, `TileLayer.panBuffer` and `TileLayer.keepBuffer` documentation (design decision 6); verify `dart doc` reports no new warnings
- [x] 4.2 Run `flutter analyze` and `flutter test` on the fork's branch; verify both pass with no existing test changed
- [x] 4.3 Run the harness on the Pixel with the change, with the same cameras as 1.2, and record the results and the frame time at 60° next to the baseline in design.md; terminate the harness afterwards
- [x] 4.4 Ask the user to check the example app's Pitch page on the Pixel and the iPhone while panning, rotating and pitching, for gaps and for tiles switching zoom visibly; record the result in design.md
- [x] 4.5 Remove an aborted tile load from the image cache when its abort trigger fires, so that a tile with the same URL doesn't show the aborted load's transparent image (found in 4.4); verify a provider test that fails without the fix
