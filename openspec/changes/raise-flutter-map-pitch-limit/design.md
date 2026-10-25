## Context

`docs/map-pitch-concept.md` (sections 4, 8 and 9) records the pitch design; the requirements are in `specs/`. The fork is at `~/git/flutter_map`, local branch `map-pitch`, which isn't pushed; this change starts after `979748d` (change 5). File references are to that commit.

Relevant current state in the fork:

- `MapOptions.pitchLimit` is 60, and `clampPitch` limits the pitch to it.
- `MapCamera._groundFromCenter` casts a view ray to the ground. Above the horizon it returns null (`groundOffsetFromCenter`, `maybeScreenOffsetToLatLng`), or uses a small divisor that gives a distant point (`screenOffsetToLatLng`, `offsetToCrs`, and the footprint `_visibleGroundFromCenter`, which `size`, `pixelOrigin`, `pixelBounds` and `visibleBounds` use).
- `TileCoverCalculator` takes the ground under the four viewport corners and asserts that each exists.
- `CameraFit._fitPitched` returns the camera unchanged when a corner of the padded viewport is above the horizon.
- `MapInteractiveViewer._groundShift` and the map controller's offset methods do nothing for positions above the horizon; just below it, a drag of 1 px moves the ground by an unbounded distance.
- `MobileLayerTransformer` draws its child, a box of the footprint's size, through the full pitched transform, without a clip.

In mapigrade, `flutter_mapigrade` doesn't set MapLibre Native's bounds, so MapLibre's default maximum pitch of 60° applies, and camera prediction clamps the predicted pitch to `fm.MapOptions.pitchLimit`. The FFI provides `mln_map_set_bounds` with `MLN_BOUND_OPTION_MAX_PITCH`. MapLibre Native's own maximum is 180° (`PITCH_MAX`), and it limits the far plane with a horizon angle of 89.25° (`maxMercatorHorizonAngle`).

## Goals / Non-Goals

**Goals:**

- Pitch up to 85° for `flutter_map` maps that set `maxPitch`, and for mapigrade.
- One definition of where the visible ground ends, used by every computation that today uses the viewport corners or the horizon.
- Nothing changes up to a pitch of about 70.8°, where the far limit enters the viewport.

**Non-Goals:**

- A sky, fog, or a sky color option.
- Pitch above 85°, or terrain.
- Hysteresis or level-of-detail changes in the tile layer beyond using the far limit.

## Decisions

### 1. The pitch limit is 85°

`MapOptions.pitchLimit` becomes 85. MapLibre GL JS allows up to 85° by default; above it the visible ground is a band a few pixels high under a large empty area, and the tile cover's far tiles become very coarse.

We chose 85 (user decision, 2026-10-25). A higher limit, up to MapLibre Native's 180°, would need a sky and handling of a camera that looks up.

### 2. The far limit

The visible ground ends at the ground points whose view ray is 89.25° from straight down, MapLibre Native's horizon angle. On the screen it is the horizontal line at `y = h / 2 − d · tan(89.25° − pitch)` in the viewport before rotation, where `h` is the viewport height and `d` the camera distance. It is in the viewport above a pitch of 89.25° − 18.43° = 70.82°. At 85° on a 393 × 851 viewport it is 331 px from the top, 17 px below the horizon at 314 px; the size on screen of one projected pixel there is about 0.15, so far tiles are about 3 levels coarser than at the center.

`MapCamera` gets an internal `groundViewport`: the viewport before rotation, with its top moved down to the far limit when the far limit is in it. Every computation that today uses the viewport corners uses its corners instead: the footprint (`size`, `pixelOrigin`, `pixelBounds`, `visibleBounds`), the tile cover, and the camera fits. Below 70.82° it is the viewport, so those computations don't change.

We chose 89.25° (user decision, 2026-10-25), as in MapLibre Native, so that mapigrade's MapLibre map and the overlays end at the same place. A smaller angle such as 87° would give fewer, finer far tiles and a larger empty band.

### 3. Above the far limit

Ground layers draw nothing above the far limit, and `FlutterMap`'s background color (`MapOptions.backgroundColor`) shows. `MobileLayerTransformer` clips its child to the visible ground polygon, in the child's coordinates before the transform, so that no point beyond the far limit or behind the camera is drawn; a point behind the camera has a negative perspective divisor and would otherwise be drawn mirrored. Billboard layers keep drawing markers and labels whose point is below the far limit.

We chose no new API (user decision, 2026-10-25); an application that wants a sky sets `backgroundColor`. A `skyColor` option or a gradient can follow in a later change.

### 4. Conversions

`maybeScreenOffsetToLatLng` and `groundOffsetFromCenter` return null above the far limit, not only above the horizon. `screenOffsetToLatLng` and `offsetToCrs` return the coordinate on the far limit directly below the position, instead of a distant point in its direction. Hit testing uses the nullable conversion, so nothing is hit above the far limit.

### 5. Gestures and the movement limit

`MapInteractiveViewer` moves a pointer or focal point that is above the far limit down onto the far limit before casting its ray. A drag, fling, focal-point zoom or rotation then moves the ground by at most what a pointer on the far limit moves it, which is the movement limit that change 6 originally described. The map controller's offset methods keep today's rule: above the far limit, they act as without an offset.

### 6. mapigrade

`flutter_mapigrade` calls `mln_map_set_bounds` with `MLN_BOUND_OPTION_MAX_PITCH` set to `fm.MapOptions.pitchLimit` when it creates a map, so that MapLibre Native renders the pitch that `flutter_map` uses. Camera prediction already clamps to `fm.MapOptions.pitchLimit`. The demo's 3D view slider already uses `MapOptions.pitchLimit` as its maximum.

### 7. Verification

- Unit tests of `groundViewport` and the far limit: in the viewport above 70.82°, not below; the positions given in decision 2.
- Unit tests of the conversions above and below the far limit, and of the camera fits at 85°.
- Widget tests for the spec scenarios at 85°: the viewport below the far limit is covered, nothing is drawn above it, a polygon beyond the far limit and behind the camera is clipped, the drag above the far limit, and the visible bounds.
- The existing tests run unchanged; their pitch is at most 60, below the far limit.
- The tile harness of change 5 (`~/git/tile-lod-harness`) on the Pixel at 70, 80 and 85°: tile requests, decoded memory, load time and frame time.
- In mapigrade: the static alignment check at pitch 85, and the demo's 3D view on the Mac and the iPhone.

## Risks / Trade-offs

- [Clipping every ground layer costs raster time] → A hard-edged clip to a quadrilateral; measured with the harness's frame times at 60° and 85°.
- [The large empty area above the horizon at 85° looks unfinished with the default gray background] → Documented on `maxPitch`; a sky is a non-goal.
- [`MapOptions.pitchLimit` is public, and code that assumed 60 sees 85] → `maxPitch` still defaults to 0; the changelog of the fork notes it.
- [MapLibre Native and the overlays end the ground at different places] → Both use 89.25°; the alignment check at 85° shows any difference.
- [Precision of large projected coordinates near the far limit] → The far limit bounds them; the footprint at 85° is finite and checked by the visible bounds test.
