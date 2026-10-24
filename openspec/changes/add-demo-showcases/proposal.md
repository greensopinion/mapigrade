## Why

The demo has one screen, built around the flyover that `tool/record_readme.sh` records for the README. We want the demo to also show the package's other user-visible features as they are added, starting with feature queries and feature state from `add-feature-queries`, so that a developer can try them and we can test them by hand. Adding each feature to the flyover screen would couple it to the flyover's input handling and to the recording, which depends on the same camera and overlays at the same time in every run.

## What Changes

- The demo opens at a gallery that lists its showcases, each with a title and a sentence that states what to try. Choosing one opens its screen, which has its own map; going back to the gallery disposes that map.
- The flyover screen is the first showcase. It keeps the styles, overlays, metrics, camera readout, flyover and attribution that the demo has now, and adds a control to go back to the gallery.
- In the recording mode the demo opens the flyover screen without the gallery and without the control to go back, so the recording and `tool/record_readme.sh` stay as they are.
- A new showcase, "Inspect features": a tap on the map queries the features at the tap and highlights the topmost one with feature state. A panel states the style layer that draws it, and its source ID, source-layer ID, ID and properties. A tap where the map draws no feature clears the highlight and the panel. The screen offers the four styles that the demo has now, with highlight layers that the demo adds to each style.
- Each screen has its own style choice.

Non-goals:

- No themes showcase in this change. We plan it as the next change.
- No showcase for settings that a user of an app doesn't see: HTTP headers, alignment, and the tile cache size stay out of the demo.
- No launch option that opens one showcase directly.
- No change to the package, the example or the test harness.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `demo-app`: adds the gallery and the "Inspect features" showcase; the styles, metrics, overlays, flyover and camera readout become requirements of the flyover screen; the recording mode opens the flyover screen directly.

## Impact

- Demo code: `packages/demo/lib/`. `main.dart` shows the gallery; the current `MapScreen` moves to the flyover screen; new code for the gallery, the inspect screen and its style patch; the style picker and attribution become widgets that both screens use. New tests in `packages/demo/test/` for the style patch.
- Dependencies: none. The demo fetches style JSON with `dart:io`'s `HttpClient`.
- Network: the inspect screen fetches each style's JSON itself before it gives it to the layer, from the same hosts the demo uses now.
- Assumption: features in OpenFreeMap's and the MapLibre demo tiles' vector tiles have IDs. If a style's features have none, the inspect screen can't highlight them; design.md states the fallback.
- MapLibre Native returns the features of several layers in hash order, not in style order, so the inspect screen queries each style layer and orders the results itself. `docs/maplibre-query-result-order.md` describes the defect for an upstream fix, which is separate from this change. The `feature-query` spec and the `queryRenderedFeatures` docs state the order that MapLibre doesn't give; a separate change corrects them.
- MapLibre Native loses a feature state change when a removal in the same source layer reaches the same render, so the inspect screen deselects by setting `selected: false`. `docs/maplibre-feature-state-coalescing.md` describes the defect for an upstream fix, which is separate from this change; the separate change that corrects the `feature-query` spec also states this limitation.
- MapLibre Native returns no feature state for features of symbol layers, so the inspect screen states that for labels and icons. `docs/maplibre-symbol-query-feature-state.md` describes the defect for an upstream fix; the separate `feature-query` change also states this limitation.
- Documentation: `packages/demo/README.md` (the gallery and the inspect screen), and the demo's line in the layout in `CONTRIBUTING.md`.
- Recording: `tool/record_readme.sh` and the video don't change.
