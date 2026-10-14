# Architecture

This document describes the macOS and iOS implementation. Paths are relative to `packages/flutter_mapigrade/`.

## Threads

```
 Dart (main isolate, platform thread)          map thread (one per map)                 Flutter raster thread
 ───────────────────────────────────           ─────────────────────────                ─────────────────────
 MapTextureController                          owns mln_runtime, mln_map,
   loadStyleUrl/Json, resize ──► ordered queue ──┐  mln_render_session
   setCamera ─────────────────► camera slot  ──┤
                  (both then mln_wake_source_signal)
                                               │ loop:
                                               │   mln_runtime_pump (parks until a wake)
                                               │   apply queued commands, then the latest camera
                                               │   drain events ── style loaded, loading failed,
   events stream ◄── NativeCallable.listener ◄─┤                   render error, idle
                                               │   if a render update is pending, Flutter has
                                               │   taken the latest frame, and a buffer is free:
                                               │     set_target to the free IOSurface buffer
                                               │     render_update into it
                                               │     (copyFree: false: render_update into the
                                               │      render texture, blit into the free buffer)
                                               │     publish it as latest
                                               │     textureFrameAvailable (via main queue)
                                               │                                        copyPixelBuffer:
                                               │                                          latest → presented,
   frames stream ◄── NativeCallable.listener ◄─┼──────────── frame displayed ◄─────────── return the buffer,
                                               └◄──────── wake (frame taken) ◄───────────  report its camera
```

Each loop iteration runs in an autorelease pool (`RunInPlatformScope`), so that Objective-C objects created on the map thread, such as each frame's command buffer, are released after the iteration. On iOS, the plugin pauses the map thread's rendering when the app enters the background and resumes it before the app enters the foreground, and asks the renderer to release cached resources after a memory warning.

Dart never calls MapLibre. It calls the plugin's C ABI (`src/core/map_texture_api.h`), whose functions only write to the command queue or camera slot and wake the map thread. The map thread is the owner thread of the runtime, map and render session, as the FFI requires. Camera updates coalesce in the slot, so the map renders the latest camera only. Consecutive resizes also coalesce.

## Frame path

```
MapLibre (Metal) ──render──► IOSurface-backed CVPixelBuffer (one of three: latest, presented, free),
                             through an MTLTexture made from its IOSurface
                 ──────────► FlutterTexture.copyPixelBuffer ──► Flutter composites it as a Texture widget

copyFree: false:
MapLibre (Metal) ──render──► private MTLTexture (BGRA8, one per size)
                 ──blit────► IOSurface-backed CVPixelBuffer, as above
```

Maps are copy-free by default (design D20): before each render, `mln_metal_borrowed_texture_set_target()` makes the free buffer's MTLTexture the session's target, and MapLibre renders directly into it. With `MapTextureController.create(copyFree: false)` or the internal layer widget `MapTextureLayer(copyFree: false)`, MapLibre renders into one private texture, and each frame is copied on the GPU into the free buffer (design D3b). Measurements of both modes are in `benchmarks.md`.

No pixels pass through CPU memory, and the copy, if any, stays on the GPU. The three buffers ensure that the map thread never writes into the buffer Flutter displays or the one it displays next. The map renders only when MapLibre publishes a render update, and only after Flutter has taken the previous frame, so it renders nothing while the map is idle and no more frames than the display shows.

Each displayed frame is reported to Dart with the camera and size it was rendered with (`MapTextureController.frames`), taken from `mln_render_session_projection_create()` after the frame rendered.
