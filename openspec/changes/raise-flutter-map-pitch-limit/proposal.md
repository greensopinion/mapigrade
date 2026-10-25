## Why

`flutter_map` maps in the fork, and mapigrade's maps, can pitch to at most 60°, because above 60° the visible ground grew without bound and the tile layer had one tile zoom. Change 5 gave the tile layer coarser tiles for far ground, so a higher pitch is now possible; MapLibre allows up to 85° in GL JS by default and more in Native. This is change 6 in `docs/map-pitch-concept.md`, renamed from `limit-flutter-map-pitch-near-horizon` because it now raises the limit as well as limiting movement near the horizon (user decision, 2026-10-25).

## What Changes

The `flutter_map` part is implemented in our fork (greensopinion/flutter_map), on the branch `map-pitch`; the rest is in mapigrade.

- `MapOptions.pitchLimit` rises from 60° to 85°. `maxPitch` still defaults to 0, so applications that don't set it don't change.
- A far limit ends the visible ground where the view ray is 89.25° from straight down, as in MapLibre Native. The far limit is in the viewport only above a pitch of about 70.8°; up to that pitch nothing changes.
- Above the far limit, ground layers draw nothing and the map's background color shows. There is no sky.
- The camera's visible bounds, pixel bounds, size and pixel origin, the tile cover, and the polygon and polyline culling use the visible ground up to the far limit.
- Converting a screen position above the far limit gives no coordinate, or, where a coordinate is required, the coordinate on the far limit below it.
- Gestures whose pointer or focal point is above the far limit act at the far limit below it, so a drag near the horizon moves the ground by a bounded distance.
- Camera fits use the part of the viewport below the far limit.
- Ground layers are clipped to the visible ground, so that no point beyond the far limit or behind the camera is drawn.
- mapigrade sets MapLibre Native's maximum pitch to `MapOptions.pitchLimit`, and its camera prediction limits the predicted pitch to it. The demo's 3D view lets the pitch go to the limit.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-map-pitch`: the pitch limit rises to 85°; a far limit of the visible ground is added, and the projection, ground layers, visible bounds and tiles, gestures, controller offsets and camera fits use it instead of the horizon.
- `map-layer`: the MapLibre map's maximum pitch and the predicted pitch follow `MapOptions.pitchLimit` instead of 60°.
- `demo-app`: the 3D view's pitch slider goes from 0 to `MapOptions.pitchLimit`.

## Impact

- The fork: `MapOptions`, `MapCamera`, `MobileLayerTransformer`, `TileCoverCalculator`, the camera fits, the map controller's offset methods, `MapInteractiveViewer`, the polygon and polyline layers' culling, the example's Pitch page, documentation and tests.
- mapigrade: `flutter_mapigrade`'s native map setup (`mln_map_set_bounds` with `MLN_BOUND_OPTION_MAX_PITCH`), camera prediction, the demo's 3D view, and tests.
- `MapOptions.pitchLimit` is a public constant whose value changes; code that used it as 60 sees 85.
