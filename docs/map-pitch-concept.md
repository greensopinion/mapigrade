# Map pitch: concept

**Status:** Concept and decisions; changes 1 to 5 done
**Updated:** 2026-10-25

## Current state

- Change 1 (`add-flutter-map-pitch-camera`) is done and archived. Its code is commit `04c3e14` on the fork's local branch `map-pitch` in `~/git/flutter_map`, which is not pushed.
- Change 2 (`add-pitch`) is done on mapigrade's branch `map-pitch` and archived, with its specs synced. mapigrade resolves `flutter_map` to the fork through a path override in the root `pubspec.yaml`, which needs the fork checked out next to mapigrade.
- The demo's README video was made again with the pitched flyover (`packages/demo/build/readme_demo.mp4`) and is not uploaded.
- Change 3 (`add-flutter-map-pitch-gestures`) is done and archived. Its code is commit `66b72e5` on the fork's local branch `map-pitch`, which is not pushed. In Chrome on macOS, Ctrl-click opens the browser's context menu; the fork documents that web applications that enable pitch disable it.
- Change 4 (`pitch-camera-fit-and-constraints`) is done and archived. Its code is commit `a581ef2` on the fork's local branch `map-pitch`, which is not pushed. It also fixed the contain constraints, which change 1 had broken on pitched maps.
- Change 5 (`add-flutter-map-tile-level-of-detail`) is done and archived; decisions 21 and 23 were revised during implementation. Its code is commit `979748d` on the fork's local branch `map-pitch`, which is not pushed. Follow-up commits `76d0633` (the cover is computed once per camera: median build time while rotating at 60° on the Pixel went from 3.0 ms before the change, to 7.3 ms, to 4.7 ms) and `03cfd00` (removed `TileRangeCalculator`) are on the same branch. It also fixed a defect in `NetworkTileImageProvider`, in its own commit `e33cd10`: a tile whose URL matched an aborted load could show the aborted load's transparent image. Upstream PRs are not planned yet.
- Change 6, renamed `raise-flutter-map-pitch-limit`, is proposed: it raises the pitch limit to 85°, with a far limit of the visible ground at 89.25° from straight down, the background color above it, and a movement limit for gestures above it (user decisions, 2026-10-25).
- Next: implement change 6. Pushing the fork, contacting the fleaflet maintainers and uploading the video are public actions that need explicit approval first (section 12).

## 1. Purpose

We want a map whose camera can be pitched: the camera looks at the ground at an angle instead of straight down. MapLibre Native renders pitched maps, but `flutter_map` has no pitch, and in integration model A `flutter_map` controls the camera, the gestures and the overlays. Pitch therefore has to be added to `flutter_map` first, and then passed through mapigrade to MapLibre.

This document records the decisions that we made while exploring pitch, so that the OpenSpec changes that implement it are written from one source. Logical pixels are abbreviated px. H and W are the viewport height and width in px.

## 2. The earlier experiment

[fleaflet/flutter_map#1273](https://github.com/fleaflet/flutter_map/pull/1273) (closed, unmerged) drew each layer flat and then applied `Transform(Matrix4..setEntry(3, 1, -0.002)..rotateX(pitch))`. It didn't produce a usable map, for these reasons:

1. The perspective entry `-0.002` is not derived from a field of view or a camera distance, so there was no camera model for `latLngToScreenOffset`, `screenOffsetToLatLng`, gestures or hit testing to invert. Markers used a separate approximation of the same transform.
2. The flat layer was sized `H / cos(pitch)`, which assumes an orthographic tilt. Under perspective the far edge of the visible ground is also wider than W, so the layer didn't fill the viewport.
3. All tiles were loaded at one zoom, so distant tiles were loaded at full resolution and then drawn smaller.
4. Pan and pinch-zoom worked in screen pixels, not on the ground plane.
5. Each layer declared `applyPitch` on `LayerOptions`, a class that `flutter_map` no longer has.

## 3. Camera model

We use MapLibre Native's camera model, so that a pitched MapLibre map and pitched `flutter_map` overlays align without a conversion between two projections:

- vertical field of view `0.6435011087932844` rad (36.87°), MapLibre's `DEFAULT_FOV`;
- camera distance from the center point `0.5 · H / tan(fov / 2)` = 1.5 H, MapLibre's `getCameraToCenterDistance`;
- default maximum pitch 60°, MapLibre's `DEFAULT_PITCH_MAX`.

With these constants the map scale at the center point does not change with pitch, so the zoom describes the scale at the center point. Points nearer the camera are drawn larger and points farther away are drawn smaller.

The world-to-screen transform, applied to a point in `flutter_map`'s north-up map pixel space at the camera zoom, is:

```
screen = T(viewport center) · P(1.5 H) · Rx(pitch) · Rz(rotation) · T(-project(center))
```

`P(d)` is the perspective with focal length `d` px, so a point on the ground at the center point keeps scale 1. Screen to ground is the inverse: cast the view ray through the screen point and intersect it with the ground plane. A screen point above the horizon has no ground point.

## 4. The visible ground area

Unpitched, the visible ground is the viewport rectangle, rotated. Pitched, it is a trapezoid, the footprint: narrow at the near edge of the viewport and wide at the far edge.

```
             far edge  (wide, distant, drawn small)
         +---------------------------+
          \                         /
           \       footprint       /
            \                     /
             \        * center   /
              +-----------------+
              near edge (drawn large)
                     ^
                   camera
```

With the constants in section 3:

| Pitch | Far edge beyond center | Near edge before center | Far edge width | Scale at near edge | Scale at far edge |
|---|---|---|---|---|---|
| 30° | 0.71 H | 0.48 H | 1.31 W | 1.13 | 0.77 |
| 45° | 1.06 H | 0.53 H | 1.58 W | 1.26 | 0.63 |
| 60° | 2.37 H | 0.63 H | 2.49 W | 1.50 | 0.40 |
| 70° | 17.4 H | 0.76 H | 12.5 W | 1.82 | 0.08 |

At 60° the bounding box of the footprint is about 2.5 W × 3.0 H, 7.5 times the unpitched area. Above 60° it grows without bound. MapLibre limited pitch to 60° until it had tile level of detail and a horizon, and we do the same.

The camera is 1.30 H behind the center point at 60°, and ground points more than 1.73 H before the center point are behind the camera. A flat layer canvas that is centered on the center point and large enough for the far edge (2.37 H) would contain points behind the camera, which have no valid perspective projection. The canvas therefore covers the bounding box of the footprint, which is not centered on the center point.

## 5. Layers

`flutter_map` layers already state how they move with the camera by their structure, not by a flag: a layer that wraps its content in `MobileLayerTransformer` moves and rotates with the map, and a layer that doesn't, such as the attribution, stays fixed in the viewport. Pitch adds a third kind:

| Kind | Examples | With pitch |
|---|---|---|
| Ground | tiles, polygons, polylines, circles, overlay images | Painted flat in map pixels inside `MobileLayerTransformer`, which applies the full world-to-screen transform. Strokes and fills are drawn smaller with distance. |
| Billboard | markers, polygon labels | Placed at the screen position of their point, drawn upright and unscaled in screen space by a new billboard transformer |
| Static | attribution, scale bar | Unchanged. The scale bar is correct only at the center point. |

A layer that paints in map pixels from `pixelOrigin` and `visibleBounds` works pitched without changes. A layer that computes its own screen positions, such as the marker layer's counter-rotation and the polygon label's `canvas.rotate(-rotationRad)`, is wrong when pitched and has to move to the billboard transformer or to the camera's projection methods.

## 6. Zoom when pitched

The zoom is the scale at the center point (section 3), so changing the pitch doesn't change the zoom, and `minZoom`, `maxZoom` and zoom-dependent styling keep their meaning. Zoom behavior changes in these places:

1. **Focal-point zoom.** Pinch-zoom, scroll-wheel zoom and double-tap zoom keep the ground point under the focal point fixed. Pitched, the focal point's ground point is found by ray-casting, the zoom is changed, the ground point under the focal point is found again, and the center is moved by the difference. This is exact because moving the center only translates the projection in Mercator pixel space. When the focal point is above the horizon, the zoom is around the center point. Near the horizon, small focal-point movements map to large ground distances; change 6 handles that. The same ray-casting applies to the rotate gesture, drag, fling and the controller's screen-offset methods (section 8, change 1).
2. **Pitch gesture and pinch-zoom.** A two-finger gesture can be zoom, rotate, move or pitch. Change 3 decides how they are told apart.
3. **Fit and constraints.** `CameraFit.bounds` and `CameraConstraint` assume a rectangular visible area. Change 4 makes them use the footprint.
4. **Tile zoom.** `TileLayer` chooses one tile zoom from the camera zoom. At 60°, near tiles are drawn 1.5 times larger (slightly blurred) and far tiles 2.5 times smaller (more tiles than needed). We accept both until tile level of detail.
5. **Sizes given in meters or px.** Ground layers drawn in map pixels at the center scale are drawn smaller with distance. The scale bar measures at the center point only.

## 7. Repositories and branches

- The `flutter_map` work is done in our fork, [greensopinion/flutter_map](https://github.com/greensopinion/flutter_map), on the branch `map-pitch`, created from `upstream/master` (fleaflet). We intend to open an upstream PR from it later. The fork's own `master` is 86 commits behind upstream (7.0.2 vs 8.4.0-dev.1) and is not the base.
- The mapigrade work is done on mapigrade's branch `map-pitch`. It depends on the fork's `map-pitch` through a git `dependency_overrides` entry for `flutter_map` that pins a commit, until the upstream PR is merged and released. mapigrade's `map-pitch` is merged to its `main` only when we're ready for that dependency.
- Every public action (pushes to public branches, issues, PRs, comments) needs explicit approval first (section 12).
- All OpenSpec changes, including those that change only the fork, are in the mapigrade repo. The fork's behavior is the capability `flutter-map-pitch`.

## 8. Changes

We split the work so that the projection is verified against MapLibre before the gesture work depends on it (option c in the exploration):

| # | Change | Repository | Depends on |
|---|---|---|---|
| 1 | `add-flutter-map-pitch-camera` | fork | |
| 2 | `add-pitch` | mapigrade | 1 |
| 3 | `add-flutter-map-pitch-gestures` | fork | 1, verified by 2 |
| 4 | `pitch-camera-fit-and-constraints` | fork | 1 |
| 5 | `add-flutter-map-tile-level-of-detail` | fork | 1 |
| 6 | `raise-flutter-map-pitch-limit` (first named `limit-flutter-map-pitch-near-horizon`) | fork and mapigrade | 1, 5 |

Change 5 is planned before the upstream PR is accepted, because the maintainers may require it (decision 12). When we open the PR, and how we split it, is open (section 12).

### Change 1: `add-flutter-map-pitch-camera` (fork)

- `MapCamera.pitch` and the world-to-screen transform of section 3.
- `latLngToScreenOffset`, `screenOffsetToLatLng`, `offsetToCrs` and `focusedZoomCenter` through the transform and its inverse, so that the existing pinch, scroll-wheel and double-tap zoom and the two-finger rotate gesture keep the ground under the focal point.
- Every other conversion of a screen offset to a ground offset by rotation alone changes to ray-casting: `MapController.move` with `offset` (used by `flutter_map_location_marker` and similar plugins), `MapController.rotateAroundPoint`, drag (the ground point under the pointer stays under it) and fling (animates the drag's ground velocity). Keyboard pan and rotation are correct when pitched and don't change. `MapCamera.rotatePoint` keeps its 2D meaning (section 11).
- `visibleBounds`, `pixelBounds` and the tile range from the footprint.
- `MobileLayerTransformer` applies the full transform over a canvas that covers the footprint's bounding box (section 4).
- A billboard transformer; the marker layer and the polygon labels use it.
- `MapOptions.initialPitch`, and `MapOptions.maxPitch` with default 0 and a limit of 60°. With the default, no application or plugin changes behavior.
- `MapController.pitch`, with a `MapEventPitch` event whose source is `MapEventSource.mapController`.
- No pitch gesture.

### Change 2: `add-pitch` (mapigrade)

- `pitch` in mapigrade's `MapCamera` and in the FFI binding. The FFI's `mln_camera_options` already has `pitch` and `field_of_view`, and `mln_bound_options` has `min_pitch` and `max_pitch`. The native core currently sets only `MLN_CAMERA_OPTION_CENTER`, `MLN_CAMERA_OPTION_ZOOM` and `MLN_CAMERA_OPTION_BEARING`.
- The layer sets the MapLibre pitch from the `flutter_map` pitch, and the frame report includes the pitch.
- Perspective in `src/core/projection.h` (which states that the camera has no pitch) and in `lib/src/layer/camera_projection.dart`: `screenPosition` and `worldPosition`. If the fork's transform is public, the Dart side uses it instead of a copy.
- A pitch term in `CameraVelocity`, and pitch in `flutterMapCameraOf`, so that camera prediction and children alignment work pitched.
- The `dependency_overrides` entry for the fork branch.
- A pitch showcase in the demo app.
- Verification: at rest, a geographic coordinate appears at the same screen position in the MapLibre map and in `flutter_map` overlays, at several pitches and rotations. This is the test of change 1's projection.

### Change 3: `add-flutter-map-pitch-gestures` (fork)

- `InteractiveFlag.pitch`, included in `InteractiveFlag.all`; it has no effect while `maxPitch` is 0. Pitch gesture events use the existing multi-finger `MapEventSource` values (section 11).
- Two-finger vertical drag changes the pitch: both fingers move vertically in the same direction, and the line between them is near horizontal. This is MapLibre's rule. `ScaleUpdateDetails` has only the focal point, so the viewer records each pointer's position in its `Listener`.
- The pitch changes by 0.5° per px of vertical movement, as on iOS and in GL JS, and moving up increases it. The pitch pivots on the viewport center, so the center and the zoom don't change, as with `MapController.pitch`.
- A threshold for the pitch gesture, alongside `rotationThreshold`, `pinchZoomThreshold` and `pinchMoveThreshold`.
- While `maxPitch` is above 0, a two-finger gesture holds back zoom, rotate and move until the pitch gesture is recognized or ruled out, with or without `enableMultiFingerGestureRace`. A recognized pitch gesture locks them out for the rest of the gesture (decision 13).
- Ctrl-drag (cursor/keyboard rotation) while `maxPitch` is above 0: horizontal movement rotates and vertical movement pitches, as in GL JS's default mouse handlers. Vertical movement changes the pitch by 0.5° per px. Horizontal movement rotates the map about the viewport center: more than 100 px above or below the center, by the angle that the horizontal movement makes at the center; otherwise by 0.8° per px. `CursorRotationBehaviour` and `setNorthOnClick` have no effect in this mode. At `maxPitch` 0, Ctrl-drag is unchanged.
- No keyboard pitch keys. A trackpad gives Flutter no per-finger positions, only a combined pan, scale and rotation, so it has no pitch gesture; on macOS, Ctrl-drag pitches.

### Change 4: `pitch-camera-fit-and-constraints` (fork)

- `CameraFit.bounds` and its variants choose a zoom so that the projected bounds lie in the viewport at the current pitch. This takes a short iteration, not a closed form. MapLibre Native's `cameraForLatLngs` does one step of the same estimate, which is only approximate when pitched.
- Only the built-in implementations change; `CameraFit` and `CameraConstraint` gain no abstract members (section 11).
- `CameraConstraint.contain` and `containLatitude` keep the same box inside their bounds at every pitch as at pitch 0, and ignore pitch, as MapLibre GL JS's `maxBounds` constraint does (decision 20). Ground beyond the bounds can be visible toward the far edge of a pitched map.

### Change 5: `add-flutter-map-tile-level-of-detail` (fork)

The goal is lower latency, decoded image memory and data transferred for `TileLayer` users of the fork; the user experience comes before the number of tile server requests. mapigrade doesn't use `TileLayer`, because MapLibre Native draws its base map. The change is required before `maxPitch` can exceed 60°.

- The tile layer loads the tiles that cover the visible ground, not its bounding box, with each tile's zoom chosen from its size on screen but not finer than today's (decision 21), so that far ground uses coarser tiles. On a Pixel-sized viewport at 60° and rotation 45°, that is 132 tiles today and 64 with the change, including the pan buffer.
- One code path for every map: an unrotated, unpitched map loads, draws and prunes the same tiles as before, and a rotated, unpitched map no longer loads tiles beyond the buffer in the corners of the bounding box (decision 22).
- `panBuffer` and `keepBuffer` are tiles around the visible ground, at each tile's zoom (decision 23).
- No hysteresis in the zoom rule (decision 24).
- Tiles load in order of their center's distance on screen from the viewport center (decision 25).
- Culling, the zoom rule and the load order are one change, so that the upstream PR is one review; it is split only if the zoom rule turns out to be large or complex.

### Change 6: `raise-flutter-map-pitch-limit` (fork and mapigrade)

First named `limit-flutter-map-pitch-near-horizon`. On 2026-10-25 we decided that change 6 also raises the pitch limit to 85°, because the movement limit has no effect at 60°. The change's design has the far limit, the clip of ground layers, and MapLibre Native's maximum pitch in mapigrade.

- Focal point or pointer near or above the horizon: limit the ground distance that a focal-point, drag or fling movement can cause, as MapLibre does. Change 1 already anchors zoom, rotation, drag and fling on the ground; change 6 limits the movement by acting on pointers above the far limit as on the far limit.
- The limit is needed only when `maxPitch` exceeds 60°, which requires change 5. The horizon is in the viewport only above a pitch of 90° − fov / 2 = 71.57°. At 60°, a 1 px vertical drag at the top edge moves the ground about 11 projected px, compared with 2 px at the center: large, but bounded and correct.

## 9. Decisions

| # | Decision | Status | Reason |
|---|---|---|---|
| 1 | Use MapLibre Native's camera model and constants (section 3) | Decided | mapigrade's map and overlays align without conversion |
| 2 | No per-layer pitch flag; ground, billboard and static layers (section 5) | Decided | Layers already state their kind by structure; a flag can't detect plugins that compute screen positions themselves |
| 3 | `maxPitch` defaults to 0 and is limited to 60° | Decided | Existing applications and plugins don't change; footprint size (section 4) |
| 4 | Projection methods, the controller's screen-offset methods, drag and fling ray-cast in change 1, not change 3 | Decided | Existing gestures and plugins then behave correctly when an application sets the pitch from code |
| 5 | Order: change 1, then 2, then 3 and 4 (option c) | Decided | Verify the projection against MapLibre before the gesture work depends on it |
| 6 | Work in the fork, intending an upstream PR | Decided | An upstream PR needs a fork; mapigrade isn't blocked on upstream review |
| 7 | mapigrade depends on the fork branch through `dependency_overrides` | Decided | Same as 6 |
| 8 | All OpenSpec changes are in mapigrade; capability `flutter-map-pitch` | Decided | One planning record |
| 9 | Zoom is the scale at the center point | Decided | Same as MapLibre; zoom limits and styling keep their meaning (section 6) |
| 10 | Layer canvas covers the footprint's bounding box, not centered on the center point | Decided | About 1.6 times smaller at 60°; avoids points behind the camera (section 4), although the spike showed that Flutter paints those correctly |
| 11 | Branch the fork from `upstream/master` | Decided | Base for the upstream PR |
| 12 | Single tile zoom until tile level of detail (change 5) | Decided | Correct, at 7.5 times the tiles at 60°; change 5 is planned before the upstream PR is accepted, because the maintainers may require it |
| 13 | A recognized pitch gesture locks out other two-finger gestures | Decided (change 3) | Same as MapLibre |
| 14 | Only additive API changes in `flutter_map`, in all four changes (section 11) | Decided | Applications and plugins upgrade without changes |
| 15 | `pitch` is a member of the `MapController` interface | Decided | `MapController` is abstract to hide `MapControllerImpl`; a GitHub code search found almost no other implementations, and mocks are unaffected |
| 16 | One branch `map-pitch` in each repository; mapigrade's override pins a commit of the fork's `map-pitch` | Decided | One line of work per repository; reproducible mapigrade builds |
| 17 | Pitch-0 compatibility is checked by geometry assertions in the fork's tests, and by golden tests kept out of the upstream PR | Decided | Upstream has no golden tests, and golden images differ between platforms |
| 18 | MapLibre reference positions are generated through the FFI's `mln_map_pixel_for_lat_lng` | Decided | Uses the FFI build we already have, instead of C++ against `TransformState` |
| 19 | While `maxPitch` is above 0, Ctrl-drag rotates with horizontal movement and pitches with vertical movement; no keyboard pitch keys | Decided (change 3) | Same as MapLibre GL JS; applications that keep `maxPitch` at 0 don't change |
| 20 | The contain constraints ignore pitch and keep the unpitched viewport box inside their bounds | Decided (change 4) | Same as MapLibre GL JS; keeping the footprint inside would refuse pitch changes whenever the bounds are smaller than about 2.5 W × 3 H at 60° |
| 21 | Each tile's zoom is `round(zoom + log2(scale))` at the tile's point nearest the camera, from the minimum native zoom to today's tile zoom | Decided (change 5) | Far tiles are drawn at most √2 times their native size and near tiles are as today; no more tiles than today for any camera. Without the limit to today's tile zoom, a zoom 0.45 above an integer loaded 10 to 25% more tiles than today; applications that need sharp near ground can use vector tiles |
| 22 | One tile selection for every map; unrotated, unpitched maps load the same tiles as before | Decided (change 5) | Two code paths would have to be maintained; rotated maps load about 15% fewer off-screen tiles |
| 23 | `panBuffer` and `keepBuffer` are the tiles around the visible ground, at each tile's own zoom | Decided (change 5) | Rings around every tile overlap the coarser covering tiles; at one zoom it is today's buffer |
| 24 | No hysteresis in the tile zoom rule | Decided (change 5) | Switching back is served from tiles that are already kept; today's rounding of the zoom has none either |
| 25 | Tiles load by their center's distance on screen from the viewport center | Decided (change 5) | Close to today's order at pitch 0; loads the center of the view first when pitched |

## 10. Risks

- **Perspective transforms in Flutter.** Flutter paints a 4 × 4 perspective `Transform`, and hit testing should invert it through `PointerEvent.removePerspectiveTransform`. We have not verified hit testing on a pitched layer or painting on Impeller; change 1 starts with a test of both.
- **Third-party plugins.** A plugin that computes screen positions itself is wrong when an application sets `maxPitch` above 0. The default of 0 limits this to applications that enable pitch; the fork documents the migration.
- **Upstream acceptance.** The fleaflet maintainers may want a different API or tile level of detail (change 5) before merging. mapigrade is not blocked by this (decision 7), but its dependency stays on the fork until the PR is merged. Adding `pitch` to `MapController` (decision 15) breaks a hand-written `implements MapController`; the PR description states this so that the maintainers can decide whether it requires a major release.
- **Web.** `flutter_map` supports web, so the upstream PR has to work there, although mapigrade doesn't. The spike in change 1 includes Chrome.
- **Frame time.** At 60° the tile layer loads up to 7.5 times the tiles. Change 1 measures frame time on the Pixel at 60°, for the upstream PR and to judge how urgent change 5 is.
- **`flutter_map` version.** `upstream/master` is 8.4.0-dev.1 and mapigrade depends on `^8.3.2`; changes on `upstream/master` since 8.3.2 apply to mapigrade through the override.

## 11. API compatibility

Every change to `flutter_map` is additive (decision 14), so that code written for the current release compiles unchanged and, at pitch 0, behaves the same. These rules apply to changes 1, 3, 4 and 5:

- New parameters are optional, with defaults that keep current behavior: `MapOptions.initialPitch`, `MapOptions.maxPitch`, the `MapCamera` constructor's `pitch`, and the pitch gesture's `InteractionOptions`.
- No new `MapEventSource` values: an exhaustive `switch` on an enum stops compiling when a value is added, and upstream added values only in major releases (`keyboard` in v8.0.0). Pitch changes use `mapController`; the pitch gesture uses `multiFingerGestureStart`, `onMultiFinger` and `multiFingerEnd`; Ctrl-drag pitch uses `cursorKeyboardRotation`.
- New `MapEvent` subclasses are allowed: `MapEvent` is `abstract`, not `sealed`.
- No new abstract members on `CameraFit` or `CameraConstraint`, which applications subclass. Change 4 changes only the built-in implementations.
- Existing method signatures don't change. `screenOffsetToLatLng` stays non-nullable; a new method returns null above the horizon.
- `InteractiveFlag.pitch` is a new constant and is part of `InteractiveFlag.all`; with `maxPitch` at its default of 0 it has no effect.
- The meaning of `size`, `pixelOrigin` and `pixelBounds` widens when pitched (section 4), which affects only applications that raise `maxPitch`.
- Layer internals may change if the pixels drawn at pitch 0 don't change (decision 17). The marker layer always uses the billboard transformer, because changing its widget structure when the pitch leaves 0 would discard the markers' `State`. Polygon labels stay in the polygon painter at pitch 0, keeping the paint order that `drawLabelsLast` selects, and move to a screen-space painter only when pitched.
- The one exception is `MapController.pitch` (decision 15).

## 12. Open items

These don't block change 1:

- When to contact the fleaflet maintainers, for example with an issue or discussion about the API, and how to split the upstream PRs. Change 1 alone is large. Both are decided later, and each public action needs explicit approval first.
- Non-Mercator CRSs. Pitch works in projected pixel space, so they should work, but the MapLibre reference tests cover only EPSG:3857.
- Polyline simplification near the bottom edge, where the 1.5 times magnification at 60° may make the simplification visible.
- Done in change 2: a pitched flyover in the demo, which pitches the camera to 50 degrees while it follows a route.
- Markers that lie on the ground. Every marker faces the viewer (section 5), so a marker can't be drawn flat on the map, for example a direction arrow on a road. MapLibre offers both through pitch alignment: `icon-pitch-alignment` in the style spec, and `pitchAlignment` (`map` or `viewport`) on GL JS's `Marker`. #1273 had the same choice as `applyPitch`. A pitch-alignment option on `MarkerLayer` or `Marker` would be additive (section 11).
