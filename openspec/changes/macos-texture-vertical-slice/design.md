## Context

This repository contains only the exploration brief (`docs/maplibre-native-ffi-flutter-texture-poc.md`). It has no code yet. See proposal.md for motivation and scope; specs/map-texture/spec.md for requirements.

Facts that constrain the design, checked in MapLibre Native FFI at commit `dd97d20f8fab6990cd87c13f091ce00e662707bd` (headers under `include/maplibre_native_c/`):

- macOS has a `macos-arm64-metal` CMake preset. Metal supports three render target kinds: surface, session-owned texture and borrowed (caller-owned) texture.
- `mln_metal_borrowed_texture_attach()` renders into a caller-supplied `id<MTLTexture>` that is render-target capable, single-sample, and exactly the declared physical size.
- `mln_metal_borrowed_texture_set_target()` changes the target texture without destroying the session. The renderer, tile pyramid, glyph atlases and symbol placement are kept. A different pixel format is rejected. A different `scale_factor` rebuilds the renderer. The header says the new extent "applies exactly as `mln_render_session_resize()` applies one".
- For the borrowed-texture path, `render_update` commits its command buffer and calls `waitUntilCompleted()` before it returns (`src/render/metal/metal_texture_backend.mm:137-138`). When the call returns, the texture contents are complete.
- The runtime, map, camera and style calls are bound to the map owner thread. Session calls are bound to the thread that attached the session. A call from another thread returns `MLN_STATUS_WRONG_THREAD`.
- `mln_wake_source_signal()` can be called from any thread and wakes a parked `mln_runtime_pump()`.
- `mln_render_session_projection_create()` captures the transform of the last rendered frame. `mln_map_projection_get_camera()` reads its camera.
- Events of interest: `MLN_RUNTIME_EVENT_MAP_STYLE_LOADED`, `MLN_RUNTIME_EVENT_MAP_LOADING_FAILED`, `MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE`, `MLN_RUNTIME_EVENT_MAP_RENDER_ERROR`, `MLN_RUNTIME_EVENT_MAP_IDLE`.

## Goals / Non-Goals

**Goals:**
- Prove the frame path from MapLibre Metal rendering to Flutter `Texture` on macOS without CPU readback, and measure it.
- Establish the threading and ownership model that the iOS and Android slices will reuse.
- Produce per-frame camera data from the start, because the later `flutter_map` slice needs it to align the texture with overlays.

**Non-Goals:**
- A general map API. The C ABI and Dart API cover only the operations in the spec.
- Gestures inside MapLibre. The example app changes the camera from Flutter (buttons, sliders, a timed pan).
- Using the official `maplibre_native_ffi` Dart binding. The native core calls the C API directly.
- Optimizing beyond what the 30 fps minimum requires, unless a measurement shows a cheap gain.

## Decisions

### D1. A native C/C++ core owns all MapLibre threads

The plugin's native core creates a thread (the map thread) that owns the runtime, the map and the render session. Dart calls a small C ABI exported by the plugin through `dart:ffi`. Those calls only write to state that is safe to access from any thread, then call `mln_wake_source_signal()`. Dart never calls MapLibre directly.

The C/C++ core (`src/core/`) has no Apple dependencies. Only the render target and texture registration are platform-specific (`macos/`). The iOS and Android slices are expected to reuse the core.

*Alternative:* Dart's main isolate owns the runtime and map through the official Dart binding, and a native thread owns the session. We rejected it for this slice. It puts pumping the runtime and draining events on the thread that builds Flutter frames, it needs an `mln_map` handle passed between Dart and native code (which requires both to load the same library instance, not verified), and it still needs a native thread for the session. Its advantage, the full map API without wrappers, doesn't matter while the `flutter_map` base-layer model needs only about 20 to 30 operations. We will reconsider this if the project changes to a model where MapLibre owns the camera.

### D2. One thread for runtime, map and session to start

The map thread's loop:

```
loop:
  mln_runtime_pump(runtime, timeout)       // parks until work or wake
  apply pending commands (style, resize, dispose)
  apply latest camera slot if changed
  drain events -> forward selected events to Dart
  if render update available and a free buffer exists:
      set_target(free buffer) if it differs from current
      render_update()                       // returns after GPU completes
      if RENDERED: capture frame camera, publish buffer, notify Flutter
```

*Alternative:* a separate render thread that owns the session, synchronized with the map thread through atomic flags (the "dedicated thread" pattern in the FFI render loop guide). It allows style and tile work to overlap with rendering. We defer it until a measurement shows map-thread work delaying frames. The C API allows moving the session to its own thread later without changing the Dart API.

### D3. Render target: borrowed Metal textures over a set of three IOSurface-backed pixel buffers

The bridge allocates three `CVPixelBuffer`s with `kCVPixelFormatType_32BGRA` and IOSurface backing, and creates an `MTLTexture` for each through `CVMetalTextureCache` (`MTLPixelFormatBGRA8Unorm`, render-target usage). The session attaches to one with `mln_metal_borrowed_texture_attach()`. Before each frame it calls `mln_metal_borrowed_texture_set_target()` with a free buffer. MapLibre renders directly into memory that Flutter samples, so there is no copy.

There are three buffers so that MapLibre never writes to the buffer Flutter displays now or the one it may still sample:
- **latest**: the last completed frame, which the next `copyPixelBuffer` returns
- **presented**: the one `copyPixelBuffer` returned last
- **free**: the render target

*Fallback (D3b):* if `set_target` with an unchanged size is expensive, for example if it causes a `MLN_RENDER_RESULT_SIZE_PENDING` cycle on every frame, the session keeps one borrowed `MTLTexture` and each frame is copied into the free pixel buffer with an `MTLBlitCommandEncoder`. That is one GPU copy per frame, which the spec permits. Task 3.3 measures `set_target` before the rest of the bridge is built on it.

*Alternative:* a session-owned texture with `acquire_frame`/`release_frame` plus a blit. It has the same copy as D3b and adds acquire/release states that block `render_update` while acquired. We rejected it in favor of D3b.

*Alternative:* the Metal surface target (`CAMetalLayer`). Flutter's texture registry doesn't accept a layer, and using a layer means a platform view. We rejected it.

### D4. Frame handoff to Flutter

The bridge implements `FlutterTexture`. `copyPixelBuffer` runs on Flutter's raster thread. It reads the **latest** index atomically, marks that buffer as **presented**, and returns it with +1 retain, which Flutter releases. After publishing a frame, the map thread calls `textureFrameAvailable:` on the texture registry. If that method requires the platform thread, the call is dispatched to the main queue. Task 3.4 checks the macOS embedder's threading contract.

A buffer is free when it is neither **latest** nor **presented**. If no buffer is free (Flutter hasn't sampled since the last two frames), the map thread skips rendering and retries on the next wake. It doesn't overwrite a buffer Flutter may sample.

### D5. Commands from Dart and coalescing

The C ABI (`map_texture_*` functions, names to be fixed during implementation) takes a handle and plain values. Camera updates go into a single slot under a mutex. Each update overwrites the previous one, which provides the "latest camera wins" coalescing the spec requires. Style loads, resize and dispose go into an ordered queue, because they must not be dropped or reordered. Every command ends with `mln_wake_source_signal()`.

Dart binds the ABI with `@Native` declarations resolved from the process (the plugin's native code is linked into the app), so there is no separate dynamic library for Dart to load.

### D6. Events and frame camera back to Dart

The native core receives a `NativeCallable.listener` function pointer at creation. The map thread calls it with small value-only messages: style loaded, load failed (with message), render error, idle, and frame displayed (frame id, center, zoom, bearing, physical size, scale factor). The callback runs later on the main isolate's event loop.

The frame camera comes from `mln_render_session_projection_create()` and `mln_map_projection_get_camera()` after each `MLN_RENDER_RESULT_RENDERED`. The camera last sent from Dart isn't used, because the rendered update may predate it. The frame id increments per rendered frame. The bridge records which frame id each buffer holds, so that the "frame displayed" event refers to the frame `copyPixelBuffer` returned.

*Alternative:* a `SendPort` with `Dart_PostCObject` through `dart_api_dl`. It works the same way but needs the Dart API DL initialization. `NativeCallable.listener` needs less code.

### D7. Resize and device pixel ratio

The Dart widget reports its logical size and `MediaQuery.devicePixelRatio` through `LayoutBuilder`. The map thread allocates a new set of three buffers at the new physical size and calls `set_target` with the new extent. It handles `MLN_RENDER_RESULT_SIZE_PENDING` by waiting for the next render-update event. Buffers of the old size are released after Flutter has taken a frame of the new size. A change of device pixel ratio rebuilds the renderer (per the header), so tiles and atlases reload. That is acceptable, because a pixel ratio change is rare.

During a window resize, consecutive resize commands are coalesced like camera updates (the latest size wins), so that a drag doesn't allocate a buffer set per intermediate size.

### D8. Repository layout and build

```
packages/flutter_map_maplibre_texture/   Flutter plugin (macOS only in this change)
  lib/flutter_map_maplibre_texture.dart  public exports
  lib/src/texture/                       Dart API: controller, widget, @Native bindings;
                                         must not import package:flutter_map
  lib/src/layer/                         flutter_map layer (later change; empty here)
  src/core/                              C/C++ core: map thread, commands, events (no Apple deps)
  macos/                                 ObjC++ bridge: buffer set, FlutterTexture, registration
example/                                 Flutter macOS app with a Flutter overlay and camera controls
scripts/build_maplibre_ffi.sh            clones the FFI repo at the pinned commit, builds macos-arm64-metal
third_party/maplibre-native-ffi/         build output (gitignored), linked and embedded by the plugin
```

The FFI commit is fixed in one place (`scripts/maplibre_ffi.lock` or a variable in the script), and the README records it. The plugin uses the native build integration (CocoaPods or Swift Package Manager) that the pinned Flutter version's plugin template defaults to. The README records which one and the exact Flutter version.

### D9. One package with an internal boundary

The texture core and the later `flutter_map` layer live in one package, `flutter_map_maplibre_texture`. Inside it, `lib/src/texture/` (and the native code) must not import `package:flutter_map`; only `lib/src/layer/` may. A test checks this by scanning the imports under `lib/src/texture/`. This keeps the core's dependency direction the same as a separate package would, without a second pubspec and coordinated releases.

*Alternative:* two packages, a core without the `flutter_map` dependency plus a `flutter_map` layer package, as `vector_tile_renderer` and `vector_map_tiles` are split. We rejected it for now. During the POC and the `flutter_map` slice, layer requirements will change the core API often, so most changes would need releases of both packages, and the core has no other user. We will revisit it if a second user of the core appears. Then `lib/src/texture/` and the native code move to a new core package, and this package keeps its name as the layer, so users of the layer don't change their dependency.

The name is a working name until the package is published on pub.dev.

### D10. Measurement

- Flutter side: `SchedulerBinding.addTimingsCallback` for UI and raster durations, and counting distinct "frame displayed" ids per second for the displayed map frame rate.
- Native side: duration of each `render_update`, the number of frames rendered and skipped (no free buffer), and `set_target` duration.
- Instruments: Metal System Trace for GPU time and for confirming that no CPU readback occurs; Allocations and the thread count for the lifecycle scenario.
- Scenario from the spec: 30 s continuous pan at a fixed zoom over a cached area, window 1600x1000 logical pixels. Results go in `benchmarks.md` with machine, macOS, Flutter and FFI versions.

## Risks / Trade-offs

- [`set_target` with an unchanged size may cost too much per frame] → Measure it first (task 3.3); switch to D3b (single borrowed texture plus a blit) if needed.
- [`waitUntilCompleted` inside `render_update` runs CPU encoding and GPU execution one after the other on the map thread] → It sets a ceiling on frame rate; measure encoding and GPU time separately. If it limits the frame rate, split the session onto its own thread (D2 alternative) so that map work overlaps the wait.
- [Map thread work (style parsing, tile responses) delays frames because D2 uses one thread] → Bound each pump with a drain budget; split threads if measurements show frame delays caused by pumping.
- [The macOS embedder may hold a returned `CVPixelBuffer` longer than one frame] → Three buffers plus "skip when no buffer is free" prevent overwriting. If skips are frequent, increase to four buffers.
- [BGRA format and color space mismatch between MapLibre output and Flutter's sampling] → Verify the colors against a reference style with known colors; set the IOSurface color space explicitly if they differ.
- [Pre-1.0 FFI C ABI changes] → Pin the commit, keep all MapLibre calls in `src/core/` and the Metal target code, and record any local patches.
- [Packaging the FFI dylib into the app bundle (install name, code signing)] → Verify with a release build, run outside the build directory, and record the bundle size increase.
- [The texture shows an older camera than Flutter's overlays during camera changes] → Accepted in this slice. The frame camera report (D6) is the input for the later alignment work.

## Open Questions

- Whether the macOS embedder allows `textureFrameAvailable:` from a thread other than the platform thread. The answer only decides whether D4 dispatches to the main queue. It doesn't change the design or the tasks.
- Whether a release build needs the FFI library as a framework rather than a bare dylib for code signing. It changes only the packaging step in task group 2.
