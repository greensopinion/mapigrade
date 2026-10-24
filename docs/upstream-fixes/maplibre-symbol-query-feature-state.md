# MapLibre Native: queried symbol features have no feature state

This document describes a defect in MapLibre Native (github.com/maplibre/maplibre-native) that affects Mapigrade. It is the input for an upstream fix, which is separate from the OpenSpec change `add-demo-showcases`; that change found the defect and works around it in the demo. Related defects in the same project are described in [maplibre-query-result-order.md](maplibre-query-result-order.md) and [maplibre-feature-state-coalescing.md](maplibre-feature-state-coalescing.md).

## Summary

`Renderer::queryRenderedFeatures` returns each feature with its feature state in `Feature::state`, except features of symbol layers (labels and icons), which always have empty state, even when their state is set.

This is a defect for these reasons:

- One query can contradict itself. A feature that two style layers draw is returned once per layer, and when one of them is a symbol layer, the two copies disagree about the feature's state. For example, OpenFreeMap Liberty draws a one-way street of the source layer `transportation` with a line layer such as `road_minor` and with the symbol layer `road_one_way_arrow`, which places arrows along the same line. A query at an arrow returns the street from `road_minor` with `selected: true` and from `road_one_way_arrow` with empty state.
- The state exists and is used: the style's `feature-state` expressions read it, so the map can draw a label as selected while a query of that label says it has no state.
- An application can't tell an empty state from a state that wasn't looked up, because `Feature` doesn't report the layer type that matched.
- An application reads state back through a query to check the state that the map uses, for example after `setFeatureState`. For symbols, the query returns empty state without an error.

## How we found it

The demo's "Inspect features" screen sets `selected: true` on the feature that the user taps, then queries that feature's layer again and shows the returned state. On 2026-10-24, with the OpenFreeMap Liberty style, we selected a water polygon and a POI label. The demo had set `selected: true` on both, and the map drew both as selected, but the query returned `selected: true` for the water polygon and empty state for the label.

## Where the defect is

Mapigrade uses MapLibre Native through MapLibre Native FFI (github.com/maplibre/maplibre-native-ffi, checked out at `/Users/dgreen/git/maplibre-native-ffi`), which vendors MapLibre Native in `third_party/maplibre-native/` at commit `254d0a872407c15e9ea4211691af0abeb7e18f16`. In that commit, the namespace and the source directory are `mln` (`src/mln/...`).

In `src/mln/geometry/feature_index.cpp`, `FeatureIndex::addFeature` looks up the state when it gets a `SourceFeatureState`:

```cpp
        FeatureState state;
        if (sourceFeatureState != nullptr) {
            ...
                sourceFeatureState->getState(state, sourceLayer->getName(), *idStr);
        }
        ...
        feature.state = state;
```

`FeatureIndex::query`, which handles queries of non-symbol layers, passes the source's `SourceFeatureState`. `FeatureIndex::lookupSymbolFeatures`, which handles queries of symbol layers through the collision index, passes `nullptr`:

```cpp
    for (const auto& symbolFeature : sortedFeatures) {
        mat4 unusedMatrix;
        addFeature(result, symbolFeature, queryOptions, globalState, tileID, layers,
                   GeometryCoordinates(), {}, 0, unusedMatrix,
                   nullptr);
    }
```

Its caller, `RenderOrchestrator::queryRenderedSymbols` (`src/mln/renderer/render_orchestrator.cpp`), uses the placement's collision index and the retained query data of each bucket. It doesn't look up the source's `SourceFeatureState`, and `lookupSymbolFeatures` has no parameter for one.

For non-symbol layers, `addFeature` also passes the state to `RenderLayer::queryIntersectsFeature`, for paint properties that read `feature-state`; symbol layers skip that test. The query filter is evaluated without feature state on both paths.

On 2026-10-24, upstream `main` (`src/mln/geometry/feature_index.cpp`) also passed `nullptr` in `lookupSymbolFeatures`. The vendored file differs from upstream `main` elsewhere, in tile ID types and envelope hit testing, but not in this call.

## Proposed fix

Give `lookupSymbolFeatures` the feature state of the source, and pass it to `addFeature`:

- Add a `const SourceFeatureState*` parameter to `FeatureIndex::lookupSymbolFeatures`.
- In `RenderOrchestrator::queryRenderedSymbols`, find the `RenderSource` of each bucket's layers, through the `RenderLayer`'s `baseImpl->source` and `getRenderSource`, and pass its feature state. `RenderTileSource` owns the `SourceFeatureState featureState` that its `queryRenderedFeatures` already uses for non-symbol layers. Either add an accessor for it, or let the source look up the state, as it does for non-symbol layers.
- Several layers can share the retained query data of one bucket, but those layers have one source, so one `SourceFeatureState` per bucket is enough.

Before choosing, check how MapLibre GL JS attaches state to symbol features (`src/source/query_features.ts` and `src/style/style.ts`); if the fix gives the same results as GL JS, the web and native platforms return the same state. We haven't checked whether GL JS returns state for symbols.

## Tests

- In `test/api/query.test.cpp`, with the fixture `test/fixtures/api/query_style.json`, which has symbol layers: set feature state on a feature of a symbol layer, render, query its position with that layer's ID, and assert that `Feature::state` has the state. Without the fix, the test fails. Add the same assertion for a fill or circle layer to show that both paths agree.
- A query test in `metrics/integration/query-tests/feature-state/` with a symbol layer, a `setFeatureState` operation and a `wait`, whose `expected.json` contains the state.

## What Mapigrade does until the fix is released

- The demo's inspect screen states, for a feature of a symbol layer, that MapLibre Native doesn't return feature state for labels and icons, in place of the empty state (design D194 of `add-demo-showcases`).
- The `feature-query` spec (requirement "Query results") states that each `QueriedFeature` has its feature state. We plan a separate Mapigrade change that states this limitation in the spec and in the doc comment of `QueriedFeature.state`, together with the corrections for the other two defects.
- Mapigrade gets the fix when we pin an FFI release that vendors a MapLibre Native commit with the fix, in `packages/flutter_mapigrade/maplibre_ffi.lock`.
