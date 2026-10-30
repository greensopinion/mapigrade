## Context

See proposal.md for motivation, and `specs/polyline-layer/spec.md` for the required behavior.

The FFI functions this change uses are in `style.h` of the pinned release 0.202610.2:

- `mln_geojson_source_data_create` parses and tiles UTF-8 GeoJSON into a prepared index. It runs on any thread and touches no map, and the handle can be destroyed after it is installed.
- `mln_map_add_geojson_source_data` and `mln_map_set_geojson_source_data` install prepared data; `mln_map_remove_style_source` removes a source.
- `mln_map_add_style_layer_json` adds a layer before an existing layer ID, or on top when the ID is empty; `mln_map_move_style_layer` and `mln_map_remove_style_layer` move and remove layers.
- `mln_map_list_style_layers` reports every layer's ID and type in style order.

In this release all of these are commands or queries: each returns once accepted, applies on the map owner thread during a later `mln_render_session_service_driver_work` call, and reports its result through an `mln_completion`, as feature state does today (`ApplyFeatureState` in `map_texture.cpp`).

Every call from Dart to the native core is a command in `CommandQueue` that the map thread applies at the start of `RunOnce`, before it renders. The runtime calls `MapTexture::OnEvents`, which receives `MLN_RUNTIME_EVENT_MAP_STYLE_LOADED`, on its scheduler thread, not on the map thread. A style load removes every source and layer that was added at runtime.

`MapTextureLayer` builds its `children` in a `Stack` under its own `MapInheritedModel`, and builds them again in each Flutter frame in which it chooses a map frame. The child widgets themselves don't change, so a child that doesn't depend on `MapCamera` isn't rebuilt when the camera moves. `MapTextureLayer` creates its `MapTextureController` asynchronously, after its first build.

## Goals / Non-Goals

**Goals:**
- One widget is one GeoJSON source plus the style layers it needs, so that an application controls how much of the data a change sends again by splitting polylines across widgets.
- Changing only properties that MapLibre evaluates per feature (`points`, `color`, widths, border, join) sends new data and no layer changes.
- Below the polyline translation, no Dart or native code refers to lines, so a later polygon or circle layer adds only its model and translation.

**Non-Goals:**
- Synchronous tiling. A data change can appear a frame or more after the widget is rebuilt; MapLibre keeps the old tiles until the new ones are ready, so nothing flickers.
- A binary geometry format. The FFI takes GeoJSON as UTF-8 bytes.
- Matching `flutter_map`'s alpha compositing of overlapping translucent polylines. `flutter_map` composites a batch through a saved layer, so two translucent polylines in a batch don't darken where they overlap; MapLibre blends each feature, so they do.

## Decisions

### D195: Public API

```dart
final class MapigradePolylineLayer extends StatefulWidget {
  const MapigradePolylineLayer({super.key, required this.polylines,
      this.placement = const LayerPlacement.belowLabels()});
  final List<MapigradePolyline> polylines;
  final LayerPlacement placement;
}

@immutable
final class MapigradePolyline {
  const MapigradePolyline({required this.points, this.strokeWidth = 1.0,
      this.color = const Color(0xFF00FF00), this.borderStrokeWidth = 0.0,
      this.borderColor = const Color(0xFFFFFF00), this.strokeCap = StrokeCap.round,
      this.strokeJoin = StrokeJoin.round, this.useStrokeWidthInMeter = false,
      this.dashes, this.gradientColors, this.gradientStops});
  factory MapigradePolyline.fromPolyline(Polyline polyline);
  // fields as in the spec; ==, hashCode
}

final class LayerPlacement {
  const LayerPlacement.belowLabels();
  const LayerPlacement.belowLayer(String id);
  const LayerPlacement.top();
}
```

The model keeps `flutter_map`'s field names, types and defaults for the properties it shares with `Polyline`, so that code that builds `Polyline` values compiles after the class name is changed, unless it uses a field that MapLibre can't draw. Those fields don't exist on the model, so using one is a compile error at the call site.

`dashes` is in multiples of the line's width, which is MapLibre's unit for `line-dasharray`. With pixel lengths, a dash pattern on a line whose width is in meters would need a different dash array at each zoom level, and `line-dasharray` can't vary by zoom per feature. `gradientColors` keeps `flutter_map`'s name, but `gradientStops` replaces `colorsStop`, because the stops mean positions along the line, and a renamed parameter makes a converted call site fail to compile instead of changing meaning without notice.

`LayerPlacement` doesn't name polylines, so that later polygon and circle layers take the same type. Its name starts with `Layer`, as `LayerAlignment` does; the naming rule forbids exported names that start with `Polyline`.

Alternatives considered:
- Reusing `flutter_map`'s `Polyline`. Rejected: its gradient, `PatternFit`, `hitValue` and the layer's culling and simplification parameters would have no effect.
- The same names as `flutter_map` (`Polyline`, `PolylineLayer`), so that an import with `hide` switches between them. Rejected: every file that uses polylines would need `hide` or a prefix permanently, a reader couldn't tell from a call site which layer it is, and the naming rule's scenario "Application imports without hiding names" would fail.
- Cap and dashes as layer properties instead of polyline properties, because MapLibre can't vary them per feature. Rejected: the layer groups runs internally (D197), and the extra style layers cost no more than the same polylines in several widgets.

### D196: Equality and change detection

`MapigradePolyline.==` compares `points` with `identical` first and then element by element, then the other fields; `hashCode` is computed once and cached, as `flutter_map` does. `didUpdateWidget` compares the old and new `polylines` with `identical`, then with `listEquals`. An application that builds new `MapigradePolyline` values from the same points in each `build` therefore sends nothing; one that keeps its points list sends nothing at the cost of an identity check per polyline.

When the lists differ, the layer compares the run structure (D197) of the old and new lists. If the run structure is the same, it sends only new GeoJSON data; otherwise it also sends new layer JSON.

### D197: Translation to GeoJSON and line layers

The only polyline-specific code is the translation from a list of `MapigradePolyline` values to one GeoJSON `FeatureCollection` and a list of style layer JSON objects. Each polyline with at least two points becomes a `LineString` feature. Longitudes are unwrapped so that each step between consecutive points is at most 180 degrees, which MapLibre's GeoJSON tiling accepts, and which gives the shorter way around the world that `flutter_map` draws by default.

Feature properties carry everything MapLibre evaluates per feature:

| Property | Value |
|---|---|
| `i` | index in the list; `line-sort-key`, so the list order holds within a style layer |
| `r` | run index; the layer filter |
| `c`, `bc` | `color` and `borderColor` as `rgba(...)` strings |
| `w0`, `w24` | the line width at MapLibre zoom 0 and 24 |
| `b` | `borderStrokeWidth / 2` |
| `j` | `strokeJoin` as `miter`, `round` or `bevel` |

`line-width` is `["interpolate", ["exponential", 2], ["zoom"], 0, ["get", "w0"], 24, ["get", "w24"]]`. A width in logical pixels has `w0 == w24`. A width in meters has `w0 = meters * 512 / (40075016.686 * cos(latitude of the first point))` and `w24 = w0 * 2^24`, because at MapLibre zoom `z` the world is `512 * 2^z` logical pixels wide, the same as `flutter_map`'s `256 * 2^(z + 1)`. Data-driven values inside the stops of a zoom `interpolate` are allowed, which a `case` around the zoom expression isn't.

A run is a maximal sequence of consecutive polylines with the same `strokeCap` and `dashes` and no gradient; each polyline with a gradient is a run of its own. `line-cap`, `line-dasharray` and `line-gradient` can't vary per feature, so each run gets two style layers with the filter `["==", ["get", "r"], k]`, drawn in run order:

- the border: `line-gap-width` from the same `w0`/`w24` interpolation, `line-width` from `b`, `line-color` from `bc`. A line with a gap draws two strokes, one on each side of the gap, so a translucent line never shows its border through it, as `flutter_map`'s `dstOut` pass achieves.
- the line: `line-width`, `line-color` from `c` (or `line-gradient` with `["line-progress"]` stops), `line-join` from `j`, `line-cap` and `line-dasharray` from the run.

The source sets `line_metrics`, which `line-gradient` requires, always: the source options are fixed when the source is added, and recreating the source when the first gradient appears would cost more than the per-vertex distances.

Alternative considered: one style layer pair per polyline. Rejected because the number of style layers would grow with the number of polylines for the common case, in which all polylines share a cap and dashes.

### D198: Overlays, the geometry-independent part

Below the translation, a widget is an overlay: an ID, one GeoJSON document, a list of style layer JSON objects that use the overlay's source, a placement, and an order key (D200). The overlay doesn't know the geometry or the layer types.

Dart: `MapTextureLayer` provides an internal `OverlayHost` through an `InheritedWidget` around its children. `MapigradePolylineLayer` registers an overlay with the nearest host in `initState`, updates it in `didUpdateWidget`, and removes it in `dispose`. The host keeps the overlays while the map doesn't exist and sends them all when `MapTextureController` is created. Without a host, the widget fails the spec's assertion.

C ABI, in `map_texture_api.h`:

```c
int32_t map_texture_overlay_set_data(int64_t handle, int64_t overlay_id,
    const uint8_t* geojson, int64_t length);
int32_t map_texture_overlay_set_layers(int64_t handle, int64_t overlay_id,
    const char* layers_json, int32_t placement_kind, const char* below_layer_id,
    int64_t order_child, int64_t order_seq);
int32_t map_texture_overlay_remove(int64_t handle, int64_t overlay_id);
```

`set_data` calls `mln_geojson_source_data_create` on the calling thread, then queues a command with the prepared handle; invalid GeoJSON returns a failure status with the FFI's diagnostic. The overlay's source ID is `mapigrade-overlay-<id>`, and its layers' IDs are `mapigrade-overlay-<id>-<n>`; Dart writes the source ID into each layer's JSON. The prefix `mapigrade-` is reserved: placement ignores layers with it when it looks for the last non-symbol layer.

Alternative considered: keeping the overlays only in Dart, and sending them again after each style-loaded event. Rejected because the event reaches Dart through the event port after the map thread has continued, so the map would render frames of the new style without the polylines, and Dart would also have to resend data it has already prepared.

### D199: Placement on the map thread

The map thread keeps, for each overlay, the prepared data handle, the layer JSON, the placement and the order key. Installing overlays starts with `mln_map_list_style_layers`. From the list it computes each placement's anchor, the ID of the layer that the overlay's layers are added before:

- `belowLabels`: the layer after the last layer whose type isn't `symbol` and whose ID doesn't start with `mapigrade-`, or the first layer when there is none, or empty (top) when that layer is the last;
- `belowLayer(id)`: `id`, or empty with a load-failure event naming `id` when the list doesn't contain it;
- `top`: empty.

Overlays with the same anchor are added in increasing order key, each before the anchor, so a later overlay ends up above an earlier one. An overlay added later, or whose order changed, is added before the first layer of the next overlay at the same anchor in order, or before the anchor when there is none. A placement change removes and adds the overlay's layers again; a data change only calls `mln_map_set_geojson_source_data`.

In the style of OpenFreeMap Liberty, the anchor of `belowLabels` is the layer after `boundary_disputed` (index 87), so routes are above the 25 bridge layers that follow the first symbol layer `road_one_way_arrow` (index 61). "Below the first symbol layer" was rejected because it would put routes under every bridge in that style.

### D200: Order key from the position in the children

`MapTextureLayer` wraps each child in an internal `InheritedWidget` that holds the child's index. A polyline layer reads the index of its nearest wrapper as the first part of its order key, and the host assigns a sequence number at registration as the second part. When the application reorders or inserts children, the wrappers' indexes change, the dependent polyline layers update their order key, and the map thread moves their layers (D199).

Alternative considered: registration order only. Rejected because a child inserted before an existing polyline layer would register later and be drawn above it, which contradicts the spec's scenario "Child inserted before an existing polyline layer".

### D201: Style loads

`OnEvents` sets an atomic flag on `MLN_RUNTIME_EVENT_MAP_STYLE_LOADED` and wakes the map thread. `RunOnce` checks the flag after `ApplyCommands` and again before `MaybeRender`, and installs every overlay as D199 describes, adding each source from its retained prepared data. Commands from Dart that arrive between the style load and the install change only the kept state, which the install then uses.

### D202: Encoding off the UI isolate

The polyline layer encodes the GeoJSON with a `StringBuffer`, not `jsonEncode` of nested maps, and converts it to UTF-8 bytes. When the polylines have more than 20,000 points in total, the encoding and the `map_texture_overlay_set_data` call run together in `Isolate.run`, so that both the encoding and MapLibre's parsing and tiling run on a background isolate's thread. An update that arrives while one is running replaces the queued one; only the newest data is sent, and data sent for an overlay is never older than data sent before it. The 20,000-point threshold is a starting value for the implementation to adjust from measurement.

### D203: Failures

A failure status from `map_texture_overlay_set_data`, or a failed completion of an FFI command for an overlay, is reported as a `LayerRenderException` that names the operation, as feature-state failures are. A missing `belowLayer` ID is a load failure (`LayerLoadException`), reported once for each style load, through the load-failure event that the layer already deduplicates.

## Risks / Trade-offs

- [The install after a style load uses three FFI round trips: list, add sources, add layers; the map may render one or more frames of the new style without polylines] → An integration test samples the frames after a style change and records how many lack the polylines. The spec requires the polylines with the new style, not in its first frame.
- [Feature order within a style layer might not follow `line-sort-key` across tile boundaries] → The draw-order integration tests cover lines that cross tile boundaries.
- [MapLibre clips a line's width at tile edges with the tile buffer of 128 pixels; very wide lines could show seams] → Widths above 128 logical pixels are rare for routes; the documentation states the limit if the test shows seams.
- [GeoJSON encoding and tiling time grows with the number of points; very long tracks may take long enough for the update to visibly lag] → D202 moves both off the UI isolate. Applications split static and changing polylines across widgets.
- [The run structure turns into one style layer pair per polyline when polylines with different caps or dashes alternate in the list] → The documentation asks applications to keep polylines with the same cap and dashes next to each other.

## Migration Plan

The change only adds API. Applications switch from `PolylineLayer` and `Polyline` to `MapigradePolylineLayer` and `MapigradePolyline`, or convert an existing list with `MapigradePolyline.fromPolyline`.
