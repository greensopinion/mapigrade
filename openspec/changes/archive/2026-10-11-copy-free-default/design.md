## Context

See proposal.md for the motivation. The frame path before this change: the render session renders into one private `MTLTexture`, and `MetalRenderTarget::CopyToBuffer` copies each frame with an `MTLBlitCommandEncoder` into the free one of three IOSurface-backed `CVPixelBuffer`s (designs D3b and D4). D20 of the iOS slice added an experimental path, selected for the whole process by a test hook, in which `RenderTarget::SelectBuffer` makes the free buffer the session's target with `mln_metal_borrowed_texture_set_target()` before each render. It needed a local FFI patch, because the FFI posted the size to the map on every `set_target`, and the map then published a new render update after every frame.

## Goals / Non-Goals

**Goals:**
- Copy-free rendering is the default path, with the copy kept as a per-map option.
- Both paths stay covered by the integration suite, whichever path the suite is run with.

**Non-Goals:**
- Choosing the path automatically per device. On the Mac copy-free gives no consistent gain, but it isn't slower either, and one default is simpler to test and explain.

## Decisions

### D37. Copy-free is the default (supersedes D3b, closes D20)

Maps render directly into the display buffers unless they are created with `copyFree: false`. D3b made the copy the only path because of the FFI's behavior, which #807 fixed. D20's measurements were made with a local patch; the decision rests on the measurements at the pinned commit `6f5a662` (`benchmarks.md`, "Copy-free with the upstream FFI fix" and the sections it points to):

- iPhone 15 Pro Max, two sessions of 3 runs each: median second 109–111 fps against 98–102 with the copy, lowest second 98–104 against 83–88. A 5-minute run held 109.7–111.6 fps per 30 s interval (the copy: 97.5–98.9), with the thermal state nominal throughout in both.
- M2 Max Mac at 3200x2000: no consistent gain. `render_update` is about 0.7 ms longer, more than the 0.5 ms copy; the average frame rate was within the run-to-run range of the copy in both sessions.
- Memory on the iPhone: about 8 MiB less before a memory reduction and about 14 MiB less after it; the private texture is 13.8 MiB.
- Alignment: with the transform, the same p50 and p95 errors in every phase on both devices, except a lower p95 in the Mac's zoom phase, so the camera-prediction change's baseline holds.

*Alternative:* keep the copy as the default and offer copy-free as an option. Rejected: the iPhone is the more constrained device and gains the most, and on the Mac copy-free isn't slower.

### D38. The path is chosen per map, when the map is created

`map_texture_create` takes a `copy_free` argument, `MapTexture::Create` passes it to `CreatePlatformRenderTarget`, and the Dart API exposes it as `copyFree` on `MapTextureController.create` and `MapLibreTextureLayer`. The process-wide test hook `map_texture_set_zero_copy_for_testing` is removed. A render target can't change paths after it is created: the copy path allocates a private texture with each buffer set, and the copy-free path attaches the session to a display buffer.

*Alternative:* keep a process-wide switch. Rejected: an application with two maps couldn't choose per map, and a test couldn't run both paths in one suite.

### D39. The copy path stays

`copyFree: false` keeps the private texture and the blit. It is the fallback if a device or a future FFI version makes the copy-free path slower or wrong, and it lets the benchmarks compare both paths. The integration suite runs "renders frames without copies" and "idle map renders no frames for 10 seconds" in each mode explicitly, and `--dart-define=COPY=true` runs the rest of the suite with the copy.

### D40. The FFI pin moves to `6f5a662`, with no local patches

maplibre-native-ffi#807 skips posting the size to the map when a `set_target` keeps the session's width and height. Unlike the first version of the local patch that D20 measured, the session still resets its record of the rendered update, so the next `render_update` draws the latest render update into the new target. The pin also brings #806 (a MapLibre Native patch for color ramps). `scripts/build_maplibre_ffi.sh` still applies `scripts/patches/` if the directory exists.

### D41. The per-target depth and stencil allocation stays

Every borrowed Metal `set_target` drops the renderable resource, so the next frame allocates new depth and stencil textures. An FFI change that kept them across same-size targets (`~/git/maplibre-native-ffi/HANDOFF2.md`) shortened copy-free `render_update` by 0.3 ms on the Mac but lengthened it by 0.4–0.9 ms on the iPhone, measured against the unpatched FFI in the same session. We abandoned it. The cause on the iPhone wasn't investigated.

### D42. The undisplayed frames are accepted

A copy-free frame costs about one refresh interval on the iPhone, and the map renders ahead (D19) almost all the time, so 7–9% of rendered frames are replaced before Flutter displays them, against 3–5% with the copy. Counting those frames, copy-free spends 8.2–8.6 ms of map-thread render time per displayed frame, against 9.9–10.1 ms with the copy. Lowering the render-ahead threshold wouldn't reduce the waste, because copy-free already renders ahead almost all the time.

*Alternative not tried:* render ahead by at most one frame (don't start a frame ahead of Flutter if the latest one was itself rendered ahead). It may let the GPU drop to a lower performance state, as pacing did (D19).

## Risks / Trade-offs

- [The map thread's render time isn't an energy measurement; the thermal state has four levels] → The 5-minute runs showed no thermal difference; an Instruments energy trace would measure energy directly if it becomes a concern.
- [A future FFI version could again post the size or publish an update on a same-size `set_target`] → The integration test "idle copy-free map renders no frames for 10 seconds" fails in that case; `copyFree: false` is the fallback.
- [The Mac gains nothing from the default] → Accepted (D37); applications can pass `copyFree: false`.
- [The headline frame-rate table in `benchmarks.md` was measured with the copy at the old pin] → Task 3.1 measures the default again.

## Migration Plan

There are no users of the package besides the example. Code that calls `map_texture_create` directly must pass the new argument, and tests that called `setZeroCopyForTesting` pass `copyFree` when they create a map. Rollback: change the two Dart defaults to `false`.
