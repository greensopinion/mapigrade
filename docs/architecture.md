# Architecture

This document describes the implementation on macOS and iOS (Threads, Frame path) and how Android differs from it (Android). Paths are relative to `packages/flutter_mapigrade/`.

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
                                               │     frame, hold it in its slot, publish it
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

Maps are copy-free by default (design D20): the session's target is a borrowed ring of the four slots' MTLTextures, in slot order, and MapLibre renders directly into them (design D182). The session chooses the slot of each frame among those whose frames the map thread doesn't hold; the map thread acquires each rendered frame, publishes it into its slot, and releases it when the slot becomes free. A resize ends outstanding frame demands, releases the frames, and replaces the ring (design D183). With `MapTextureController.create(copyFree: false)` or the internal layer widget `MapTextureLayer(copyFree: false)`, MapLibre renders into one private texture, and each frame is copied on the GPU into the free slot (design D3b). Measurements of both modes are in `benchmarks.md`.

Each map has four display slots, each with its own buffer and its own registered Flutter texture (design D122 of the layer-children-alignment change). A slot is free, rendering, ready (it holds a finished frame that Dart hasn't chosen), or held (design D124). When a frame has rendered, the map thread reports it to Dart with its slot, camera and camera sequence number (`MapTextureController.readyFrames`). In each build, `MapigradeLayer` calls `MapTextureController.selectNewest`, which calls `map_texture_select_newest` on the platform thread. Under the `BufferState` lock, the map chooses its ready frame, which is the newest finished frame, marks the slot's texture available before the Flutter frame is rasterized, and returns the frame's slot, camera and camera sequence number; the layer displays that slot's `Texture` widget and draws its children at that camera (design D123 of the layer-children-alignment change, D139 to D141 of the synchronous-frame-choice change). The chosen frame can be newer than the last frame reported in `readyFrames`. If no frame has finished since the last choice, `selectNewest` returns null and the layer keeps the frame it chose before. A `MapTextureView` without a slot does the same.

A chosen slot stays held until Flutter presents a slot that Dart chose later, and the slot presented last stays held until Flutter presents another slot, so the map thread never renders into a buffer that Flutter may still display. A ready frame that Dart hasn't chosen is replaced by the next frame. During a resize, the buffer of the slot Dart chose last stays displayable until Dart chooses a frame of the new size (design D126). No pixels pass through CPU memory, and the copy, if any, stays on the GPU. The map renders only when MapLibre publishes a render update (each frame demand waits for one), and only after Dart has chosen the previous frame, unless it renders ahead (design D19), so it renders nothing while the map is idle.

Each displayed frame is reported to Dart with the camera and size it was rendered with and the sequence number of the camera update it was rendered with (`MapTextureController.frames`), taken from `mln_map_projection_create()` on the frame result's view. The sequence number is that of the newest camera command whose completion's render update generation the frame includes (design D181). The layer keeps the `flutter_map` camera of each of the last 32 camera updates it sent, by sequence number, and draws its `children` under its own `MapInheritedModel` at the camera of the frame it chose (designs D125 and D127). The children therefore stay exactly on the displayed map, and lag the gesture as the map does.

## Feature queries

A rendered feature query (`LayerController.queryRenderedFeatures`) runs against the render session's last rendered frame, not against the camera Dart set last. While the camera moves, three cameras differ: the live `flutter_map` camera, the camera of the displayed frame, and the camera of the last rendered frame, which can be ahead of the displayed one with camera prediction or while the map renders ahead. The query position is converted in two steps:

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

## Flutter engines

A process can run more than one Flutter engine, for example a background engine that a messaging plugin starts. Each engine registers the plugin, and texture ids are only valid in the engine that issued them, so each map registers its textures with the engine whose Dart code created it (design D153 to D157 of the multiple-flutter-engines change).

- When an engine registers the plugin, the platform code stores the engine's texture registry in a table under a token, a number that is never reused in the process. The table is guarded by a mutex.
- The plugin registers the method channel `flutter_mapigrade` with each engine. Its handler answers `engineToken` with that engine's token. Dart asks once per isolate, at the first map creation, so `MapTextureController.create` is asynchronous; `MapigradeLayer` builds an empty placeholder until the map exists.
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

The session is dedicated (FFI preset `android-arm64-egl`): it owns the map thread's EGL context and renders directly into the `ImageReader`'s `HardwareBuffer`s, so the plugin makes no copy and no pixels pass through CPU memory. `copyFree: false` has no effect on Android.

Android has six display slots, which share the one image texture, so `MapTextureController.textureIds` has six equal ids (designs D133 and D135). Before each render, the map thread records the frame id in the slot, and before every service call it sets the next frame's id as the presentation time, because any service call can present the frame (design D184). The listener matches each image to its slot by that timestamp. The image can arrive before the service call returns; the map thread then publishes the frame when the frame result arrives (design D131). When the session loses its surface target, the map thread attaches a new session to the current surface (design D184). When a frame is published, Dart receives the frame-ready report, which starts a build of the layer; in each build the layer chooses the newest ready frame, as on macOS and iOS. `map_texture_select_newest` gives the frame's image to the texture on the main thread, before the Flutter frame is rasterized, and sends the frame-displayed report, which has no display time (design D132).

Flutter gives the plugin no call when it has finished with an image, so a chosen slot becomes free when Dart has chosen three later frames; its image is then closed (design D133). The map thread starts a render no earlier than one display refresh interval after the previous one, and doesn't wait for Dart's choice; a ready frame that Dart hasn't chosen is replaced by the next one (design D134). Deferred renders are counted in `interval_waits`.

Dart finds the plugin's functions through the build hook `hook/build.dart`, which names `libflutter_mapigrade.so` as the bindings' code asset. [packaging.md](packaging.md) describes how the APK contains the libraries.
