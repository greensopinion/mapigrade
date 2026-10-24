# MapLibre Native: rendered query results aren't in style order

This document describes a defect in MapLibre Native (github.com/maplibre/maplibre-native) that affects Mapigrade. It is the input for an upstream fix, which is separate from the OpenSpec change `add-demo-showcases`; that change found the defect and works around it in the demo. Related defects in the same project are described in [maplibre-feature-state-coalescing.md](maplibre-feature-state-coalescing.md) and [maplibre-symbol-query-feature-state.md](maplibre-symbol-query-feature-state.md).

## Summary

`Renderer::queryRenderedFeatures` in MapLibre Native returns features grouped by style layer, but the groups are in the iteration order of a `std::unordered_map` keyed by layer ID, not in style order. A caller that takes the first feature as the feature drawn on top gets a feature of an arbitrary layer.

This is a defect, not an unspecified order, for these reasons:

- MapLibre Native documents the order. The iOS SDK's `MLNMapView` (`platform/ios/src/MLNMapView.h`), whose `visibleFeaturesAtPoint:` and `visibleFeaturesInRect:` return this result, states: "The returned array is sorted by z-order, starting with the topmost rendered feature and ending with the bottommost rendered feature."
- The code states the order it intends. The merge loop's comment reads "Combine all results based on the style layer renderItems", but the loop doesn't do that.
- Callers can't restore the order. `Feature` doesn't report the layer that drew it, so the order of the result is the only information about which feature is on top. The most common use of a query, finding the feature that the user tapped, depends on it.
- The order isn't predictable. It depends on the hashes of the layer IDs and on the standard library's hash table, so one style can give different orders on Linux and on Apple platforms, and adding a layer can change the order of the other layers.
- MapLibre GL JS returns features of the topmost layer first, so the same style and query give a different first feature on the web and on native platforms.

Mapigrade's `feature-query` spec and API docs state the order that the iOS SDK documents, so both are wrong while the defect exists.

## How we found it

The demo's "Inspect features" screen queries the features at a tap with `LayerController.queryRenderedFeatures` and highlights the first feature of the result. On 2026-10-24, with the OpenFreeMap Liberty style over Nice at about zoom 16, we tapped a building that lies inside a park. The demo highlighted the park, a polygon of the source layer `park`, which Liberty draws at layer index 2, instead of the building, which Liberty draws at layer index 84 (`building-3d`, a `fill-extrusion` layer from zoom 14). We didn't record the full result of that query; we found the cause below by reading the code.

## Where the defect is

Mapigrade uses MapLibre Native through MapLibre Native FFI (github.com/maplibre/maplibre-native-ffi, checked out at `/Users/dgreen/git/maplibre-native-ffi`), which vendors MapLibre Native in `third_party/maplibre-native/` at commit `254d0a872407c15e9ea4211691af0abeb7e18f16`. In that commit, the namespace and the source directory are `mln` (`src/mln/...`). On 2026-10-24, upstream `main` had the same code in `src/mln/renderer/render_orchestrator.cpp`.

In `src/mln/renderer/render_orchestrator.cpp`, the public overload collects the layers into an unordered map:

```cpp
std::vector<Feature> RenderOrchestrator::queryRenderedFeatures(const ScreenLineString& geometry,
                                                               const RenderedQueryOptions& options) const {
    std::unordered_map<std::string, const RenderLayer*> layers;
    if (options.layerIDs) { /* one entry per requested ID */ }
    else { for (const auto& entry : renderLayers) layers.emplace(entry.second->getID(), entry.second.get()); }
    return queryRenderedFeatures(geometry, options, layers);
}
```

The private overload copies the layers that need rendering at the current zoom into another unordered map, `filteredLayers`. It then collects the results of each source's query and of the symbol query into `resultsByLayer`, also an `unordered_map<std::string, std::vector<Feature>>`, keyed by layer ID, and merges them:

```cpp
    // Combine all results based on the style layer renderItems.
    for (const auto& pair : filteredLayers) {
        auto it = resultsByLayer.find(pair.second->baseImpl->id);
        if (it != resultsByLayer.end()) {
            std::move(it->second.begin(), it->second.end(), std::back_inserter(result));
        }
    }
```

The comment states the intended order, but the loop iterates `filteredLayers`, so the order of the groups depends on the hash of each layer ID and on the standard library's hash table. It can differ between libc++ (iOS, macOS, Android) and libstdc++ (Linux), and it changes when layers are added.

Within one layer, the order is correct: `FeatureIndex::query` in `src/mln/geometry/feature_index.cpp` sorts by `sortIndex`, descending, so later features of a tile come first, and `lookupSymbolFeatures` sorts symbols by the placement's `featureSortOrder`. Only the order across layers is wrong.

## The style order is available

`RenderOrchestrator` keeps the style order in `orderedLayers` (`RenderLayerReferences`, a vector of `std::reference_wrapper<RenderLayer>`, declared in `render_orchestrator.hpp`), bottom layer first. `createRenderTree` rebuilds it from `layerImpls` whenever layers are added or removed, and asserts that it has as many entries as `renderLayers`.

## Proposed fix

Merge the groups in reverse style order, restricted to the layers that passed the filter:

```cpp
    // Combine all results in style order, topmost layer first.
    for (auto it = orderedLayers.rbegin(); it != orderedLayers.rend(); ++it) {
        const std::string& layerID = it->get().getID();
        if (!filteredLayers.contains(layerID)) continue;
        auto found = resultsByLayer.find(layerID);
        if (found != resultsByLayer.end()) {
            std::move(found->second.begin(), found->second.end(), std::back_inserter(result));
        }
    }
```

Points to check while making the fix:

- A query can run before the first `createRenderTree`, when `orderedLayers` is still empty. With the fix, such a query returns no features. That is correct, because no frame has been rendered, but check that no caller depends on features before the first render.
- With `layerIDs`, the fix returns the features in style order, not in the order of the requested IDs. We believe that GL JS does the same, but we haven't checked. Check GL JS's `queryRenderedFeatures` before the upstream PR states that the fix matches GL JS.
- The cost of the merge changes from O(filtered layers) to O(style layers). It remains small compared with the cost of the tile queries.
- `queryShapeAnnotations` calls the same private overload, so annotations get style order too.

## Tests

- In `test/api/query.test.cpp`, add a test with a GeoJSON source of ten identical polygons, each with a property `n` from 0 to 9, and ten fill layers, where layer `i` has the filter `n == i`. `Feature` doesn't report its layer, so `n` identifies the layer that returned each feature. Choose layer IDs whose hash order differs from their style order; with ten layers, the probability that the two orders are equal by chance is negligible. Query a point inside the polygons, once without `layerIDs` and once with `layerIDs` in a shuffled order, and assert that the values of `n` are in reverse style order. Without the fix, the test fails.
- The query render tests in `metrics/integration/query-tests/` compare `actual.json` with `expected.json` with `deepEqual`, which compares arrays in order. Run them after the fix. A test with several layers whose `expected.json` was generated from MapLibre Native's own output can fail after the fix; before updating its `expected.json`, compare the new result with GL JS's expected result for the same test.

## What Mapigrade does until the fix is released

- The demo's inspect screen queries each of the style's own layers with `layerIds: [id]`, sends all the queries at once, and selects the feature of the topmost layer that returns one (design D193 of `add-demo-showcases`).
- The `feature-query` spec (requirement "Query results") and the doc comment of `LayerController.queryRenderedFeatures` in `packages/flutter_mapigrade/lib/src/layer/layer_controller.dart` state that features of the topmost style layer come first. We plan a separate Mapigrade change that corrects both to state that the order across layers is unspecified. When the pinned FFI release contains the fix, a later change restores the statement.
- On 2026-10-24, Mapigrade pinned FFI release 0.202610.2. Mapigrade gets the fix when we pin an FFI release that vendors a MapLibre Native commit with the fix, in `packages/flutter_mapigrade/maplibre_ffi.lock`.
