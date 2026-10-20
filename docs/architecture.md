# Architecture

This document describes the implementation on macOS and iOS (Threads, Frame path) and how Android differs from it (Android). Paths are relative to `packages/flutter_mapigrade/`.

## Threads

```
 Dart (main isolate, platform thread)          map thread (one per map)                 Flutter raster thread
 ───────────────────────────────────           ─────────────────────────                ─────────────────────
 MapTextureController                          owns mln_runtime, mln_map,
   loadStyleUrl/Json, resize ──► ordered queue ──┐  mln_render_session
   setCamera (with seq) ──────► camera slot  ──┤
                  (both then mln_wake_source_signal)
                                               │ loop:
                                               │   mln_runtime_pump (parks until a wake)
                                               │   apply queued commands, then the latest camera
                                               │   drain events ── style loaded, loading failed,
   events stream ◄── NativeCallable.listener ◄─┤                   render error, idle
                                               │   if a render update is pending, Dart has
                                               │   chosen the latest ready frame, and a slot
                                               │   is free:
                                               │     set_target to the free slot's buffer
                                               │     render_update into it
                                               │     (copyFree: false: render_update into the
                                               │      render texture, blit into the free slot)
                                               │     publish it as ready
   readyFrames stream ◄─ NativeCallable.listener ◄┤ frame ready (slot, camera, seq)
   build: selectNewest() (newest ready frame) ────┤ slot held; wake
     textureFrameAvailable(slot's texture)          │
     display Texture(textureIds[slot])              │                    copyPixelBuffer (slot's texture):
                                               │                                          return the slot's buffer,
   frames stream ◄── NativeCallable.listener ◄─┼──────────── frame displayed ◄─────────── free the slots chosen
                                               └◄──────── wake (slots freed) ◄───────────  before it
```

Each loop iteration runs in an autorelease pool (`RunInPlatformScope`), so that Objective-C objects created on the map thread, such as each frame's command buffer, are released after the iteration. On iOS, the plugin pauses the map thread's rendering when the app enters the background and resumes it before the app enters the foreground, and asks the renderer to release cached resources after a memory warning.

Dart never calls MapLibre. It calls the plugin's C ABI (`src/core/map_texture_api.h`), whose functions only write to the command queue or camera slot, record Dart's choice of a frame, and wake the map thread. The map thread is the owner thread of the runtime, map and render session, as the FFI requires. Camera updates coalesce in the slot, so the map renders the latest camera only. Consecutive resizes also coalesce.

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

Maps are copy-free by default (design D20): before each render, `mln_metal_borrowed_texture_set_target()` makes the free slot's MTLTexture the session's target, and MapLibre renders directly into it. With `MapTextureController.create(copyFree: false)` or the internal layer widget `MapTextureLayer(copyFree: false)`, MapLibre renders into one private texture, and each frame is copied on the GPU into the free slot (design D3b). Measurements of both modes are in `benchmarks.md`.

Each map has four display slots, each with its own buffer and its own registered Flutter texture (design D122 of the layer-children-alignment change). A slot is free, rendering, ready (it holds a finished frame that Dart hasn't chosen), or held (design D124). When a frame has rendered, the map thread reports it to Dart with its slot, camera and camera sequence number (`MapTextureController.readyFrames`). In each build, `MapigradeLayer` calls `MapTextureController.selectNewest`, which calls `map_texture_select_newest` on the platform thread. Under the `BufferState` lock, the map chooses its ready frame, which is the newest finished frame, marks the slot's texture available before the Flutter frame is rasterized, and returns the frame's slot, camera and camera sequence number; the layer displays that slot's `Texture` widget and draws its children at that camera (design D123 of the layer-children-alignment change, D139 to D141 of the synchronous-frame-choice change). The chosen frame can be newer than the last frame reported in `readyFrames`. If no frame has finished since the last choice, `selectNewest` returns null and the layer keeps the frame it chose before. A `MapTextureView` without a slot does the same.

A chosen slot stays held until Flutter presents a slot that Dart chose later, and the slot presented last stays held until Flutter presents another slot, so the map thread never renders into a buffer that Flutter may still display. A ready frame that Dart hasn't chosen is replaced by the next frame. During a resize, the buffer of the slot Dart chose last stays displayable until Dart chooses a frame of the new size (design D126). No pixels pass through CPU memory, and the copy, if any, stays on the GPU. The map renders only when MapLibre publishes a render update, and only after Dart has chosen the previous frame, unless it renders ahead (design D19), so it renders nothing while the map is idle.

Each displayed frame is reported to Dart with the camera and size it was rendered with and the sequence number of the camera update it was rendered with (`MapTextureController.frames`), taken from `mln_render_session_projection_create()` after the frame rendered. The layer keeps the `flutter_map` camera of each of the last 32 camera updates it sent, by sequence number, and draws its `children` under its own `MapInheritedModel` at the camera of the frame it chose (designs D125 and D127). The children therefore stay exactly on the displayed map, and lag the gesture as the map does.

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
                                                       session to it (mln_opengl_surface_set_target)
 setCamera, loadStyleUrl ───► camera slot, queue ──►   loop as on macOS and iOS; render at most once
                                                       per display refresh interval, into a free slot:
                                                         set the frame id as presentation time,
                                                         render_update → eglSwapBuffers queues the
                                                         frame in the ImageReader

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

Android has six display slots, which share the one image texture, so `MapTextureController.textureIds` has six equal ids (designs D133 and D135). Before each render, the map thread records the frame id in the slot and sets it as the frame's presentation time. The listener matches each image to its slot by that timestamp. The image can arrive before `render_update` returns; the map thread then publishes the frame when the render returns (design D131). When a frame is published, Dart receives the frame-ready report, which starts a build of the layer; in each build the layer chooses the newest ready frame, as on macOS and iOS. `map_texture_select_newest` gives the frame's image to the texture on the main thread, before the Flutter frame is rasterized, and sends the frame-displayed report, which has no display time (design D132).

Flutter gives the plugin no call when it has finished with an image, so a chosen slot becomes free when Dart has chosen three later frames; its image is then closed (design D133). The map thread starts a render no earlier than one display refresh interval after the previous one, and doesn't wait for Dart's choice; a ready frame that Dart hasn't chosen is replaced by the next one (design D134). Deferred renders are counted in `interval_waits`.

Dart finds the plugin's functions through the build hook `hook/build.dart`, which names `libflutter_mapigrade.so` as the bindings' code asset. [packaging.md](packaging.md) describes how the APK contains the libraries.
