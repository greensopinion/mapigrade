## Context

`docs/map-pitch-concept.md` section 8 (change 4) and decision 20 record the decisions this design implements; the requirements are in `specs/flutter-map-pitch/spec.md`. File references are to the fork's branch `map-pitch` at `66b72e5` (change 3).

Relevant current state:

- `lib/src/map/camera/camera_fit.dart`: `FitBounds` and `FitCoordinates` compute a scale from the size of the projected bounds or coordinates rotated by the camera's rotation, and the center from their rotated bounding box plus a padding offset. `FitInsideBounds` fits the rotated viewport inside the projected bounds with `_rectInRotRectScale`. None of them reads the pitch.
- `lib/src/map/camera/camera_constraint.dart`: `ContainCamera` and `ContainCameraLatitude` clamp the center so that a box of `camera.size / 2` on each side of it stays inside the bounds. At pitch 0, `MapCamera.size` is `calculateRotatedSize(rotation, nonRotatedSize)`; when pitched, change 1 made it the size of the visible ground's bounding box, which isn't centered on the center. `ContainCameraCenter` clamps only the center.
- `MapCamera` (change 1) has the world-to-screen transform, `latLngToScreenOffset`, the internal `groundOffsetFromCenter` (the ground offset, in projected pixels at the camera zoom, under a screen position, or null above the horizon), and `withPosition` and `withPitch`.
- Moving the center translates the visible ground in projected pixel space without changing its shape, and the ground offsets under fixed screen positions don't depend on the zoom when measured in projected pixels at that zoom.

## Goals / Non-Goals

**Goals:**

- Keep the existing code path at pitch 0, so that the existing fit and constraint tests are the compatibility check.

**Non-Goals:**

- Constraining the visible ground when pitched (decision 20: the constraints follow GL JS and ignore pitch).
- Changing the pitch or the rotation in a fit.
- `ContainCameraCenter`, which is correct at every pitch.

## Decisions

### 1. Fitting bounds and coordinates iterates on screen positions

At pitch 0 the existing code runs. When pitched, `FitBounds` and `FitCoordinates` fit a list of points: the four corners of the bounds, or the coordinates. The target is the viewport reduced by the padding, `R`.

1. Start from the existing fit of the same points to the camera at pitch 0, with the camera's pitch then restored.
2. Convert the points to screen positions, and take their bounding rectangle `S`.
3. Move the center by the ground shift that takes the ground under `S.center` to `R.center` (`groundOffsetFromCenter` at both positions), then change the zoom by `log2(min(R.width / S.width, R.height / S.height))`. If a point is behind the camera, change the zoom by −1 instead.
4. Repeat from 2 until the zoom changes by less than 1e-4, at most 20 times.
5. Apply the minimum and maximum zoom and `forceIntegerZoomLevel` (floor), then repeat the centering step of 3 at the final zoom until `S.center` is within 0.1 px of `R.center`, at most 20 times.

The perspective transform is projective, so straight lines on the ground stay straight on the screen, and the projected bounds are a convex quadrilateral that lies inside `R` when its four corners do. Zooming out about the center point moves every screen position toward the center of the viewport along its line from that center, so the floor in step 5 keeps the points inside `R`.

A point behind the camera has no screen position. The step 1 start contains the points in the unpitched view, which at pitch 60 is within 0.5 H of the center point, in front of the camera (concept section 4: ground more than 1.73 H before the center point is behind the camera). If an iteration produces such a point anyway, the fit zooms out by 1 and continues.

Alternative: a closed form. Rejected: with perspective, the screen extent of the points depends on the center as well as the zoom, so there is none for an arbitrary set of points.

Alternative: one step, as MapLibre Native's `cameraForLatLngs` (`src/mln/map/map.cpp`) does: it projects the points with the current camera, sets the zoom from their screen extent and the center to the coordinate under the middle of that extent. Rejected: when pitched, the result depends on the camera it starts from and can leave points outside the viewport or the fit loose; repeating the same step until it converges makes the result exact.

Alternative: bisection on the zoom with the center found for each zoom. Rejected: it needs more conversions for the same accuracy, because step 3 already estimates the zoom change from the current scale.

### 2. Fitting inside bounds is closed form when pitched

The coordinates under the corners of the padded viewport, as ground offsets from the center in projected pixels at the camera zoom, are the same at every zoom. Their bounding box `F` has a size and an offset `o` of its center from the center point. The bounds, projected at zoom `z`, are `B0 · 2^(z − z0)`. A polygon lies inside an axis-aligned rectangle exactly when its bounding box does, so:

- zoom `z = z0 + log2(max(F.width / B0.width, F.height / B0.height))`, then `forceIntegerZoomLevel` (ceil, as now) and the zoom limits;
- center: the projected center of the bounds at `z` minus `o`.

At pitch 0 the existing code, with `_rectInRotRectScale`, runs unchanged.

### 3. The contain constraints use the unpitched box

`ContainCamera` and `ContainCameraLatitude` replace `camera.size` with `MapCamera.calculateRotatedSize(camera.rotation, camera.nonRotatedSize)`, which is the same value at pitch 0. They then never return null because of the pitch, and the center they compute doesn't depend on the pitch.

Alternative: keep the visible ground's bounding box inside the bounds. Rejected in the concept exploration (decision 20): at 60° the visible ground is about 2.5 W × 3 H, so the constraint would refuse pitch changes whenever the bounds are smaller than that, and MapLibre GL JS's `maxBounds` constraint ignores pitch.

### 4. Documentation

`MapOptions.maxPitch` currently says that `CameraFit` and `CameraConstraint` compute as if the map were not pitched. It changes to: fits project at the current pitch, and the contain constraints ignore pitch, so ground beyond their bounds can be visible toward the far edge. `CameraConstraint.contain` and `containLatitude` state the same.

### 5. Verification approach

- Unit tests with `MapCamera` instances, without widgets: the spec scenarios at pitch 45 and 60 and rotation 30, checking screen positions with `latLngToScreenOffset` and the coordinates under the viewport corners with `screenOffsetToLatLng`.
- A test that each fit at pitch 60 is tight: at least one point within 1 px of the edge of `R`, or, for inside bounds, one ground corner within 1 projected px of the bounds.
- Constraint tests: a pitch change inside the bounds is accepted with the center unchanged, and the constrained center at pitch 60 equals the one at pitch 0.
- The existing fit and constraint tests run unchanged at pitch 0.

## Risks / Trade-offs

- [The iteration may converge slowly for points spread far toward the horizon] → At most 20 iterations; at pitch up to 60° the ratio of the largest to the smallest scale on screen is below 4 (concept section 4), and tests at pitch 60 check the result.
- [Ground beyond the contain bounds is visible when pitched] → The same as MapLibre GL JS; documented on `maxPitch` and on the constraints.
- [A fit to a single coordinate or to bounds of zero size has a zero-size `S`] → The existing pitch-0 code handles these cases with its scale calculation; when pitched, a zero extent keeps the zoom from step 1 and only centers.

## Migration Plan

- Implement on the fork's local branch `map-pitch`, after `66b72e5`; no push without explicit approval.
- mapigrade needs no change.
- Rollback: revert the commit on the fork's branch.
