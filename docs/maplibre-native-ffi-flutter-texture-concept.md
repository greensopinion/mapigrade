# MapLibre Native FFI + Flutter Texture: Concept

**Status:** Concept and decisions; stages 1 (macOS) and 2 (iOS) done, decision: continue
**Updated:** 2026-10-09

## 1. Purpose

We maintain a vector map renderer for Flutter in two versions:

- a CPU version that draws with the Flutter canvas ([`dart-vector-tile-renderer`](https://github.com/greensopinion/dart-vector-tile-renderer), [`flutter-vector-map-tiles`](https://github.com/greensopinion/flutter-vector-map-tiles));
- a GPU version that has all of the CPU version's complexity, plus GPU code that targets `flutter_gpu`, which may take years to reach GA or may never reach it.

This experiment tests whether MapLibre Native can replace our renderer. MapLibre Native handles style evaluation, tile decoding (vector and raster), text shaping, label collision detection and rendering. If it works, we stop maintaining a renderer and the dependency on `flutter_gpu`. The experiment doesn't compare against our existing renderer. It tests whether the MapLibre approach is fast enough and correct enough to use on its own.

## 2. Concept

MapLibre Native renders the map on the GPU into memory that Flutter displays with a standard `Texture` widget. There is no platform view. Flutter draws other widgets, including `flutter_map` overlays, on top of the texture as it draws them over any other widget.

```
+----------------------------------------------------+
|  Flutter widget tree                               |
|    flutter_map overlays (routes, markers, UI)      |  Flutter: layout, gestures,
|    Texture(textureId)  <-- sampled by Flutter      |  composition, camera
+-------------|--------------------------------------+
              | platform texture registry
+-------------|--------------------------------------+
|  Platform bridge                                   |
|    macOS/iOS: FlutterTexture <- IOSurface-backed   |
|               CVPixelBuffer <- Metal texture       |
|    Android:   SurfaceProducer -> Surface -> EGL    |
+-------------|--------------------------------------+
              |
+-------------|--------------------------------------+
|  Native core (our C/C++ code)                      |
|    map thread: runtime + map + render session      |
+-------------|--------------------------------------+
              | C API
+-------------|--------------------------------------+
|  MapLibre Native FFI (pinned commit)               |  MapLibre: style, tiles,
|    style, tiles, text, labels, Metal/GL rendering  |  text, labels, rendering
+----------------------------------------------------+
```

The package is named `flutter_map_maplibre_texture`. The name follows the `flutter_map` plugin naming convention, and "texture" distinguishes it from `flutter_map_maplibre` (section 9), which displays the native MapLibre SDK view.

## 3. Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | Use draft PR #906 (`maplibre/flutter-maplibre-gl`) for ideas only; reuse none of its code | #906 keeps the `maplibre_gl` API, where MapLibre controls the camera; model A needs `flutter_map` to control it |
| 2 | Our existing renderer is not a comparison point | The question is whether MapLibre is good enough, not whether it's better |
| 3 | Goal: stop maintaining a renderer and the `flutter_gpu` dependency | See section 1 |
| 4 | Platform order: macOS, then iOS, then Android | macOS and iOS share the Metal bridge; macOS has the shortest build-and-run loop; the Apple path has the larger feasibility risk, so we test it first |
| 5 | Required: iOS and Android. macOS is a plus. Web is out of scope | Our requirement |
| 6 | Minimum 30 fps on Mac, Android and iPhone; target 60 fps or more | Acceptance threshold for the go/no-go decisions |
| 7 | Integration model A: MapLibre renders the base layer; `flutter_map` controls the camera, gestures and overlays | Keeps Flutter composition; keeps the MapLibre API small (section 6) |
| 8 | Threads that the native core creates own the MapLibre runtime, map and render session; Dart sends commands through `dart:ffi` | Keeps MapLibre work off Flutter's UI thread; one owner per MapLibre object (section 5) |
| 9 | Zero-copy is preferred; GPU-to-GPU copies are acceptable; CPU readback is not | CPU readback of full frames can't reach the frame rate target |
| 10 | Apple bridge: MapLibre renders into borrowed Metal textures backed by a set of three IOSurface-backed `CVPixelBuffer`s; fallback: one texture plus a Metal blit | Zero-copy, if switching the target texture each frame costs little (section 7) |
| 11 | One package, `flutter_map_maplibre_texture`, with an internal boundary: `lib/src/texture/` must not import `flutter_map` | Avoids coordinated releases of two packages while the texture core API is changing; can be split later without renaming (section 5) |

## 4. Integration model

We considered two models.

**Model A (chosen): MapLibre as the `flutter_map` base layer.** `flutter_map` controls gestures, camera animation and overlays. MapLibre renders only the base map at the camera it receives. The map widget is one layer among `flutter_map`'s children:

```dart
// Illustrative, not yet implemented.
FlutterMap(
  children: [
    MapLibreTextureLayer(style: '...'),   // fills the viewport, follows the camera
    PolylineLayer(polylines: routes),
    MarkerLayer(markers: weatherMarkers),
  ],
)
```

**Model B (fallback): MapLibre controls the map.** MapLibre controls gestures and camera animation, and Flutter overlays follow MapLibre's camera. It needs a much larger API (section 6). We would move to model B only if model A can't keep the texture aligned with the overlays (section 8).

## 5. Architecture

### Package layout

```
packages/flutter_map_maplibre_texture/
  lib/src/texture/   Dart API: controller, widget, @Native bindings
                     (must not import package:flutter_map; a test checks this)
  lib/src/layer/     flutter_map layer (after the texture core works)
  src/core/          native core (C/C++): map thread, commands, events (no platform deps)
  macos/, ios/       Metal bridge (shared code)
  android/           EGL or Vulkan bridge
example/             test app: map, Flutter overlay, camera controls
```

We call `lib/src/texture/` together with the native code the texture core. If a user other than the `flutter_map` layer needs the texture core, we move it into a separate package. This package keeps its name and becomes the layer.

### Threads

The MapLibre C API binds the runtime, map, camera and style calls to the map owner thread, and render session calls to the thread that attached the session. A call from another thread returns `MLN_STATUS_WRONG_THREAD`. In Dart, only the main isolate stays on one OS thread (the Flutter UI thread), so Dart could only own MapLibre objects on the thread that builds Flutter frames. We put them on a native thread instead.

```
 Dart main isolate (UI thread)       native core                       Flutter engine
 -----------------------------      --------------------------        -------------
 setCamera(c) via dart:ffi
   writes latest-camera slot ----->  map thread (owns runtime,
   signals wake source       ----->    map and render session)
                                      pump runtime, apply commands
                                      on render update available:
                                        set_target(free buffer)
                                        render_update (waits for GPU)
                                        read frame camera
                                        publish buffer ------------->  raster thread:
                                        textureFrameAvailable          copyPixelBuffer
 NativeCallable.listener  <--------  events: style loaded, errors,
 (async on the isolate)               idle, frame displayed + camera
```

- **Camera updates are coalesced.** Dart overwrites a single latest-camera slot. The map thread reads only the latest camera when it wakes, so a gesture doesn't produce a queue of old cameras.
- **Other commands are ordered.** Style loads, resize and dispose go into a queue, because the map thread must not drop or reorder them.
- **Rendering is on demand.** The map thread renders only after MapLibre reports a render update (camera, style, data or size change, or a style transition). An idle map renders no frames.
- **One thread at first.** The runtime, map and session share one thread. If style or tile work delays frames, we move the session to its own thread. The C API allows this without changing the Dart API.

We considered having Dart's main isolate own the runtime and map through the official `maplibre_native_ffi` Dart binding, with only the session on a native thread. It would give the full map API without our own wrappers. We rejected it because it puts runtime pumping on Flutter's UI thread, it requires passing the map handle between Dart and native code (both must load the same library instance, which we haven't verified), and it still needs a native thread. We would reconsider it if we move to model B.

## 6. API surface

**Proof of concept (POC), macOS vertical slice:** create, load style (URL or JSON), set camera (center, zoom, bearing), resize (logical size and device pixel ratio), dispose; events for style loaded, load failure, render error and idle; the camera and frame id of each displayed frame.

**Model A beyond the POC** (about 20 to 30 C functions, each of which makes one or a few C API calls on the map thread):

| Area | Operations |
|---|---|
| Lifecycle | pause/resume, memory pressure |
| Viewport | padding |
| Style | replace style; set layer visibility, paint and layout properties, filters |
| Network and resources | URL transform or request headers (API keys), cache path and size limit |
| Events | map idle or fully loaded, rendered camera for each frame |
| Attribution | source attribution strings from the style |
| Queries (optional) | features rendered at a point or in a box |

**Model B** would add gestures and camera animation in MapLibre, GeoJSON sources, layers, images, annotations, screen/geo projection, offline regions and snapshots: well over 100 operations. At that size, writing a wrapper for each operation costs too much, and the official Dart binding would be the better choice.

## 7. Platform bridges

### macOS and iOS (shared)

1. Allocate three IOSurface-backed `CVPixelBuffer`s (`kCVPixelFormatType_32BGRA`), and create an `MTLTexture` for each through `CVMetalTextureCache`.
2. Attach the render session to one of them with `mln_metal_borrowed_texture_attach()`.
3. Before each frame, switch the target texture to a free buffer with `mln_metal_borrowed_texture_set_target()`, then call `mln_render_session_render_update()`. For borrowed textures it commits and waits for the GPU (`waitUntilCompleted`) before returning, so the buffer is complete when the call returns.
4. Publish the buffer as latest and notify Flutter. `copyPixelBuffer` on Flutter's raster thread returns it.

There are three buffers so that MapLibre never writes to the one Flutter shows now or may still sample: **latest** (the last completed frame), **presented** (the one `copyPixelBuffer` returned last) and **free** (the render target). If no buffer is free, the map thread skips rendering until one is.

**Fallback:** if switching the target texture each frame costs too much, MapLibre renders into one borrowed texture, and each frame is copied into a free buffer with a Metal blit. That is one GPU copy each frame, which decision 9 allows.

macOS and iOS differ mainly in plugin registration, display scale changes (macOS windows move between displays) and app lifecycle (iOS backgrounding).

### Android

`TextureRegistry.SurfaceProducer` provides an Android `Surface`. MapLibre attaches to it as a native surface render target (EGL, or Vulkan if measurements show it is faster). The Android-specific work is surface loss and recreation (`onSurfaceCleanup`/`onSurfaceAvailable`), packaging one library per ABI, and the Rustls platform-verifier helper that the FFI needs for HTTPS on Android. Whether `SurfaceProducer` is zero-copy depends on the Flutter version and renderer (Impeller uses `ImageReader` and `HardwareBuffer`), so record both with every measurement.

## 8. Camera alignment with `flutter_map`

In model A, Flutter draws the overlays and MapLibre renders the map texture, on different threads:

```
 gesture (frame N) --> flutter_map camera C_N --> overlays drawn at C_N in frame N
                  \--> setCamera(C_N) --> map thread renders C_N --> ready at N+1 or N+2
                                                      Flutter shows texture of C_(N-1) or C_(N-2)
```

During a pan, the overlays are at the current camera and the texture lags them by one or two frames. Rendering faster doesn't remove this lag, because the pipeline causes it. We plan to correct it in Flutter:

- **Compensating transform (preferred).** Each displayed frame reports the camera it was rendered with (from `mln_render_session_projection_create()` and `mln_map_projection_get_camera()`). Flutter wraps the `Texture` in a `Transform` that maps the rendered camera to the current `flutter_map` camera. For pan, zoom and rotation without pitch, this is a similarity transform in Web Mercator, so it is exact except at the edges. Rendering a margin beyond the viewport (overscan) provides pixels for the edges during fast pans.
- **Overlays follow the texture (alternative).** Position overlays at the camera of the last displayed frame. Alignment is exact, but every overlay gets one or two frames of input latency.

Camera conversion between the engines, confirmed by `flutter_map_maplibre`: MapLibre zoom = `flutter_map` zoom − 1 (512 px vs 256 px tiles), MapLibre bearing = −`flutter_map` rotation, pitch fixed at 0.

Test alignment with:

- pan, pinch zoom, rotation and animated camera transitions;
- viewport resize, device pixel ratio changes and map padding;
- world wrap, antimeridian crossing and high latitudes.

Measure alignment by comparing the screen positions of fixed coordinates in the texture and in the overlays throughout gestures.

The macOS vertical slice includes the camera report for each displayed frame, so the alignment work can start without changes to the native API.

## 9. Prior art

- **PR #906 and discussion #907** ([discussion](https://github.com/maplibre/flutter-maplibre-gl/discussions/907), [PR](https://github.com/maplibre/flutter-maplibre-gl/pull/906)). An Android arm64 experiment that uses `maplibre-native-ffi` and a Flutter `Texture` behind the `maplibre_gl` API. It reported lower gesture frame rates than the existing plugin at the time. We use it for ideas only.
- **`flutter_map_maplibre`** by josxha ([pub.dev](https://pub.dev/packages/flutter_map_maplibre), v0.0.5, 2025-09-30, MIT). It implements model A by putting the `maplibre` package's native MapLibre SDK view inside `FlutterMap`, with MapLibre gestures disabled. It sends each `flutter_map` move event as a camera update, with no coalescing and no lag compensation. It also offers model B (`flutter_map` layers inside a MapLibre map). It's the closest existing solution and our comparison baseline. josxha maintains both `maplibre` and this adapter, so working together (for example, a texture backend for `maplibre`) is an option to discuss before we publish.

## 10. MapLibre Native FFI facts

We checked these facts in the source at commit `dd97d20f8fab6990cd87c13f091ce00e662707bd` (HEAD on 2026-10-09). The C ABI is pre-1.0 and unstable. Pin an exact commit, and recheck these facts when updating it.

- Presets: `macos-arm64-metal`, `ios-arm64-metal`, `ios-simulator-arm64-metal`, `android-arm64-egl`, `android-arm64-vulkan`, and others.
- Metal supports surface, session-owned texture and borrowed texture targets (`include/maplibre_native_c/texture.h`, `surface.h`).
- A borrowed Metal texture must be render-target capable, single-sample and exactly the declared physical size.
- `mln_metal_borrowed_texture_set_target()` keeps the renderer, tile pyramid, glyph atlases and symbol placement; it rejects a different pixel format, and a different `scale_factor` rebuilds the renderer.
- Borrowed-texture `render_update` waits for GPU completion (`src/render/metal/metal_texture_backend.mm`).
- `mln_render_session_projection_create()` captures the last rendered frame's transform; `mln_map_projection_get_camera()` reads its camera.
- `mln_wake_source_signal()` can be called from any thread.
- The Dart binding `maplibre_native_ffi` exists (Dart SDK ^3.11, distributed as a code asset). Under decision 8 we don't use it.

## 11. Performance targets and measurement

- **Thresholds:** at least 30 fps during continuous camera changes on Mac, Android and iPhone; target 60 fps or the display refresh rate.
- **Comparison:** `flutter_map_maplibre` on the same device, style and camera path. `maplibre_gl` is optional.
- **Measured values:** median, p95 and p99 frame durations; displayed map frame rate; Flutter UI and raster time; native `render_update` and GPU time; skipped renders; CPU and GPU utilization and thermal state; memory and thread count across repeated create/dispose; time to first usable map; tiles decoded and loaded, and cache behavior; label clarity and stability during camera changes; app size increase; texture-to-overlay error in pixels (from the alignment work onward).
- **Comparable conditions:** use the same style, geographic extent, geometry density, labels, tile source, window size and device for every implementation. Warm caches the same way for each run, and report cold start separately.
- **Record with every measurement:** device, OS, Flutter version and renderer, FFI commit, build mode, style, window size.
- **Correctness conditions:** test under slow network, no network, background/foreground, repeated widget mount/unmount, orientation change, device pixel ratio change, and surface destruction and recreation.

## 12. Risks and open questions

| Risk or question | How we resolve it |
|---|---|
| Switching the target texture each frame may cost too much (for example, a `MLN_RENDER_RESULT_SIZE_PENDING` result after every switch) | Measure it first in the macOS vertical slice; use the blit fallback if needed |
| `waitUntilCompleted` runs CPU encoding and GPU work one after the other | Measure both; move the session to its own thread if it limits the frame rate |
| Whether `textureFrameAvailable:` can be called off the platform thread | Check the embedder; dispatch to the main queue if not |
| How long Flutter holds a returned `CVPixelBuffer` | Three buffers and skip-when-none-free; four buffers if skips are frequent |
| BGRA and color space mismatch | Compare known fill colors; set the IOSurface color space explicitly |
| The texture lags the overlays during gestures | Compensating transform (section 8); model B if alignment fails |
| Pre-1.0 FFI ABI changes | Pin the commit; keep all MapLibre calls in the native core |
| Licenses and app size | Review MapLibre Native and FFI licenses and third-party notices; record the size increase for each platform |
| Offline map regions | Not needed for model A's first vertical slices; decide later whether the disk cache is enough |

## 13. Roadmap

| Stage | Content | Go/no-go | Decision |
|---|---|---|---|
| 0. Reconnaissance | Done: this document and the FFI source check | Done | Continue |
| 1. macOS vertical slice | Texture display, style, camera, resize, lifecycle, camera report for each frame, measurements | ≥30 fps and no CPU readback; if slow, find whether rendering, passing frames to Flutter, scheduling or synchronization causes it | Continue (2026-10-09): median 119 fps during continuous pan on an M2 Max, no CPU readback ([benchmarks](../benchmarks.md), [limitations](../limitations.md)) |
| 2. iOS | Reuse the Metal bridge; iOS lifecycle; device measurements | ≥30 fps on iPhone | Continue (2026-10-10): over central London the iPhone 15 Pro Max displayed 99–100 map frames per second at the median second (p10 87, lowest second 85) with rendering ahead; no CPU readback; no rendering in the background ([benchmarks](../benchmarks.md), [limitations](../limitations.md)) |
| 3. `flutter_map` layer | Layer widget, camera conversion, compensating transform, alignment and lag measurements, comparison with `flutter_map_maplibre` | If the texture is visibly misaligned with the overlays, don't present it as a drop-in base layer; consider model B | |
| 4. Android | `SurfaceProducer` bridge, surface lifecycle, packaging, measurements | ≥30 fps on the reference Android device | |

Each stage ends with one of three decisions: continue, adopt an existing solution (for example `flutter_map_maplibre`), or stop.

## 14. Working rules

These rules apply to anyone implementing this design, including coding agents.

- Read the C headers, Dart bindings and examples at the pinned FFI commit before choosing API calls. Don't infer signatures from illustrative examples.
- Label pseudocode as pseudocode. Never present a guessed API as compiling code.
- Pin every dependency revision, and document build prerequisites and exact commands.
- Don't use CPU readback as a workaround on the interaction path. If it is unavoidable, mark the stage as unsuccessful.
- Treat camera alignment, native resource lifetime and frame synchronization as requirements, not as later improvements.
- Keep a list of blockers and uncertainties, with evidence and links.
- Don't claim success from source code alone. Run builds and tests on available devices, and report which verification you couldn't run.
- Don't modify `dart-vector-tile-renderer` or `flutter-vector-map-tiles`.

## 15. References

- [MapLibre Native FFI](https://maplibre.org/maplibre-native-ffi/): [concepts](https://maplibre.org/maplibre-native-ffi/concepts/), [render targets](https://maplibre.org/maplibre-native-ffi/guides/attach-a-render-target/), [render loop](https://maplibre.org/maplibre-native-ffi/guides/run-the-render-loop/), [repository](https://github.com/maplibre/maplibre-native-ffi)
- [Flutter `Texture` widget](https://api.flutter.dev/flutter/widgets/Texture-class.html), [`FlutterTexture` protocol](https://api.flutter.dev/ios-embedder/protocol_flutter_texture-p.html), [Android `SurfaceProducer`](https://docs.flutter.dev/release/breaking-changes/android-surface-plugins)
- [`flutter_map` plugin guide](https://docs.fleaflet.dev/plugins/making-a-plugin)
- [`flutter_map_maplibre`](https://github.com/josxha/flutter_map_plugins/tree/main/flutter_map_maplibre)
