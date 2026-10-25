## Why

mapigrade can't show a pitched map, because in integration model A `flutter_map` controls the camera and `flutter_map` has no pitch. A camera with pitch, a projection that matches MapLibre Native's, and layers that draw correctly when pitched are the base that mapigrade pitch (change 2 in `docs/map-pitch-concept.md`), pitch gestures (change 3) and pitched camera fitting (change 4) depend on.

## What Changes

This change is implemented in our `flutter_map` fork (greensopinion/flutter_map), on a branch from fleaflet's `master`, with the intent of an upstream PR. It changes nothing in mapigrade.

- The `flutter_map` camera has a pitch, set initially from the map options and later from the map controller, with a map event for each change. The maximum pitch defaults to 0 and is at most 60°.
- When pitched, the camera projects between coordinates and screen positions with MapLibre Native's camera model, and screen-to-coordinate conversion casts the view ray to the ground.
- Layers that move with the map draw in perspective and cover the viewport at every pitch and rotation; the tile layer loads the tiles of the visible ground.
- Markers and polygon labels are drawn upright and unscaled at the screen position of their point.
- The existing pinch, scroll-wheel and double-tap zoom keep the ground point under the focal point fixed on a pitched map.
- With pitch 0, behavior is unchanged.
- No pitch gesture, no pitched camera fitting or constraints, and no tile level of detail; these are later changes.

## Capabilities

### New Capabilities

- `flutter-map-pitch`: pitch in our `flutter_map` fork: the pitched camera and projection, and how layers draw and respond to input when pitched.

### Modified Capabilities

None. mapigrade's behavior changes in change 2.

## Impact

- The fork: `MapCamera`, `MapOptions`, `MapController`, map events, `MobileLayerTransformer`, the tile range calculation, the marker layer and polygon labels, and the example app.
- Public API additions in the fork, all with defaults that keep existing behavior, and no other API changes. The exception is the new `MapController.pitch` member, which a class that implements `MapController` itself has to add. Plugins that compute screen positions themselves are wrong only in applications that set a maximum pitch above 0.
- mapigrade: none in this change. Change 2 adds a `dependency_overrides` entry for the fork branch.
