## Context

`docs/map-pitch-concept.md` describes the camera model (section 3), the footprint (section 4), the layer kinds (section 5) and zoom when pitched (section 6), and records the decisions this design depends on. This design covers how change 1 implements them in the fork. File references are to fleaflet's `master` (8.4.0-dev.1), which the fork branch starts from.

Relevant current state:

- `MapCamera` has `center`, `zoom`, `rotation` and `nonRotatedSize`. `size` is the bounding box of the rotated viewport, `pixelOrigin` is `project(center) - size / 2`, and `pixelBounds` is the rectangle of `size` centered on the projected center. `visibleBounds` unprojects the corners of `pixelBounds`.
- Painters and hit testing convert between canvas positions and coordinates through `pixelOrigin`.
- `MobileLayerTransformer` places its child in an `OverflowBox` of `size`, centered in the viewport, and applies `Transform.rotate`.
- The tile range calculator builds its own rectangle of `size` centered on the projected center.
- The marker layer culls with `pixelBounds` and counter-rotates markers. Polygon labels are drawn in the polygon painter, with `canvas.rotate(-rotationRad)`.
- `latLngToScreenOffset`, `screenOffsetToLatLng`, `offsetToCrs` and `focusedZoomCenter` undo the rotation in 2D. The gesture code converts focal points through `offsetToCrs` and `focusedZoomCenter`.

## Goals / Non-Goals

**Goals:**

- One world-to-screen transform in `MapCamera` that all projections, layers and hit testing use.
- Keep `pixelOrigin`, `size` and `pixelBounds` consistent with each other, so that layers that use them work pitched without changes.
- Make no observable change at pitch 0.

**Non-Goals:**

- Pitch gesture and horizon handling for gestures (change 3).
- Pitched `CameraFit` and `CameraConstraint` (change 4). In this change they compute as if unpitched.
- Tile level of detail, a horizon, or pitch above 60°.
- Changes in mapigrade (change 2).

## Decisions

### 1. The transform lives in `MapCamera`

`MapCamera` gains `pitch` (degrees, default 0 in the constructor so existing callers compile), `withPitch`, and a lazily computed `Matrix4` from projected map pixels at the camera zoom to viewport positions:

```
T(nonRotatedSize / 2) · P(d) · Rx(pitch) · Rz(rotation) · T(-project(center))
d = 0.5 · nonRotatedSize.height / tan(fov / 2),  fov = 0.6435011087932844
```

`P(d)` sets the matrix entry that divides by `1 - z / d`, so points at z = 0 (the ground at the center point) keep scale 1. The inverse for screen to ground casts the ray from the camera through the screen point and intersects z = 0; when the ray doesn't reach the ground in front of the camera, the result is null.

`latLngToScreenOffset` and `screenOffsetToLatLng` use the transform. `screenOffsetToLatLng` stays non-nullable to avoid a breaking change; above the horizon it returns the coordinate at the maximum ground distance along the ray's bearing. A new nullable method returns null there, and the gesture code uses it. The constants match MapLibre Native's `DEFAULT_FOV` and `getCameraToCenterDistance`.

Alternative: keep the 2D formulas and add pitch as a separate correction, as in #1273. Rejected: two formulas drift apart, and the inverse isn't exact.

### 2. `size`, `pixelOrigin` and `pixelBounds` describe the footprint's bounding box

When pitched, `pixelBounds` is the north-up bounding box, in projected map pixels, of the four ground points under the viewport corners. `size` is its size, and `pixelOrigin` is its top-left corner. At pitch 0 these equal the current values. The invariants `pixelBounds.topLeft == pixelOrigin` and `pixelBounds.size == size` hold at every pitch, so code that paints at `project(p) - pixelOrigin` inside a canvas of `size` keeps working, and `visibleBounds`, which unprojects `pixelBounds`, needs no change.

`getNewPixelOrigin` and `pixelBoundsAtZoom` compute the same box for the given center and zoom. The tile range calculator uses `pixelBoundsAtZoom` scaled to the tile zoom instead of its own centered rectangle.

Alternative: a canvas centered on the center point, large enough for the far edge. Rejected: at 60° it contains ground points behind the camera (concept section 4), which have no valid projection, and it is about 1.6 times larger.

### 3. `MobileLayerTransformer` applies the full transform

The transformer places its child at the top left in an `OverflowBox` of `size` and applies `camera transform · T(pixelOrigin)`, so canvas position `q` reaches the screen at the transform of `q + pixelOrigin`. At pitch 0 this is the same rotation about the viewport center as now. `Transform` keeps `transformHitTests: true`, and hit testing reaches the child through the inverted transform.

### 4. Billboards are placed in screen space

A new public widget, the billboard transformer, fills the viewport (`nonRotatedSize`) with no transform. Its children place themselves at `latLngToScreenOffset` positions. The marker layer moves from `MobileLayerTransformer` to it at every pitch, including 0. Switching only when pitched would change the widget structure when the pitch leaves 0 and discard the markers' `State`. At pitch 0 the result is the same pixels as now:

- `rotate: true` (stay upright) applies no rotation; `rotate: false` applies `Transform.rotate(rotation)` around the marker's point, which equals rotating the whole layer about the viewport center.
- Culling uses `pixelBounds` as now, then skips markers whose point is above the horizon.

At pitch 0, polygon labels stay in the polygon painter, which keeps the paint order that `drawLabelsLast` selects. When pitched, they're drawn by a second painter under the billboard transformer, at the screen position of each label point and after all polygons. The switch changes only paint order, not widget state, so it can happen in any frame. The label placement calculation stays where it is.

Alternative: keep markers inside `MobileLayerTransformer` and counter-transform each marker. Rejected: it requires the inverse of a perspective transform per marker, and markers near the far edge would be drawn through two transforms that don't cancel exactly.

### 5. Options, controller and events

- `MapOptions.initialPitch` (default 0) and `MapOptions.maxPitch` (default 0, asserted at most 60).
- `MapController.pitch(double degree, {String? id})` is a member of the interface and returns whether the camera changed, as `rotate` does. This breaks a hand-written `implements MapController`; concept decision 15 accepts that, and the upstream PR description states it.
- `MapEventPitch`, a `MapEventWithMove` like `MapEventRotate`, with source `MapEventSource.mapController`. No `MapEventSource` value is added (concept section 11).
- `MapCamera` includes `pitch` in equality, `hashCode` and `toString`.

### 6. Screen offsets in gestures and the controller

Several places convert a screen offset to a ground offset by rotation alone, which is correct only at pitch 0. All of them change to ray-casting, which is exact because moving the center only translates the transform:

- **Focal-point zoom.** `offsetToCrs` and `focusedZoomCenter` cast the ray through the focal point at the current camera, then at the target zoom, and move the center by the difference in projected pixels at the target zoom. When the focal point's ray doesn't reach the ground, `focusedZoomCenter` returns the current center.
- **Rotate gesture.** It already pivots on `offsetToCrs(focal)`. Rotating the center about that ground point and changing the rotation by the same angle leaves the point's offset from the center unchanged after `Rz`, so it keeps its screen position. Only `offsetToCrs` changes.
- **`MapController.move` with `offset` (`moveRaw`).** Cast the ray through `viewport center + offset` from a camera centered on the target center at the target zoom, giving ground point G; the new center is `target − (G − target)` in projected pixels. `flutter_map_location_marker` and similar plugins use this.
- **`MapController.rotateAroundPoint` (`rotateAroundPointRaw`).** The pivot is the ray-cast ground point at the given screen position, as in the rotate gesture.
- **Drag.** At the start of the drag, ray-cast the pointer position to ground point G. On each update, cast the ray through the pointer at the current camera and move the center by G minus the result. This replaces `_rotateOffset` for drags.
- **Fling.** The fling animates the ground velocity at the end of the drag (the ground movement of the last update divided by its duration) instead of the screen velocity rotated by the map rotation.

Unchanged: keyboard pan and keyboard rotation move along screen directions about the center, which is correct when pitched. `MapCamera.rotatePoint` is public and keeps its 2D meaning; its documentation states that it ignores pitch.

### 7. Compatibility

All API changes are additive, following the rules in concept section 11: new parameters are optional with defaults that keep current behavior, no existing signature changes, no `MapEventSource` value is added, and `CameraFit` and `CameraConstraint` gain no abstract members. The only exception is `MapController.pitch` (decision 5).

### 8. Verification approach

- Unit tests in the fork compare the transform with MapLibre Native's positions for a set of cameras: pitch 0, 30, 45 and 60, rotation 0, 30 and 200, two viewport sizes. We generate the reference values once with the FFI's `mln_map_pixel_for_lat_lng` and `mln_map_lat_lng_for_pixel` and check them in.
- Widget tests cover the spec scenarios for layers, markers, hit testing and zoom.
- Pitch-0 compatibility (concept decision 17): geometry assertions in the fork's tests (marker rectangles from `tester.getRect`, label positions) recorded on the branch's start commit before the layer changes. Golden tests of the same scenes, generated on the start commit, check pixels during development; they're kept out of the branch, because upstream has no golden tests and golden images differ between platforms.
- A test that a pitched view whose far edge crosses the antimeridian, in a CRS that repeats the world horizontally, has visible bounds and loaded tiles on both sides.
- Frame time at 60° with a tile layer on the Pixel, recorded in this design for the upstream PR.
- A compile-only test has an exhaustive `switch` on `MapEventSource` and a custom `CameraConstraint` subclass.
- A Pitch page in the example app with sliders for pitch and rotation, for visual checks on Mac, iPhone and Android.
- The test against a rendered MapLibre map is in change 2.

## Risks / Trade-offs

- [Hit testing through a perspective `Transform` may not invert as expected] → The first implementation task is a spike: a pitched `CustomPaint` with hit testing and a `GestureDetector` child, on Impeller, Skia and web (Chrome), before any other work.
- [Perspective painting quality on Impeller, for example aliasing at the far edge] → Checked visually in the spike and on the example page; if needed, a slight minimum on line width at the far edge is a follow-up, not part of this change.
- [Up to 7.5 times as many tiles at 60°] → Accepted until tile level of detail (concept change 5). Frame time at 60° is measured; the example page states the tile cost.
- [`screenOffsetToLatLng` returns a substitute coordinate above the horizon] → Documented; the nullable method is the correct one for new code. At pitch up to 60° no position in the viewport is above the horizon.
- [Plugins that compute screen positions themselves] → Unaffected unless the application raises `maxPitch`; the fork's changelog and migration notes describe the change.
- [`CameraFit` and `CameraConstraint` are wrong when pitched until change 4] → Documented on `maxPitch`.

## Migration Plan

- Create the fork branch `map-pitch` from fleaflet's `master`. The fork's own `master` is behind upstream and isn't used. The branch is pushed to the fork only with explicit approval.
- No migration for applications: all additions have defaults that keep current behavior.
- Rollback: mapigrade doesn't depend on the branch until change 2.
