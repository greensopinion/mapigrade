## Why

Since the macOS slice, MapLibre rendered into one private texture and each frame was copied on the GPU into the display buffer that Flutter shows (design D3b), because switching the render target before each frame made the map render without end. Rendering directly into the display buffers (D20) was an experiment that needed a local FFI patch. The fix was merged upstream as maplibre-native-ffi#807 on 2026-10-11. Measured that day, copy-free rendering displays about 10 more map frames per second on the iPhone 15 Pro Max at the median second and about 15 more at the slowest, and it uses about 14 MiB less memory. So we made it the default and kept the copy as an option.

This change records that decision. The code was changed on 2026-10-11, before this change was written; its tasks record the work done and the verification, and list what remains.

## What Changes

- Maps are copy-free by default: before each render, the free display buffer becomes the render session's target, and MapLibre renders directly into it. `MapTextureController.create(copyFree:)` and `MapLibreTextureLayer(copyFree:)` default to `true`; `copyFree: false` keeps the private render texture and the GPU copy.
- The C ABI's `map_texture_create` takes a `copy_free` argument, which replaces the process-wide test hook `map_texture_set_zero_copy_for_testing` (and Dart's `setZeroCopyForTesting`). `copy_count` stays 0 for a copy-free map.
- The FFI pin moves from `dd97d20` to `6f5a662` (#807), and the local patch `scripts/patches/maplibre-native-ffi-set-target-same-extent.patch` is deleted.
- The example selects the copy with `--dart-define=COPY=true` (it was `COPY_FREE=true` while copy-free was the option). The integration suite runs two tests in each mode regardless of the define.
- Measurements in `benchmarks.md` and `limitations.md`: frame rate on both devices, render time per displayed frame, a 5-minute run, memory, and alignment in both modes.

Out of scope: removing the copy path; an FFI change that keeps the depth and stencil textures across same-size targets (tried and abandoned: faster on the Mac, slower on the iPhone); Android.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: a new requirement "Copy-free rendering by default", with the copy as an option and both modes rendering nothing while the map is idle.

## Impact

- Code: `packages/flutter_mapigrade/src/core/` (`map_texture_api.h/.cpp`, `map_texture.h/.cpp`, `render_target.h`), `darwin/.../MapTextureMetal.mm`, `lib/src/texture/` (bindings, controller, testing hooks), `lib/src/layer/map_libre_texture_layer.dart`; the example's pages, benchmarks and integration tests.
- API: **BREAKING** for the C ABI (`map_texture_create` gains an argument; the zero-copy test hook is removed) and for the Dart testing library (`setZeroCopyForTesting` is removed). The public Dart API gains an optional `copyFree` parameter; existing calls get copy-free maps.
- Dependencies: MapLibre Native FFI `6f5a662`, with no local patches.
- Behavior: on the Mac, copy-free gives no consistent frame-rate gain (`render_update` is about 0.7 ms longer, more than the 0.5 ms copy); on the iPhone, 7–9% of rendered frames are not displayed, against 3–5% with the copy.
