# Architecture

This document describes the implementation on macOS and iOS (Threads, Frame path), what `MapigradeMap` adds to it (`MapigradeMap`), and how Android differs from it (Android). Paths are relative to `packages/mapigrade/`.

## Threads

```
 Dart (main isolate, platform thread)          map thread (one per map)                 Flutter raster thread
 ───────────────────────────────────           ─────────────────────────                ─────────────────────
 MapTextureController                          creates mln_runtime and mln_map, and
   loadStyleUrl/Json, resize ──► ordered queue ──┐  drives the map's mln_render_session
   setCamera (with seq) ──────► camera slot  ──┤  (caller-graphics-thread driver)
                  (both then wake the map thread)
                                               │ loop:
                                               │   wait for a wake (Dart, the session's
                                               │     wakes, completions)
                                               │   apply queued commands, then submit the
                                               │     latest camera as a command and wait
                                               │     for its completion
                                               │   if no frame demand is outstanding, Dart
                                               │   has chosen the latest ready frame, and a
                                               │   slot is free: request a frame
                                               │   service the session's driver work, which
                                               │     renders into a slot that no acquired
                                               │     frame holds
                                               │   drain the frame results: acquire the
                                               │     newest frame, wait for its producer
                                               │     sync, hold it in its slot, publish it
                                               │     as ready
   readyFrames stream ◄─ NativeCallable.listener ◄┤ frame ready (slot, camera, seq)
   build: selectNewest() (newest ready frame) ────┤ slot held; wake
     textureFrameAvailable(slot's texture)          │
     display Texture(textureIds[slot])              │                    copyPixelBuffer (slot's texture):
                                               │                                          return the slot's buffer,
   frames stream ◄── NativeCallable.listener ◄─┼──────────── frame displayed ◄─────────── free the slots chosen
                                               └◄──────── wake (slots freed) ◄───────────  before it

 FFI runtime threads: run the map's commands, publish its render updates, run completions,
 and deliver events (style loaded, loading failed, render error, idle) ──► events stream
```

Each loop iteration runs in an autorelease pool (`RunInPlatformScope`), so that Objective-C objects created on the map thread, such as each frame's command buffer, are released after the iteration. On iOS, the plugin pauses the map thread's rendering when the app enters the background and resumes it before the app enters the foreground, and asks the renderer to release cached resources after a memory warning. While rendering is paused, the map thread doesn't service the session, so the release runs when rendering resumes (design D185 of the adopt-ffi-core-executor change).

Dart never calls MapLibre. It calls the plugin's C ABI (`src/core/map_texture_api.h`), whose functions only write to the command queue or camera slot, record Dart's choice of a frame, and wake the map thread. The FFI's runtime threads own the map and apply its commands; the map thread submits the commands, and renders on its own thread as the session's graphics thread, so that it can replace targets and prepare each frame there (design D180). Camera updates coalesce in the slot, so the map renders the latest camera only. Consecutive resizes also coalesce. The map thread waits for each camera command's completion before it services the session, so the next render includes the camera (design D181).

## Frame path

```
MapLibre (Metal) ──render──► IOSurface-backed CVPixelBuffer of a free display slot (one of four),
                             through an MTLTexture made from its IOSurface
                 ──────────► the slot's FlutterTexture.copyPixelBuffer ──► Flutter composites the
                             Texture widget of the slot that Dart chose

copyFree: false:
MapLibre (Metal) ──render──► private MTLTexture (BGRA8, one per size)
                 ──blit────► IOSurface-backed CVPixelBuffer, as above
```

The session renders on a GPU device that wraps the plugin's MTLDevice and command queue (design D221 of the port-ffi-gesture-recognizer change). Maps are copy-free by default (design D20): the session's target is a borrowed ring of the four slots' MTLTextures, in slot order, and MapLibre renders directly into them (design D182). The session chooses the slot of each frame among those whose frames the map thread doesn't hold; the map thread acquires the newest rendered frame, waits for the frame's producer sync, so that Flutter never reads a texture that the GPU is still writing, publishes the frame into its slot, and releases it with `MLN_GPU_SYNC_CPU_COMPLETE` when the slot becomes free (design D223). The session drops the rendered frames that the map thread didn't acquire. A resize ends outstanding frame demands, releases the frames, and replaces the ring (design D183). With `MapTextureController.create(copyFree: false)` or the internal layer widget `MapTextureLayer(copyFree: false)`, the ring is one private texture, and each frame is copied on the GPU into the free slot and then released (design D3b). A session renders at its map's scale factor, so a resize to another pixel ratio detaches the session, resizes the map and attaches a new session. Measurements of both modes are in `benchmarks.md`.

Each map has four display slots, each with its own buffer and its own registered Flutter texture (design D122 of the layer-children-alignment change). A slot is free, rendering, ready (it holds a finished frame that Dart hasn't chosen), or held (design D124). When a frame has rendered, the map thread reports it to Dart with its slot, camera and camera sequence number (`MapTextureController.readyFrames`). In each build, `MapigradeLayer` calls `MapTextureController.selectNewest`, which calls `map_texture_select_newest` on the platform thread. Under the `BufferState` lock, the map chooses its ready frame, which is the newest finished frame, marks the slot's texture available before the Flutter frame is rasterized, and returns the frame's slot, camera and camera sequence number; the layer displays that slot's `Texture` widget and draws its children at that camera (design D123 of the layer-children-alignment change, D139 to D141 of the synchronous-frame-choice change). The chosen frame can be newer than the last frame reported in `readyFrames`. If no frame has finished since the last choice, `selectNewest` returns null and the layer keeps the frame it chose before. A `MapTextureView` without a slot does the same.

A chosen slot stays held until Flutter presents a slot that Dart chose later, and the slot presented last stays held until Flutter presents another slot, so the map thread never renders into a buffer that Flutter may still display. A ready frame that Dart hasn't chosen is replaced by the next frame. During a resize, the buffer of the slot Dart chose last stays displayable until Dart chooses a frame of the new size (design D126). No pixels pass through CPU memory, and the copy, if any, stays on the GPU. The map renders only when MapLibre publishes a render update (each frame demand waits for one), and only after Dart has chosen the previous frame, unless it renders ahead (design D19), so it renders nothing while the map is idle.

Each displayed frame is reported to Dart with the camera and size it was rendered with and the sequence number of the camera update it was rendered with (`MapTextureController.frames`), taken from `mln_map_projection_create()` on the frame result's view. The sequence number is that of the newest camera command whose completion's render update generation the frame includes (design D181). The layer keeps the `flutter_map` camera of each of the last 32 camera updates it sent, by sequence number, and draws its `children` under its own `MapInheritedModel` at the camera of the frame it chose (designs D125 and D127). The children therefore stay exactly on the displayed map, and lag the gesture as the map does.

## Feature queries

A rendered feature query (`MapigradeController.queryRenderedFeatures`) runs against the render session's last rendered frame, not against the camera Dart set last. While the camera moves, three cameras differ: the live `flutter_map` camera, the camera of the displayed frame, and the camera of the last rendered frame, which can be ahead of the displayed one with camera prediction or while the map renders ahead. The query position is converted in two steps:

```
 tap position (logical px, flutter_map widget)
   │ Dart: worldPosition(camera of the displayed frame) per corner of the query square
   ▼
 normalized Mercator corners ──► map_texture_query_rendered_features (request id)
   │ map thread: screen position with the camera of the last rendered frame,
   │   bounds of the four corners ──► mln_render_session_query_rendered_features
   ▼
 MAP_TEXTURE_EVENT_QUERY_RESULT (request id, JSON array) ──► PendingQueries ──► Future
```

Queries wait in their own queue. Each loop iteration runs them after the frame results are handled and before the next frame demand is armed (`RunQueries`). The FFI runs a query in a later service call, and a service call can render the armed demand first, so the map thread ends the armed demand with a barrier before it converts and submits a batch, and services the session until every query of the batch has completed. The map thread records the view of each rendered frame from its frame result, including frames it doesn't publish. Results are sent in request order, and `PendingQueries` decodes a result of 64 KiB or more in another isolate and still completes queries in call order.

Feature state is set and removed with commands in the ordered queue. Because a query returns the state of the last rendered frame, the map thread holds queries until a frame has rendered with every feature-state command submitted before them. The FFI keeps feature state on the map, so it survives a style change.

## Overlays

A `MapigradePolylineLayer` draws nothing in Flutter. It gives its polylines to the map as an overlay: GeoJSON sources and the style layers that draw them, which the map adds to the style among the style's own layers (designs D197 to D199 of the add-mapigrade-polyline-layer change). Below the polyline translation (`lib/src/polyline/polyline_translation.dart`), no code refers to lines.

```
 Dart (main isolate)                                       map thread
 ───────────────────                                       ──────────
 MapigradePolylineLayer
   translation: runs, layer JSON, GeoJSON per source
   OverlayRegistration (OverlayHost, from MapTextureLayer)
     setSource ──► map_texture_overlay_set_source:
                   mln_geojson_source_data_create on the
                   calling thread (or in Isolate.run) ──► ordered queue ──► kept overlay state
     setLayers ──► map_texture_overlay_set_layers ───────► ordered queue ──►   (sources, layers,
     remove    ──► map_texture_overlay_remove(_source) ──► ordered queue ──►    placement, order key)
                                                                          SyncOverlays: query the
                                                                            style's layer list, plan
                                                                            the commands (ComputeAnchor,
                                                                            PlanLayers), submit them
```

`MapTextureLayer` provides an `OverlayHost` to its children and wraps each child in an `OverlayChildIndex`, whose index is the first part of an overlay's order key (design D200). The host keeps the overlays until the controller exists and then sends them. The polyline layer sends a source only when its features changed, and the style layers only when the run structure, the placement or the order key changed (design D196). Above 20,000 points, the GeoJSON encoding and the `set_source` call run in `Isolate.run` (design D202). The map thread sends the GeoJSON text with `mln_map_set_geo_json_source_data`, and MapLibre parses and tiles it in the background (design D224).

Commands only change the map thread's kept state of each overlay (`MapTexture::Overlay` in `src/core/map_texture.h`). After the commands of a loop iteration, and again before `MaybeRender` requests a frame, `SyncOverlays` queries `mln_map_list_style_layers` when the overlays changed or a style has loaded, and makes the style match the kept state: `ComputeAnchor` (`src/core/overlay.h`) resolves each placement to the layer the overlay's layers go before, and `PlanLayers` plans the layer additions, moves and removals. A layer list queried before a later style command or style load is dropped and queried again (design D199).

A style load removes every runtime source and layer. `OnEvents` counts style loads (`style_loads_`) and wakes the map thread, which installs every overlay again in the new style from the GeoJSON text it kept, without a round trip to Dart (designs D201 and D224). The FFI also removes every feature's state when a style loads, so the map thread keeps the net state of the feature-state commands (`src/core/feature_state.h`) and sets it again at the same point (design D249 of the port-ffi-gesture-recognizer change). A failed overlay command is reported as a render error that names the operation (design D203).

## `MapigradeMap`

`MapigradeMap` (`lib/src/map/`) displays the map with the frame path above, but MapLibre owns its camera (design D235 of the add-mapigrade-map change). `map_texture_create` takes an initial camera and limits; the map starts at that camera, Dart never writes the camera slot, and `map_texture_set_camera` is refused. Only camera commands and the FFI's gesture recognizer move the camera.

```
 Dart (main isolate, platform thread)                   map thread                 FFI runtime
 ───────────────────────────────────                    ──────────                 ───────────
 MapigradeCameraController
   jumpTo/easeTo/flyTo/fitBounds (request id) ──► ordered queue ──► camera command ──► transition
   cancelTransitions, limits ───────────────────► ordered queue ──► with an end handler
                       Future ◄── CAMERA_TRANSITION_ENDED (request id, outcome) ◄──────── ends

 MapGestureAdapter (gesture arena member)
   pointer, trackpad, wheel and key input
     ──► map_texture_gesture_handle / _tick, on the platform thread
           mln_gesture_recognizer_handle / _tick ─────────────────────────────► camera commands
     ◄── result: tick request, box zoom rectangle, events (tap, long press, notch)

 build: selectNewest() ──► frame, camera, matrix ──► MapigradeFrame ──► markers, children
```

Camera commands go through the ordered command queue, and the map thread submits each as an FFI camera command whose end handler reports `MAP_TEXTURE_EVENT_CAMERA_TRANSITION_ENDED` with the command's request id and outcome, which completes the command's `Future` (design D236).

The input adapter (`lib/src/map/gestures/map_gesture_adapter.dart`) is a gesture recognizer in a `RawGestureDetector` around the texture. It keeps each pointer's events until it wins or loses the arena, and on a win passes the kept events to the FFI's gesture recognizer in order. It accepts a pointer that moves past the pan slop or a second pointer on the map, and doesn't accept a pointer on its lift, so a child's tap recognizer wins a tap on the child (design D238). The adapter calls the recognizer on the platform thread through `map_texture_gesture_handle` and `map_texture_gesture_tick`. mln-rs allows calls from any thread, and a call doesn't wait for the map: the recognizer reads the map's last published snapshot and posts its camera moves as commands (design D237). A `Ticker` calls the tick function while the result asks for a tick every frame. Trackpad events become continuous deltas and pinches, the mouse wheel goes through `PointerSignalResolver`, and the keyboard goes through a `Focus` around the map. The recognizer decides what is a tap; when double-tap zoom is on, the adapter holds a tap for `kDoubleTapTimeout` (design D239).

`map_texture_select_newest` also returns the chosen frame's projection matrix, every field of its camera, and the clip depth convention of the device's graphics API (designs D241 and D247). The matrix is the frame result's `frame_projection`: it takes Web Mercator x and y in [0, 1] and z in meters to the frame's clip space. `MapigradeFrame` (`lib/src/map/mapigrade_frame.dart`) projects a coordinate with that matrix, in the copy of the world nearest the camera's center, and projects a position by intersecting its ray with the plane z = 0, so neither waits for the map. `MapigradeMap` provides each displayed frame through an `InheritedWidget` and through a `ValueListenable`. The render object of `MapigradeMarkers` (`lib/src/map/markers.dart`) listens to the `ValueListenable` and repaints its children with a transform per marker, without rebuilding them; it lays its children out only when they or its size change (design D242).

The map thread records the source of each FFI camera event, and each frame carries the source of the last camera event that the runtime delivered before the frame's result was handled. `cameraChanges` emits for each displayed frame whose camera differs from the previous one. After a camera event, once the map's snapshot shows no transition and no gesture, the map thread sends `MAP_TEXTURE_EVENT_CAMERA_SETTLED` with the snapshot's render update generation; `rests` emits once a displayed frame includes that generation, no pointer is down, and the recognizer asks for no tick (design D243).

`MapigradeMap` provides an `OverlayHost` and `OverlayChildIndex` to its children as `MapTextureLayer` does, so polylines work as in the layer, and attaches a `MapigradeController` with the displayed frame's camera for feature queries.

## Flutter engines

A process can run more than one Flutter engine, for example a background engine that a messaging plugin starts. Each engine registers the plugin, and texture ids are only valid in the engine that issued them, so each map registers its textures with the engine whose Dart code created it (design D153 to D157 of the multiple-flutter-engines change).

- When an engine registers the plugin, the platform code stores the engine's texture registry in a table under a token, a number that is never reused in the process. The table is guarded by a mutex.
- The plugin registers the method channel `mapigrade` with each engine. Its handler answers `engineToken` with that engine's token. Dart asks once per isolate, at the first map creation, so `MapTextureController.create` is asynchronous; `MapigradeLayer` builds an empty placeholder until the map exists.
- `map_texture_create` takes the token, the map keeps it, and `CreatePlatformRenderTarget` registers the map's textures with the token's registry. An unknown token fails the creation.
- When an engine detaches the plugin (Android `onDetachedFromEngine`, iOS `detachFromEngineForRegistrar:` when the engine is deallocated), the platform code removes the token and disposes the maps that have it (`DisposeEngineMaps`). macOS has no detach callback; its table holds the registry weakly, and a destroyed engine's undisposed maps stay until the process ends.

Pausing and memory reduction stay process-wide: they apply to every map, whichever engine created it.

## Android

Android uses the same core, C ABI and Dart API. The core has two kinds of render target (`src/core/render_target.h`): macOS and iOS use the buffer target described above, and Android uses the surface target in `android/src/main/cpp/map_texture_android.cpp` (design D52 of the android-texture-vertical-slice change).

### Threads

```
 Android main thread (also Dart's UI thread)          map thread (one per map)
 ───────────────────────────────────────────          ────────────────────────
 MapTextureController.create / resize
   createImageTexture; a new ImageReader per size
   (MapSurface, JNI)
   ANativeWindow ─────────────── ordered queue ─────►  create the EGL window surface, or switch the
                                                       session to it (mln_render_session_set_opengl_surface_target)
 setCamera, loadStyleUrl ───► camera slot, queue ──►   loop as on macOS and iOS; render at most once
                                                       per display refresh interval, into a free slot:
                                                         set the frame id as presentation time,
                                                         service the session → eglSwapBuffers queues
                                                         the frame in the ImageReader

                         image listener thread (one per map)
                         ───────────────────────────────────
                         acquire the image, OnFrameImage: the frame's slot keeps
                         the image, and the frame is published
   readyFrames stream ◄── NativeCallable.listener ◄── frame ready (slot, camera, seq)
 layer build: selectNewest() ──► pushImage of the slot's image into the image texture,
   frames stream ◄── frame displayed (no display time)
                                                       Flutter raster thread takes the pushed image
 onActivityStopped ──► pause, park on a 1x1 pbuffer ─►  done; the main thread waits for it, then closes
   surface, close the images and the readers           the images and the readers
 onActivityStarted ──► new ImageReader, resume ─────►  switch to the new window surface
 onTrimMemory(≥ BACKGROUND), onLowMemory ───────────►  release cached renderer resources
```

`MapTextureController.create` and `resize` run on Android's main thread, because Dart's UI thread is merged with it. The surface target calls `MapSurface` through JNI there: it creates the image texture and, for each physical size, an `ImageReader`, whose `Surface` goes to the map thread as an `ANativeWindow` (designs D130 and D136 of the android-layer-children-alignment change). The map thread never calls into Java and never waits for the main thread. The main thread waits for the map thread only when the activity stops and at dispose; to keep these waits short, each window surface has swap interval 0, so that `eglSwapBuffers` never waits for a buffer (design D53 of the android-texture-vertical-slice change).

Each `ImageReader` has a listener on a thread of its own, which passes each image to the native target (`MapTexture::OnFrameImage`). The target keeps a global reference to the image of each display slot. It gives an image to Flutter with `pushImage`, and closes it when its slot becomes free, under the `BufferState` lock, so the three are ordered (design D135).

The plugin class registers activity lifecycle callbacks. When the Flutter activity stops, it pauses rendering, parks the session on a pbuffer surface, and closes the slots' images and the readers; when the activity starts again, it creates a reader and resumes rendering (design D137). The map, its style and its loaded tiles stay in place.

### Frame path

```
MapLibre (OpenGL ES) ──render──► EGL window surface on the ImageReader's Surface
                     ──eglSwapBuffers──► ImageReader HardwareBuffer ──► listener acquires the Image
                                         ──► slot ──selectNewest──► pushImage ──► Flutter samples it as a Texture widget
```

The session renders on a GPU device that wraps an EGL context of the map thread (FFI preset `android-arm64`, design D222 of the port-ffi-gesture-recognizer change). It makes a context of its own in that context's share group, makes it current on the window surface for each frame, and renders directly into the `ImageReader`'s `HardwareBuffer`s, so the plugin makes no copy and no pixels pass through CPU memory. `copyFree: false` has no effect on Android.

Android has six display slots, which share the one image texture, so `MapTextureController.textureIds` has six equal ids (designs D133 and D135). Before each render, the map thread records the frame id in the slot, and before every service call it sets the next frame's id as the presentation time, because any service call can present the frame (design D184). The listener matches each image to its slot by that timestamp. The image can arrive before the service call returns; the map thread then publishes the frame when the frame result arrives (design D131). When the session loses its surface target, the map thread attaches a new session to the current surface (design D184). When a frame is published, Dart receives the frame-ready report, which starts a build of the layer; in each build the layer chooses the newest ready frame, as on macOS and iOS. `map_texture_select_newest` gives the frame's image to the texture on the main thread, before the Flutter frame is rasterized, and sends the frame-displayed report, which has no display time (design D132).

Flutter gives the plugin no call when it has finished with an image, so a chosen slot becomes free when Dart has chosen three later frames; its image is then closed (design D133). The map thread starts a render no earlier than one display refresh interval after the previous one, and doesn't wait for Dart's choice; a ready frame that Dart hasn't chosen is replaced by the next one (design D134). Deferred renders are counted in `interval_waits`.

Dart finds the plugin's functions through the build hook `hook/build.dart`, which names `libmapigrade.so` as the bindings' code asset. [packaging.md](packaging.md) describes how the APK contains the libraries.
