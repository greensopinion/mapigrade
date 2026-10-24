## Context

See proposal.md for motivation, and `specs/feature-query/spec.md` for the required behavior.

The FFI functions this change uses, in the pinned release 0.202610.2, are `mln_render_session_query_rendered_features` (`query.h`), and `mln_map_set_feature_state` and `mln_map_remove_feature_state` (`map.h`). All three are asynchronous: they copy their inputs, return, and later report the result through an `mln_completion`. Mapigrade attaches its session with the caller driver (`MLN_RENDER_DRIVER_CALLER_GRAPHICS_THREAD`), so a query runs during a later `mln_render_session_service_driver_work` call on the map thread, and reads the last frame that the session had rendered when it runs. Every call from Dart to the native core so far is a command: it queues work for the map thread and returns. Results reach Dart only as events, through the `NativeCallable.listener` that `map_texture_controller_ffi.dart` creates.

A rendered query doesn't run against the camera that Dart set last. mbgl's `RenderOrchestrator::queryRenderedFeatures` projects the query geometry with its `transformState`, which the last render update set. Three cameras are involved:

```
 A  live flutter_map camera        what MapOptions.onTap uses for its LatLng
 B  camera of the displayed frame  what the user sees and taps;
                                   the layer's children are drawn at it
 C  camera of the last rendered    what MapLibre projects the query with
    frame
```

While the camera moves, C is ahead of B: with camera prediction by design, and while rendering ahead by up to the number of display slots in use. Only the map thread knows C at the moment the query runs, because another render can run between Dart sending the query and the map thread dequeuing it.

Symbol features are an exception. mbgl matches them against the collision index of its last symbol placement, which it updates only once per placement period (about 300 ms) while the camera moves, so their hit areas can be behind both B and C.

## Goals / Non-Goals

**Goals:**
- A query at a screen position that the user sees returns the non-symbol features drawn there, within 1 logical pixel, while the camera moves.
- Query and feature state use the map thread's existing command path, without a second channel to Dart.

**Non-Goals:**
- Correcting symbol hit areas for placement lag. This is mbgl behavior, and the docs state it.
- Typed geometry (`LatLng` lists) on `QueriedFeature`. It can be added later as a getter without breaking the decoded GeoJSON.
- Reporting which style layer drew a feature. Neither mbgl nor the FFI returns it; applications query once per group of layer IDs instead.

## Decisions

### Public API

`LayerController` is a `final class` with a public no-argument constructor. `MapigradeLayer` and `MapTextureLayer` take an optional `controller`. The layer's state attaches the controller when it has created its map, and detaches it in `dispose` and when it is rebuilt with another controller.

```dart
Future<List<QueriedFeature>> queryRenderedFeatures(Offset point,
    {double radius = 8, List<String>? layerIds, Object? filter});
Future<List<QueriedFeature>> queryRenderedFeaturesInRect(Rect rect,
    {List<String>? layerIds, Object? filter});
void setFeatureState({required String sourceId, String? sourceLayerId,
    required Object? id, required Map<String, Object?> state});
void removeFeatureState({required String sourceId, String? sourceLayerId,
    Object? id, String? key});
```

The method names follow MapLibre's `queryRenderedFeatures`, which application developers know from the other MapLibre SDKs. `id` is `Object?` on `setFeatureState` so that the call checks it and can name `promoteId` in its error; a non-nullable parameter would push the null check to every call site.

Alternative considered: a callback such as `onFeatureTap` on the layer. Rejected because the layer would have to recognize taps, which competes with `flutter_map`'s gesture handling, and because it doesn't serve queries that don't come from a tap.

### Converting the query position: Dart to geographic, map thread to screen

The conversion is split at the geographic position:

```
 query rectangle (logical px, flutter_map widget)
   | Dart: 4 corners -> worldPosition(camera B, corner)        normalized Mercator
   v
 map thread, when it dequeues the query:
   | screenPosition(camera C, world) for each corner
   | axis-aligned bounds of the 4 points                     -> mln_screen_box
   v
 mln_render_session_query_rendered_features
```

A point query is the rectangle of side `2 * radius` centered on the point. Dart takes camera B from `ViewCamera.ofFrame(selectedFrame)`, the camera that the displayed frame was rendered with; before the first displayed frame it takes `viewCameraOf(live)`. `camera_projection.dart` already has `worldPosition`, and its tests cover it. The map thread uses the same formulas, ported to C++. The camera has no pitch, so the conversion is a translation, a scale by 2^(zoom C − zoom B) and a rotation by the bearing difference.

When B and C differ in bearing, the four converted corners form a rotated rectangle. The FFI box is axis-aligned, so the map thread queries the bounds of the four corners. For a tap radius of a few pixels and a bearing difference of a fraction of a degree, the bounds cover at most a fraction of a pixel more.

Before converting, the map thread wraps each corner's Mercator x into the half world closest to camera C's center, so that a query near the antimeridian doesn't convert to a point one world width away.

Alternatives considered:
- Converting with camera A in Dart only (or using `onTap`'s `LatLng`). Wrong by the full lag while the camera moves.
- Converting with camera B in Dart and querying in B's screen space. Wrong whenever C is ahead of B, which is the case on every frame that renders ahead or with prediction.
- Converting on the map thread with the FFI's map-level pixel conversion. That uses the map's current transform, which is newer than C between `ApplyCamera` and the next render. Using the camera of the last rendered frame doesn't depend on the order in which the map thread applies commands.

### Camera C on the map thread

The map thread keeps the camera and logical viewport size of the last frame it rendered, taken from `RenderedFrameInfo` when it handles the frame result.

The query's geometry is fixed when it is submitted, but the query runs in a later service call, and any service call can render the armed demand's frame first. The map thread therefore makes sure that no frame renders between the conversion and the query:

```
 RunOnce: ApplyCommands -> ApplyCamera -> ServiceDriver (frame results handled)
          -> RunQueries:
               if queries are pending:
                 EndDemands()                  barrier: no armed demand can render
                 for each query: convert with camera C, submit
                 ServiceUntil(all completed)
          -> MaybeRender (arms the next demand) -> ServiceDriver
```

Queries go into their own queue instead of the command queue, so that the map thread runs them after the frame results of the same iteration are handled. A batch costs one barrier and one service round. Queries come from taps, so this happens rarely, and the barrier delays the next render by at most that round.

Alternatives considered:
- Submitting without ending demands, and resubmitting with a new conversion when a frame rendered between submission and completion. Rendering continues during the query, but it needs a retry loop and discards the work of every query that ran against the wrong frame.
- Submitting without ending demands and accepting that a query can use a frame one render newer than the conversion. This breaks the 1-pixel alignment during a pan that the spec requires.

Task 1.3 tests that a query submitted while a demand is armed uses the last rendered frame, and task 3.3 tests the whole path with a query on a line during a pan.

### C ABI: a request ID and a result event

```c
int32_t map_texture_query_rendered_features(
    int64_t handle, int64_t request_id,
    const double* world_corners,          // 4 points, x then y, normalized Mercator
    const char* const* layer_ids, int32_t layer_id_count,   // null: all layers
    const char* filter_json);             // null: no filter
int32_t map_texture_set_feature_state(int64_t handle, const char* source_id,
    const char* source_layer_id, const char* feature_id, const char* state_json);
int32_t map_texture_remove_feature_state(int64_t handle, const char* source_id,
    const char* source_layer_id, const char* feature_id, const char* key);
```

The map thread answers each query with one new event, `MAP_TEXTURE_EVENT_QUERY_RESULT`, which carries the request ID in a new `request_id` field and a status. On success, `message` is a JSON array:

```json
[{"feature": <GeoJSON Feature from the FFI>, "source": "...", "sourceLayer": "...", "state": {...}}, ...]
```

The query's completion builds the array by concatenating the FFI's feature and state buffers, which are already JSON, with the escaped source IDs, so it parses no JSON. The completion must copy them, because the FFI's views are valid only during the callback. On failure, `message` is the FFI's diagnostic. When the map has no attached session (before the first resize, or while an Android activity is stopped), when the submission returns `MLN_STATUS_INVALID_STATE`, or when the query completes with `MLN_STATUS_TARGET_LOST`, the result is an empty array, because the map renders no features then.

Alternatives considered: a `NativeCallable` per query, which costs a callable per call and must be closed on every path; and `Dart_PostCObject` to a `ReceivePort`, which needs the `dart_api_dl` dependency in the native core. The existing event callback already crosses threads correctly and is closed at dispose.

### Feature state as commands

`setFeatureState` and `removeFeatureState` validate their arguments in Dart, convert the ID to the FFI's string `feature_id` (an `int` and an integral `double` give the same decimal string; a `String` is used as it is), encode the state with `jsonEncode`, and queue a command. They return without waiting, like `setCamera`. The map thread submits the FFI command with a `ReportingCompletion`, so that a failure is reported rather than only logged. A failure after Dart's checks can only be an internal error; the layer reports it through its failure handler as a `LayerRenderException` that names the operation. Feature-state commands stay in the ordered command queue, so a set followed by a query applies before the query runs. A query returns the feature state of the last rendered frame, and state reaches the renderer only with the next render update. The map thread therefore holds queries until every feature-state command submitted before them has completed and a frame has rendered with its `render_update_generation`. The command requests a repaint, so the wait is one frame.

Feature state persists across a style change, and mapigrade does nothing to make it so. The FFI keeps feature state in a store on the map, which a style load doesn't clear. When a render update finds a source in that store that it hasn't rendered before, the FFI renders once without presenting and then pushes the stored state into the source. A new style with the same source ID therefore gets the state back.

Alternative considered: clearing feature state on each style load. The FFI has no call that clears all state, so mapigrade would have to track the sources it set state on and remove each one. It would also lose a selection when the application switches between styles that share their sources, such as light and dark variants.

### Decoding and completion order

The Dart controller keeps a FIFO of pending queries keyed by request ID. A result whose message is smaller than 64 KiB is decoded on the UI isolate; a larger one with `Isolate.run`. Because an `Isolate.run` decode can finish after a later small decode, each query's `Future` completes only after the previous query's has, so that queries complete in call order. At dispose, every pending query completes with a `StateError`.

## Risks / Trade-offs

- [Camera C isn't the camera of the frame the query reads, for example because a service call rendered after the barrier] → The native test in task 1.3 and the pan tests in task 3.3 fail by the distance the camera moved, so the cause shows up before release.
- [Symbol hit areas lag while the camera moves] → Documented on the query methods. Taps usually happen at rest, when placement has caught up.
- [The tapped position is outside camera C's viewport during a fast fling with rendering ahead, so the rendered query misses features that the user saw] → Rare, because a tap stops a `flutter_map` fling at pointer down. Documented.
- [A query batch ends the armed demand and delays the next render by one barrier and one service round] → Queries come from taps and are rare; the frame-rate benchmark isn't affected, because it doesn't query.
- [Large rectangle queries return several MB of JSON] → Decoded off the UI isolate. The map thread builds the string once, and Dart frees it after decoding.
- [`uint64` feature IDs above 2^63 decode as `double` in Dart and lose precision, so `setFeatureState` with such an ID selects a different feature] → Documented on `QueriedFeature.id`. Such IDs are rare in tilesets.
- [Feature state does nothing unless the style reads it, and features without IDs can't take state] → The docs of `setFeatureState` show a `feature-state` paint expression and name `promoteId`.
- [State set for one style applies to an unrelated source of a later style that reuses the source ID] → Documented on the feature-state methods; an application that doesn't want this removes the state before it changes the style.
