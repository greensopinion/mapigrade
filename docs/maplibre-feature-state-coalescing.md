# MapLibre Native: feature state changes are lost when a removal arrives in the same render

This document describes a defect in MapLibre Native (github.com/maplibre/maplibre-native) that Mapigrade depends on, for the work that fixes it upstream. That work is separate from the OpenSpec change `add-demo-showcases`, which found the defect and works around it in the demo. A related defect in the same project is in [maplibre-query-result-order.md](maplibre-query-result-order.md).

## Summary

MapLibre Native queues feature state changes and removals per source and applies them to the tiles when it next prepares the source for a render. When a removal and a change of feature state in one source layer are queued before the same render, the change isn't applied to the tiles. When a removal and a change of one feature's state are queued before the same render, in that order, the feature ends with the state removed.

This is a defect for these reasons:

- The application's last call doesn't take effect. After `removeFeatureState(B)` and then `setFeatureState(P, {selected: true})`, `getFeatureState(P)` returns `selected: true`, but the map doesn't draw P as selected. After `removeFeatureState(B, "selected")` and then `setFeatureState(B, {selected: true})`, B ends without `selected`, the opposite of the last call.
- The result depends on timing that the application doesn't control: the same calls give the right result when a render falls between them and the wrong one when none does.
- The drawn state and the stored state disagree. The stored state (`currentStates`) is correct, and the map draws it later, when a change in another source layer pushes the whole state of this source layer to the tiles. Until then the map draws a state that no sequence of calls produced.
- Changing a selection is the main use of feature state, and it is exactly a removal from the previous feature and a change to the next one, sent together.

## How we found it

The demo's "Inspect features" screen highlights the selected feature with the feature state `selected: true`, and changes the selection by removing `selected` from the previous feature and setting it on the next one, in one Dart call sequence, so both reach the map thread before the same render. On 2026-10-24, with the OpenFreeMap Liberty style over Nice, the user selected a building and then other features at the same tap from a list:

- choosing a second feature of the same source layer removed the first highlight but often didn't show the second;
- choosing an entry with the same ID as the selected building left no highlight (we haven't checked why the list contains the ID twice; a query returns a feature once per tile that it crosses, which is one way);
- after a few more choices, a feature that had been chosen earlier sometimes appeared highlighted.

The cause below comes from reading the code; each symptom follows from it.

## Where the defect is

The FFI vendors MapLibre Native at `third_party/maplibre-native/` in `/Users/dgreen/git/maplibre-native-ffi`, at commit `254d0a872407c15e9ea4211691af0abeb7e18f16`. The namespace and source directory are `mln`. On 2026-10-24 upstream `main` had the same `src/mln/renderer/source_state.cpp` as the vendored copy.

`SourceFeatureState` (`src/mln/renderer/source_state.cpp`, `source_state.hpp`) keeps three maps from source-layer ID to feature ID to state: `currentStates`, the state that the tiles have; `stateChanges`, changes queued by `updateState`; and `deletedStates`, removals queued by `removeState`. In `deletedStates`, an empty map for a source layer means "remove all state of the source layer", and an empty state for a feature means "remove all state of the feature". `RenderTileSource::prepare` (`src/mln/renderer/sources/render_tile_source.cpp`) calls `coalesceChanges` once per prepare, which folds the queues into `currentStates` and passes a `LayerFeatureStates changes` map to every tile. `GeometryTile::setFeatureState` (`src/mln/tile/geometry_tile.cpp`) updates the buckets only for the features that `changes` lists under their source layer.

### 1. The removal loop replaces the source layer's changes

```cpp
    for (const auto& layerStatesEntry : stateChanges) {
        ...
        changes[sourceLayer] = std::move(layerStates);      // e.g. {P: {selected: true}}
    }

    for (const auto& layerStatesEntry : deletedStates) {
        const auto& sourceLayer = layerStatesEntry.first;
        FeatureStates layerStates = {{}, {}};
        ...
        changes[sourceLayer] = std::move(layerStates);      // e.g. {B: {}}, replaces P's entry
    }

    stateChanges.clear();
    deletedStates.clear();

    changes.insert(currentStates.begin(), currentStates.end());  // insert doesn't replace B's entry
```

When both queues have entries for one source layer, the second loop assigns `changes[sourceLayer]` and discards the entries that the first loop computed. `changes.insert(currentStates...)` then adds only source layers that `changes` doesn't have, so it doesn't restore them. The tiles get the removal and not the change. `currentStates` has the change, so it reaches the tiles in a later `coalesceChanges` that has changes in another source layer only, through the `insert`; that is the delayed highlight.

`FeatureStates layerStates = {{}, {}};` also initializes the map with one entry, the feature ID `""` with an empty state. It is harmless for tiles that have no feature with an empty ID, but it isn't intended.

### 2. A removal after a change of one feature wins, whatever the call order

`updateState` adds to `stateChanges` and doesn't remove the same keys from `deletedStates`. `coalesceChanges` applies all of `stateChanges` and then all of `deletedStates`. So for one feature and key, a removal queued before a change in the same render still removes the key, although the change was called last.

### 3. `removeState` drops a key removal when the source layer already has a removal queued

```cpp
    if (stateKey && featureID) {
        if (!deletedStates.contains(sourceLayer) && !deletedStates[sourceLayer].contains(*featureID)) {
            deletedStates[sourceLayer][*featureID][*stateKey] = {};
        }
    }
```

The condition requires that the source layer has no queued removal at all, so a second key removal in one source layer before a render is dropped. The intent is likely to skip only when the source layer or the feature is already queued for removal of all its state.

## Proposed fix

Make the queued operations apply in call order, and build `changes` from both queues without replacing entries:

- In `updateState`, erase the changed keys from `deletedStates[sourceLayer][featureID]` (when that entry exists and isn't an "all state" marker), so that a later change cancels an earlier removal of the same key. When the entry is an "all state" marker for the feature or the source layer, apply the removal to `currentStates` first or record the order; the simplest correct design keeps one ordered queue of operations and applies it in order in `coalesceChanges`.
- In `removeState`, erase the removed keys, or the feature, or the source layer, from `stateChanges`, so that a later removal cancels an earlier change.
- In `coalesceChanges`, merge into `changes[sourceLayer]` instead of assigning it, and start `layerStates` empty.
- In `removeState`, fix the condition of the key branch to skip only when the source layer has an "all state" marker (already handled by `sourceLayerDeleted`) or the feature has one.

Check how MapLibre GL JS implements `SourceFeatureState` (`src/source/source_state.ts`) before choosing; it has the same three maps, and matching its semantics keeps the platforms consistent.

## Tests

The render tests in `metrics/integration/render-tests/feature-state/` and `remove-feature-state/` put a `["wait"]` operation between `setFeatureState` and `removeFeatureState`, so each operation gets its own render, and none covers two operations before one render.

- Unit tests for `SourceFeatureState`: queue the operations, call `coalesceChanges` with a recording tile or inspect `currentStates` and the `changes` map, and check:
  - remove key of B, set key of P (same source layer): `changes` has both B without the key and P with it;
  - remove key of B, set key of B: B has the key;
  - set key of B, remove key of B: B doesn't have the key;
  - remove key of B, remove key of C (same source layer): both removals are applied;
  - remove all state of the source layer, then set key of P: P has the key and no other feature has state.
- A render test like `remove-feature-state/vector-source` with two features of one source layer, whose operations are `removeFeatureState` of one and `setFeatureState` of the other without a `wait` between them, and an expected image that shows the second feature in its changed color.
- `test/map/map.test.cpp` has `TEST(Map, FeatureStateChangesRenderedStyle)`, which exercises set, render and remove; a variant that sets and removes before one render covers the full path through the renderer.

## What Mapigrade does until the fix is released

- The demo's inspect screen deselects with `setFeatureState(selected: false)` instead of `removeFeatureState`, so a selection change queues only changes, which `coalesceChanges` merges correctly (design D193 of `add-demo-showcases`).
- `LayerController.removeFeatureState` passes removals to the FFI's `mln_map_remove_feature_state` without delay, so an application that removes and sets state in one source layer before the next render gets the defect. The `feature-query` spec (requirement "Feature state") states that a later displayed map frame shows the effect of each change; a separate Mapigrade change states this limitation in the spec and in the doc comments of `removeFeatureState`, together with the correction of the query result order.
- The fix reaches Mapigrade when an FFI release that vendors a MapLibre Native commit with the fix is pinned in `packages/flutter_mapigrade/maplibre_ffi.lock`.
