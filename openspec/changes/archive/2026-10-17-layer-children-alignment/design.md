## Context

See proposal.md for motivation and scope, and the delta specs for the behavior: `specs/map-layer/spec.md` (requirement "Children aligned with the displayed map frame") and `specs/map-texture/spec.md` (requirement "Display slots"). In-flight changes use decisions up to D121; decisions here are numbered from D122.

Current state, as checked in this repository on 2026-10-16:

- The map thread renders into one of three IOSurface-backed `CVPixelBuffer`s. `BufferState` (`src/core/buffer_state.h`) gives each buffer one of three roles: latest, presented, free. Flutter's raster thread calls `copyPixelBuffer` on the one registered `MLTFlutterTexture`, which calls `MapTexture::Present()`; that returns the latest buffer and emits the frame-displayed event with the display time.
- `FrameAvailable()` dispatches `textureFrameAvailable:` to the main queue (D4), because the engine asserts the platform thread. Dart's main isolate runs on the platform thread on macOS and iOS (`docs/architecture.md`).
- The map renders the next frame only after Flutter has taken the latest one, unless it renders ahead (D19, with hysteresis), in which case a frame Flutter hasn't taken is replaced.
- During a resize, `SwapBuffersLocked` keeps the latest buffer of the old set as `fallback_`, which `CopyBufferLocked` returns until a frame of the new set is published.
- `MaybeNotifyAfterResize` marks the texture available once more 1.1 s after a resize, so that Flutter's `CVMetalTextureCache` frees replaced buffers (`docs/flutter-texture-cache-followup.md`).
- Cameras coalesce in `CommandQueue`'s camera slot; `ApplyCamera` calls `mln_map_jump_to` with the latest one. `RenderedFrameInfo()` reads the frame's camera from `mln_render_session_projection_create()` after the render.
- `_MapTextureLayerState.build` converts the `flutter_map` camera (`viewCameraOf`), applies the predictor, calls `setCamera` when the camera changed, and returns `SizedBox(viewport, ClipRect(MapTextureView))`. It rebuilds on each frame-displayed event.
- `FlutterMap` places its children, unpositioned, in a `Stack` inside a `ClipRect`, under a `MapInheritedModel` that its `MapInteractiveViewer` builder creates with the live camera. `MapInheritedModel` is public in `package:flutter_map/src/map/inherited_model.dart` (flutter_map 8.3.2) and isn't exported from `package:flutter_map/flutter_map.dart`. `MapCamera` has a public constructor (`crs`, `center`, `zoom`, `rotation`, `nonRotatedSize`, optional `minZoom`, `maxZoom`).
- On Android the map renders through a `SurfaceProducer` (surface target). Flutter takes the latest image internally, and the plugin gets no call when it does.

## Goals / Non-Goals

**Goals:**
- Exact alignment for children on macOS and iOS, without measuring or predicting it: the camera given to the children is the camera object the frame was rendered for.
- No change to the frame rate, the copy-free default, rendering on demand or the background pause.
- No change on Android beyond accepting the new C functions and `children`.

**Non-Goals:**
- Freeing a slot later than today's rule frees a buffer (D124), unless the GPU-read risk (Risks) shows up.
- Choosing a frame whose size differs from the current viewport any differently than today: during a resize the displayed frame keeps the size it was rendered at.

## Decisions

### D122. Four slots on macOS and iOS, one Flutter texture per slot

The Metal target allocates four buffers per set (`kMaxBufferCount`, which is already 4) and registers four `MLTFlutterTexture`s, each with its slot index; `copyPixelBuffer` calls `Present(slot)`. Four covers one slot shown, one chosen and waiting for the raster thread, one finished and not yet chosen, and one rendering. `map_texture_texture_ids(handle, out, capacity)` returns the ids; on Android it returns the one `SurfaceProducer` id.

Alternatives: three slots, as today's buffer count. With a chosen slot waiting for raster, the map would often have no free slot while Dart holds the previous one, and render less often. A texture per frame, registered on demand, costs a registration per frame on the main thread.

### D123. Dart chooses the slot; `map_texture_select` marks the texture available synchronously

The map thread emits a new event, frame ready, after it publishes a frame into a slot: slot, frame id, camera, size and camera sequence number (D125). The layer rebuilds on it. In `build` it chooses the newest ready frame and calls `controller.select(frame)`, which calls `map_texture_select(handle, slot, frame_id)` and then displays `Texture(textureIds[slot])`.

`map_texture_select` runs on the platform thread and calls `textureFrameAvailable:` for that slot's texture directly. If it marked the texture asynchronously, as `FrameAvailable()` does today, the raster thread could composite the build that chose slot k before the mark arrives, and display the texture's cached contents, a frame four slots old. If `select` is called off the main thread, which the plugin doesn't expect on macOS or iOS, it dispatches the mark to the main queue as today, and logs once.

`map_texture_select` checks that the slot still holds `frame_id`. The slot doesn't in two cases: a resize has replaced the set (D126), or the map rendered ahead (D19) and published a newer frame, which freed the slot (D124), after the frame-ready event reached Dart and before Dart chose the frame. The call then records nothing and returns `MAP_TEXTURE_NOT_SELECTED`, `controller.select` returns false, and the layer keeps the frame it chose before: it displays that frame's slot and gives the children that frame's camera. That frame's slot is still held, because no later choice was recorded, or after a resize `Present` returns the fallback, which is that frame. The alignment benchmark on macOS found the second case on 2026-10-16: in 2 of about 3,000 Flutter frames the layer gave the children the camera of a refused frame while Flutter displayed the frame before it, an error of 8.33 px at 1,000 px/s.

The map thread no longer calls `textureFrameAvailable:` after a render, except in `MaybeNotifyAfterResize`, which marks all four textures.

Alternative: Dart displays the slot the native side calls latest, without telling it. That is today's behavior with extra textures, and doesn't tell native which slots Dart holds.

### D124. Slot states and when a slot is free

`BufferState` keeps, per slot: free, rendering, ready (published, not chosen), or held. It also keeps the order of selections. A slot is held from `select` until `Present` is called for a slot that Dart chose later; the slot that `Present` returned last also stays held until the next `Present` of another slot. This is today's rule: a buffer is free once Flutter has taken a newer one. Consecutive selections of the same slot count once, and selecting a slot that isn't ready changes nothing.

The map thread renders into a free slot only. When a frame is published while another frame is ready and not chosen, the older ready slot becomes free, which keeps the replacement that rendering ahead (D19) relies on. The condition "Flutter has taken the latest frame" in `RenderIntoBuffer` becomes "Dart has chosen the latest ready frame": the map starts the next render after the build that chose the frame, instead of after the raster that took it. The D19 hysteresis is unchanged.

`Present(slot)` emits the frame-displayed event with the display time when the slot's frame wasn't presented before, as today, so the `Metrics` requirement and the display-time scenario keep their meaning.

If Flutter never calls `Present`, for example while the layer isn't painted, chosen slots stay held, the map runs out of free slots, and it counts skipped renders until a `Present` releases them. A layer that isn't painted needs no new frames, so the stall is acceptable.

Alternatives: free a slot when Dart chooses another. Build N+1 runs while raster N still composites slot k, so the map could overwrite the frame being displayed. Free a slot after a number of Dart frames: needed on Android (follow-up), but on Darwin `Present` is an exact signal.

### D125. Camera sequence numbers, and a ring of `flutter_map` cameras in the layer

`map_texture_set_camera` gains an `int64 seq`. `CommandQueue` stores it with the camera; `ApplyCamera` records it as the applied sequence number, and `RenderedFrameInfo()` puts it in `FrameInfo`. A frame that renders without a camera change, for example after tiles load, carries the last applied number. The controller assigns the numbers and returns each from `setCamera`.

The layer keeps the last 32 sent cameras as `seq` → `fm.MapCamera`, and never evicts the newest. For the converted camera it stores the live `fm.MapCamera` it converted. For a predicted camera it builds an `fm.MapCamera` with the predicted center, zoom and rotation, and the live camera's `crs`, `nonRotatedSize`, `minZoom` and `maxZoom`, inverting the conversion of `viewCameraOf` (zoom + 1, rotation = −bearing). A test checks that converting the built camera gives the predicted camera back.

Alternative: rebuild the `fm.MapCamera` from the camera MapLibre reports for the frame. That carries floating-point differences from the projection read-back, and the frame's report doesn't include `flutter_map`'s CRS or constraints.

### D126. Resize keeps the frame Dart displays

`SwapBuffersLocked` retains the buffer of the slot Dart chose last (instead of the latest buffer) as the fallback, and resets all slot states. Until Dart chooses a frame of the new set, `Present(slot)` returns the fallback for every slot, so a build that chose a slot of the old set, or a slot whose new buffer isn't rendered, displays the old frame. The first `select` of a new-set frame releases the fallback.

### D127. The layer draws its children under its own `MapInheritedModel`

`lib/src/layer/map_texture_layer.dart` imports `package:flutter_map/src/map/inherited_model.dart`, with an `// ignore: implementation_imports` and a comment that names this design. It is the only file that imports it. `build` returns:

```
SizedBox(viewport)
  Stack
    ClipRect(MapTextureView(controller, slot))
    MapInheritedModel(camera: childCamera,
                      controller: MapController.of(context),
                      options: MapOptions.of(context))
      Stack(children: widget.children)
```

The inner `Stack` gives its children the same loose constraints that `FlutterMap`'s `Stack` gives its children. `childCamera` is the ring's camera for the chosen frame's `seq`, or the live camera before the first frame, on Android (one texture id), or when the ring has no entry, which only a bug causes. A test builds the model, so that an upgrade of `flutter_map` that changes it fails the build or the test.

`MapigradeLayer` gets `children` (default empty) and passes it on. `MapTextureLayer` gets a test-only callback, `onChildCamera`, called in each build with the chosen frame's id and the child camera, for the alignment benchmark.

Alternatives: a public wrapper widget for overlays placed after the layer. That adds an exported type and needs the layer to share its chosen frame with sibling widgets. An `InheritedWidget` of our own: `flutter_map` layers read `MapInheritedModel` only.

### D128. Android keeps one slot and no frame-ready events

The Android target returns one texture id; `map_texture_select` returns OK and does nothing; the surface path emits no frame-ready event. The layer takes `textureIds.length == 1` to mean that it can't choose frames, displays `textureIds[0]` and gives the children the live camera. The C ABI and Dart API are the same on all platforms, as the requirement "Supported platforms" of `map-texture` requires.

### D129. The alignment benchmark measures children against the displayed frame, independently

With the overlays as children (`ALIGNMENT_CHILDREN=1` with the existing `ALIGNMENT_MODE`), the benchmark still finds the displayed map frame per Flutter frame from the display time and Flutter's frame timings, as today. It computes the alignment error against the camera that `onChildCamera` reports for that Flutter frame, and the lag against the live camera. An error above 1 px then reveals a fault in the slot protocol, because the two sources are independent. The overshoot ahead with children is measured against the live camera (spec).

## Risks / Trade-offs

- [The GPU may still read the slot shown before the last `Present` when the map renders into it, because Flutter's and the map's command queues aren't ordered.] → Today's three-buffer rule makes the same assumption, and no tearing has been observed. If tearing shows up, keep the previous slot held one `Present` longer; four slots allow it.
- [Children lag the gesture as the map does, about 1 to 2 Flutter frames at 120 Hz.] → The manual check in the tasks decides whether this is acceptable before documentation and the demo are updated. Prediction can lower the lag without affecting alignment.
- [Pacing on `select` instead of `Present` changes when renders start, and can change the frame rate and the share of undisplayed frames.] → The frame-rate benchmark runs before and after on the reference iPhone and Mac; the results go to `docs/benchmarks.md`.
- [`MapInheritedModel` isn't exported, and a `flutter_map` release can change it.] → One importing file, and a test that builds it.
- [A child that reads the camera for logic, for example to fit the camera, reads a camera 1 to 2 frames old.] → The `children` documentation says to place such widgets after the layer.
- [Four Flutter textures mean four `CVMetalTextureCache`s in the engine, each keeping replaced buffers until its maximum age.] → `MaybeNotifyAfterResize` marks all four; the released-buffer test checks that replaced sets are freed.
- [One more buffer per set: about 14 MB at the reference iPhone's size.] → Recorded with the memory measurement.

## Migration Plan

`children` is optional, and the layer without children behaves as today, so applications need no change. Applications that want exact alignment move their overlay layers into `children`. The C ABI is internal to the package. Rollback is a revert of the change.
