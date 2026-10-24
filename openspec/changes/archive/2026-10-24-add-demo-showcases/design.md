## Context

See proposal.md for motivation, and `specs/demo-app/spec.md` for the required behavior.

The demo has one screen, `MapScreen` in `packages/demo/lib/src/map_screen.dart`. Its state owns the flyover player, the recording mode, the style choice, the stage overlays and the metrics. Any pointer-down or map event that the `MapController` didn't cause stops the flyover. The recording mode (designs D144 to D147) depends on the flyover screen filling the 1280 × 720 window, because the flyover's camera is a function of the viewport size.

`MapigradeLayer` takes exactly one of `styleUrl` and `styleJson`. The package has no API that adds a style layer at run time, so the demo can only draw a highlight that the style it gives the layer contains. MapLibre style filters can't read feature state; only paint and layout expressions can.

## Goals / Non-Goals

**Goals:**
- Adding a showcase means a new folder under `lib/src/` and one gallery entry, without a change to the flyover screen.
- The flyover screen and the recording behave as they do now.

**Non-Goals:**
- Sharing state between screens. The screens share widgets only.
- Restyling the selected label itself. The highlight marks its point with a circle.

## Decisions

### D190: Gallery with one route per showcase

`main.dart` shows a gallery: a list of entries, each with a title, a sentence and a builder for its screen. Choosing an entry pushes the screen with a `MaterialPageRoute`. Popping the route disposes the screen and its map, and the platform's back navigation pops it without extra code.

```
 DemoApp
   |-- isSupported == false --> unsupported statement
   |-- recording mode -------> FlyoverScreen(recording, canGoBack: false)
   `-- otherwise ------------> Gallery
                                 |-- push --> FlyoverScreen
                                 `-- push --> InspectScreen
```

Each screen draws its back control as an icon button in its panel's header, not in an `AppBar`. The map then keeps the whole window, as it does now, and the flyover's camera for a viewport size doesn't change.

Alternatives considered: a navigation bar, which keeps every screen's map alive in an `IndexedStack` or rebuilds it on every switch; a drawer, which hides the list of showcases behind a menu. We chose the gallery in exploration.

### D191: Code layout

```
 lib/main.dart                  DemoApp, gallery entries, recording check
 lib/src/gallery.dart           the gallery widget
 lib/src/common/                styles and attribution (styles.dart), the
                                style picker, the panel card with its header
 lib/src/flyover/               flyover_screen.dart (the former MapScreen),
                                flyover.dart, flyover_player.dart,
                                stage_layers.dart, stages.dart,
                                metrics_panel.dart, rates.dart, recording.dart
 lib/src/inspect/               inspect_screen.dart, style_patch.dart,
                                feature_panel.dart
```

`MapScreen` becomes `FlyoverScreen`, which takes the recording mode as a constructor parameter. The panel card shows the back control when its route can be popped; in the recording mode the flyover screen is the home route, so it has none. `main.dart` calls `Recording.fromEnvironment()` before `runApp`, so an invalid value still exits at launch. Tests move with their files.

### D192: Highlight layers through a style patch

The inspect screen fetches the style's JSON with `dart:io`'s `HttpClient`, passes it to a pure function that adds the highlight layers, and gives the result to the layer as `styleJson`.

For each distinct pair of source and source layer that the style's layers draw from, where the source is of type `vector` or `geojson`, the patch appends four layers after the style's own layers:

```
 mapigrade-highlight-<n>-fill     fill    geometry-type in [Polygon, MultiPolygon]
                                          fill-opacity: selected ? 0.35 : 0
 mapigrade-highlight-<n>-outline  line    geometry-type in [Polygon, MultiPolygon]
                                          line-width: 3, line-opacity: selected ? 1 : 0
 mapigrade-highlight-<n>-line     line    geometry-type in [LineString, MultiLineString]
                                          line-width: 6 at zoom 10 to 30 at zoom 20,
                                          line-opacity: selected ? 0.7 : 0
 mapigrade-highlight-<n>-circle   circle  geometry-type in [Point, MultiPoint]
                                          circle-radius: 10, circle-opacity: selected ? 0.9 : 0
```

`selected` stands for `['boolean', ['feature-state', 'selected'], false]`. Opacity carries the state because filters can't read feature state. Polygons and lines have separate line layers, so that a polygon gets a thin outline while a line's highlight is wider than Liberty's widest roads, about 20 px at zoom 20. All layers use one highlight color that differs from the flyover's magenta route and from the styles' main colors. The filters list both the single and the multi geometry types, because MapLibre versions differ in which one `geometry-type` returns for multi geometries.

Layers of type `raster`, `hillshade` and `background`, and sources of other types, get no highlight, because they have no features with IDs. Label features are points or lines in their source layer, so the circle or the line layer highlights them.

A style given as JSON has no base URL. The patch resolves relative `url`, `tiles`, `sprite` and `glyphs` values against the style's URL, so a style that uses relative URLs still loads. The four current styles use absolute URLs.

The screen keeps the patched JSON of each style it has fetched for as long as it is open, so choosing a style again doesn't fetch it again. Until the first style arrives, the screen shows a progress indicator in place of the map. On a later style change the layer keeps showing the current style until the new one arrives. The layer keeps its key, so the map, and with it the feature state, stays across style changes (D115).

Alternatives considered: drawing `QueriedFeature.geometry` as a `flutter_map` polygon or polyline in the layer's children. It works without IDs, but it doesn't show feature state, and the geometry is clipped to the tile it came from. We keep it as the fallback (see Risks).

### D193: Selection

MapLibre Native returns the features of several layers in hash order of their layer IDs, not in style order (`docs/upstream-fixes/maplibre-query-result-order.md`), so the first feature of one query isn't the topmost. The demo orders the results itself: the style patch also returns the IDs of the style's own layers that draw features (the layer types and source types of D192), topmost first, and which of them are symbol layers. On a tap, the screen uses `MapOptions.onTap` and sends one query per layer ID, with `layerIds: [id]`, `TapPosition.relative` and the default radius, all at once with `Future.wait`. The tap's hits are every feature of every result, in the order of the list, each with its layer ID. The selection is the first hit, or none. Choosing another hit in the panel selects it the same way, and the hits stay as they are until the next tap.

```
 tap --> one query per own layer, topmost first --> first non-empty result
           (Liberty: 109 queries)                     |
                    |-- none --------------> deselect previous; clear panel
                    |-- first.id == null --> deselect previous; panel + "no ID"
                    `-- first.id != null --> deselect previous;
                                             setFeatureState(selected: true); panel
```

The highlight layers aren't queried: they draw every feature of their source layer at opacity 0, so they would match the whole source layer above the style's own layers.

The demo deselects the previous feature with `setFeatureState(selected: false)`, not with `removeFeatureState`. A selection change sends a deselect and a select that reach MapLibre before the same render, and MapLibre Native's `SourceFeatureState::coalesceChanges` mishandles a removal together with a change in one source layer: the removal replaces that source layer's changes, so the new selection isn't shown, and a removal and a change of one feature leave it removed (`docs/upstream-fixes/maplibre-feature-state-coalescing.md`). Two changes merge correctly, and the later one wins for one feature. The highlight expression treats `false` as not selected, and the panel's State row shows `selected: false` for a feature that was selected before. Queries on one controller complete in the order they were called, so the results of one tap complete before those of the next, and the last tap's selection is applied last. A `LayerQueryException` shows its message in a snack bar and leaves the selection as it was. A style change doesn't touch the selection: the package keeps feature state across style changes.

Alternative considered: one query without `layerIds`, taking the first feature. Rejected because of the MapLibre Native order; it selected a park instead of a building inside it. When a fixed FFI release is pinned, the screen can return to one query, but the per-layer queries also give the layer ID, which the panel shows and which `QueriedFeature` doesn't report.

### D194: Feature panel

The panel is a card at the top left, like the flyover screen's, with the back control, the style picker, the statement that a tap selects the topmost feature, the selected feature, and the other hits of the tap:

```
 Style layer   building-3d
 Source        openmaptiles
 Source layer  building            ("none" for a GeoJSON source)
 ID            18503910
 Geometry      MultiPolygon, 655 polygons
 State         selected: true      (as the query returned it; "none" when empty)
 Properties    sorted by key
 ------------------------------------------
 Also at the tap
   park           park       171390273  >
```

Strings are shown as they are and other values with `jsonEncode`. The query that selects a feature runs before the demo sets its state, so after `setFeatureState` the screen queries the selected feature's layer again at the tap, finds the feature by source, source layer and ID, and replaces the selection and its entry in the hits with it. The package runs a query only after the frame that contains pending feature state (`MapTexture::RunQueries`), so this query returns `selected: true`; the panel thereby shows the state read back from the map, not the state the demo set. If the selection changes before the query completes, the screen ignores its result. MapLibre Native's `FeatureIndex::lookupSymbolFeatures` passes no feature state to the features it returns, so a feature of a symbol layer always has empty state (`docs/upstream-fixes/maplibre-symbol-query-feature-state.md`). The style patch also returns the IDs of the symbol layers, and for their features the State row states that MapLibre Native doesn't return feature state for labels and icons. The card scrolls when its content doesn't fit.

We added the geometry, the state and the list after comparing the panel with Maputnik's inspector, which shows `$type` and every feature under the cursor. The properties were already complete: OpenMapTiles keeps a road's name and ref in `transportation_name`, a label layer, not in `transportation`, so a road's line has no name. The list lets the developer select the label's feature where the tap hits it.

## Risks / Trade-offs

- [OpenFreeMap's tiles have no feature IDs] → The panel states that the feature has no ID, so the screen shows the problem rather than failing. If this happens for most features, a follow-up change chooses between `promoteId` on the source in the patch (it needs a property that is unique in the source layer) and the overlay highlight of D192.
- [One feature holds many buildings] → On 2026-10-24 we decoded OpenFreeMap tile 14/8522/5976 (central Nice): every feature of every layer has an ID and the IDs are unique in each layer, but its 43 `building` features have 4,066 polygons between them, the largest 655. The tiles merge buildings that have the same attributes into one multi-polygon feature, so a tap on a building highlights every polygon of that feature. The demo shows the data as it is: the panel states the geometry type and the number of parts, and the README explains the merge.
- [About 100 queries per tap] → They run on the map thread in one batch, and each one queries only one layer. If a tap doesn't feel immediate on the Pixel, the screen can query only the layers that draw at the current zoom.
- [Symbol hit areas lag while the camera moves] → This is MapLibre behavior that the `feature-query` spec states. A tap on a label during a fling can select the wrong feature or none.
- [A style's JSON changes upstream] → The patch reads only `sources` and `layers`, and the tests cover a fixture with each case the patch handles, so a new layer type gets no highlight rather than breaking the style.
- [4 × N extra layers, where N is the number of source layers] → Liberty has 14 source layers, so 56 layers that draw nothing unless a feature is selected. We expect no visible cost, and the screen doesn't show metrics.

## Migration Plan

The demo isn't published. Existing commands (`flutter run`, `tool/record_readme.sh`) keep working. A developer who opened the flyover at launch now chooses "Flyover" in the gallery first.
