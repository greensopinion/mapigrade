## Why

Tap-to-identify is the most common map interaction that `flutter_map` overlays can't provide: the features the user taps, such as a POI, a trail or a road, are inside the vector tiles that MapLibre renders, not in Dart. The FFI already offers rendered feature queries and per-feature state, so applications can identify the tapped feature and highlight it once mapigrade exposes them.

## What Changes

- Add `LayerController`, which the application creates and gives to `MapigradeLayer` through a new `controller` parameter, in the way `flutter_map` uses `MapController`.
- Add rendered feature queries to `LayerController`, in two forms: a point with a radius, and a screen rectangle. The application gives positions in the logical coordinates of the `flutter_map` viewport, as the user sees them. Each query returns a `Future` of the features that the map renders there, with an optional list of style layer IDs and an optional style-spec filter.
- Convert the query position from the camera of the displayed map frame to the camera of the last frame the map rendered, because MapLibre runs the query against its render state, which can be ahead of the displayed frame while the camera moves.
- Add `QueriedFeature`: the feature's ID, properties and GeoJSON geometry, its source ID and source-layer ID, and its feature state.
- Add feature state to `LayerController`: set state on a feature, and remove one key, all state of a feature, or all state of a source or source layer. Style expressions that read `feature-state` then change how the feature is drawn, for example to highlight the tapped feature.
- Add `LayerQueryException`, the exception with which a query fails.
- Deferred: line-string queries, source feature queries (`mln_render_session_query_source_features`), and reading feature state with `mln_map_get_feature_state`.

## Capabilities

### New Capabilities
- `feature-query`: rendered feature queries at a point with a radius and in a screen rectangle, aligned with the displayed map frame; the result type; and setting and removing feature state.

### Modified Capabilities
- `package-api`: the main library exports `LayerController`, `QueriedFeature` and `LayerQueryException`, in addition to the nine names it exports now.

## Impact

- Dart: a new public controller and result type under `packages/flutter_mapigrade/lib/src/layer/`, a `controller` parameter on `MapigradeLayer` and `MapTextureLayer`, query and feature-state methods on the internal `MapTextureController`, and FFI bindings for new C ABI functions.
- Native core (`packages/flutter_mapigrade/src/core/`): the first request with a result in the C ABI. Until now every command was fire-and-forget. The map thread runs queries and feature-state commands, converts query positions to the camera of the last rendered frame, and sends results to Dart.
- The test harness gets a style whose paint properties read `feature-state`, and tests that query and highlight features at rest and during camera movement on macOS, iOS and Android.
- No FFI change is needed. The FFI pin stays where it is.
