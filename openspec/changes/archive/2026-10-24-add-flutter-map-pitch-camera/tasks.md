## 1. Fork branch and spike

- [x] 1.1 Fetch fleaflet's `master` into `~/git/flutter_map` and create the local branch `map-pitch` from `upstream/master` (no push without explicit approval); create the local branch `map-pitch` in mapigrade; verify `flutter test` passes on the fork branch before any change
- [x] 1.2 On the start commit, add geometry assertions at pitch 0 for markers, rotated markers (`rotate` true and false, map rotation 30), and polygon label positions for `drawLabelsLast` true and false, and generate golden images of the same scenes kept outside the branch (untracked and listed in `.git/info/exclude`); verify both pass before any other change
- [x] 1.3 Add a compile-only test with an exhaustive `switch` on `MapEventSource` and a custom `CameraConstraint` subclass; verify `flutter analyze` and `flutter test` pass on the start commit
- [x] 1.4 Spike: a test app with a `CustomPaint` under a perspective `Transform` at 60°, with a hit-testable painter and a `GestureDetector` child; verify on the Mac (Impeller), on the Pixel and in Chrome that taps resolve to the expected canvas positions, and on the Mac and the Pixel that the far edge paints without visible defects (painting in Chrome is checked in 6.1); record the result in design.md

## 2. Camera

- [x] 2.1 Generate reference screen positions with the FFI's `mln_map_pixel_for_lat_lng` and `mln_map_lat_lng_for_pixel` for the cameras in design decision 8 (MapLibre zoom = `flutter_map` zoom − 1) and check them in as test data; verify the generator's output for pitch 0 matches the fork's current `latLngToScreenOffset`
- [x] 2.2 Add `pitch`, `withPitch` and the world-to-screen transform to `MapCamera`; verify unit tests against the reference positions pass within 0.01 px
- [x] 2.3 Use the transform in `latLngToScreenOffset` and `screenOffsetToLatLng`, and add the nullable conversion; verify round-trip, center-point and above-the-horizon tests pass
- [x] 2.4 Compute `pixelBounds`, `size`, `pixelOrigin`, `getNewPixelOrigin` and `pixelBoundsAtZoom` from the footprint; verify tests that the viewport corners' coordinates are within `visibleBounds` at pitch 60 and that pitch 0 values are unchanged
- [x] 2.5 Make `offsetToCrs` and `focusedZoomCenter` ray-cast; verify unit tests, with cameras constructed with pitch 50, that the coordinate under a focal point near the top of the viewport stays within 0.5 px after `focusedZoomCenter`

## 3. Options, controller and events

- [x] 3.1 Add `MapOptions.initialPitch` and `MapOptions.maxPitch` with the limits from the spec; verify tests for the default, clamping and the 60° limit
- [x] 3.2 Add `MapController.pitch` to the interface and `MapControllerImpl`, and `MapEventPitch` with source `MapEventSource.mapController`; verify tests for a change and for an unchanged pitch, and that `MapEventSource` has no new values

## 4. Gestures and controller offsets

- [x] 4.1 Ray-cast the offset in `MapController.move` and `MapController.rotateAroundPoint`; verify the spec's move-with-offset and rotate-around-a-point tests at pitch 60 and 45, and that pitch 0 results are unchanged
- [x] 4.2 Anchor drags on the ground point under the pointer and animate flings with the ground velocity; verify a widget test that a drag from near the top to near the bottom of the viewport at pitch 60 keeps the start coordinate within 0.5 px of the pointer, a fling direction test, and that pitch 0 drag and fling tests are unchanged
- [x] 4.3 Verify widget tests at pitch 50 for the scroll-wheel zoom and two-finger rotate scenarios in the spec: for scroll-wheel zoom the coordinate under the cursor stays within 0.5 px; for the rotate gesture, whose unpitched form already leaves a drift proportional to the rotation per frame (0.49 px at 3 degrees per frame), the drift in projected pixels matches the unpitched gesture's within 0.05 px

## 5. Layers

- [x] 5.1 Apply the full transform in `MobileLayerTransformer`; verify a widget test that a polyline vertex is drawn at its projected screen position at pitch 50 and rotation 20
- [x] 5.2 Compute the tile range from `pixelBoundsAtZoom`; verify a test that the tile under the top edge of the viewport is loaded at pitch 60, and a test that at pitch 60 and rotation 45 a grid of screen positions across the viewport, including its corners, all fall inside the screen quadrilaterals of loaded tiles
- [x] 5.3 Add the billboard transformer and move the marker layer to it; verify widget tests for marker position, size and rotation at pitch 60
- [x] 5.4 Draw polygon labels with a screen-space painter under the billboard transformer; verify a widget test that a label is upright and unscaled at its projected label point at pitch 45
- [x] 5.5 Verify a test at pitch 60, in a CRS that repeats the world horizontally, with the far edge across the antimeridian: the tiles on both sides are loaded and cover the viewport (visible bounds stay limited to ±180° longitude, as for an unpitched map)
- [x] 5.6 Verify hit testing: widget tests that a tap's coordinate and a polygon hit near the top of the viewport are correct at pitch 60

## 6. Example, documentation and integration

- [x] 6.1 Add a Pitch page to the example app with pitch and rotation sliders, a tile layer, polygons, polylines and markers; verify visually on the Mac, iPhone, Pixel and in Chrome at pitch 0, 30 and 60, and record the frame time at 60° on the Pixel (release build) in design.md
- [x] 6.2 Document `maxPitch`, the billboard transformer, the unpitched behavior of `CameraFit` and `CameraConstraint`, and the migration for plugins that compute screen positions; verify `dart doc` reports no new warnings
- [x] 6.3 Run `flutter analyze` and `flutter test` on the branch and verify both pass with no existing test changed, and that the geometry assertions and local golden images from 1.2 and the compile-only test from 1.3 pass unchanged
