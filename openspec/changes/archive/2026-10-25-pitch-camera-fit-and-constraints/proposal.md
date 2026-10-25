## Why

On a pitched `flutter_map` map, camera fits and the contain constraints compute the wrong camera. Fitting bounds or coordinates chooses a zoom and center from the unpitched view, so the fitted area doesn't lie in the viewport. The contain constraints keep a box of `MapCamera.size` centered on the center inside their bounds, but when pitched that box is the visible ground's bounding box, which isn't centered on the center. This is change 4 in `docs/map-pitch-concept.md`.

## What Changes

This change is implemented in our `flutter_map` fork (greensopinion/flutter_map), on the branch `map-pitch`. It changes nothing in mapigrade.

- Fitting bounds and fitting coordinates choose a zoom and center so that the bounds or the coordinates, projected at the current pitch and rotation, lie inside the padded viewport.
- Fitting inside bounds chooses a zoom and center so that the ground visible in the padded viewport lies inside the bounds.
- The contain and contain-latitude constraints keep the same box inside their bounds at every pitch as at pitch 0: the viewport at the center's scale, rotated. They ignore pitch, as MapLibre GL JS's bounds constraint does, so they never refuse a pitch change, and ground beyond the bounds can be visible toward the far edge of a pitched map.
- At pitch 0, every camera fit and constraint computes the same camera as before.
- Only the built-in fits and constraints change; the camera fit and camera constraint classes gain no abstract members.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-map-pitch`: adds pitched camera fits and the behavior of the contain constraints when pitched.

## Impact

- The fork: `FitBounds`, `FitInsideBounds`, `FitCoordinates`, `ContainCamera` and `ContainCameraLatitude`, the `MapOptions.maxPitch` documentation, which says that fits and constraints compute as if unpitched, and tests.
- No public API changes.
- mapigrade: no change. The demo's flyover fits coordinates only with an unpitched camera, to compute the zoom between stages, so its result doesn't change.
