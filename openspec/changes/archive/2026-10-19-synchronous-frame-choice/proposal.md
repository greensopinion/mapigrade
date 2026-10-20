## Why

On the Pixel 4a (5G), Dart chooses about 49 of the 58 map frames that the map renders per second, and the displayed map frame interval has a p99 of about 84 ms and a maximum of about 200 ms, so pans stutter. The documentation and design D134 of the android-layer-children-alignment change say that the map's render clock drifts against the display refresh and causes this. A trace of the benchmark on 2026-10-19 showed that this explanation is wrong.

Renders already start at a fixed point after each vsync, because Dart's `setCamera` call in each build starts them. A frame becomes finished only when its GPU work completes: `ImageReader.acquireNextImage` waits on the frame's GPU fence, about 11 ms after the swap. Frames therefore become finished 10 to 16 ms after a vsync. When one becomes finished in the last 1 to 2 ms before the next vsync, its finished-frame report reaches Dart after Flutter has started the next build. Before the following build, the map replaces that frame with a newer one. Dart then chooses the frame it was told about, the choice is refused, and Dart displays the previous frame again. This can repeat for several Flutter frames. A simulation of the frame choice from the trace's timestamps reproduced the measured frame rate and interval percentiles. With Dart choosing the newest finished frame that the map holds when Dart builds a Flutter frame, the simulation gave 54 frames per second and no interval over 35 ms.

## What Changes

- The map gets a call that chooses the newest finished frame at the time of the call and returns that frame's identifier, slot, camera, viewport size and camera sequence number. If no frame newer than the frame chosen before is finished, the call reports that and records nothing. A choice through this call is never refused.
- `MapigradeLayer` and `MapTextureView` choose with this call in each build, instead of choosing the frame of the last finished-frame report. Finished-frame reports still tell Dart to build a Flutter frame. This applies on every platform, so that Dart keeps no Android-specific code path (design D138 of android-layer-children-alignment). The macOS and iOS benchmarks are rerun to check that they don't regress.
- The Android benchmark result, `docs/limitations.md`, `docs/benchmarks.md`, `docs/camera-alignment-options.md` and `docs/platform-view-comparison.md` are corrected: the stutter came from frames that became finished just before a vsync and were then replaced, not from clock drift. The trace results are recorded in `docs/benchmarks.md`.
- Not in this change: pacing renders by `AChoreographer` callbacks, delaying the render start so that frames become finished in the middle of the refresh interval (the simulation gave about 3 more frames per second for 8 ms of added latency), and making frames available before their GPU fence signals (Android's `ImageReader` Java API offers no acquisition without the wait).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: requirement "Display slots" changes from Dart choosing a frame it was told about, which the system may refuse, to Dart asking the system to choose the newest finished frame when Dart builds a Flutter frame. The system returns that frame's camera, so that Dart can draw children at it.

## Impact

- Native core (`packages/flutter_mapigrade/src/core/`): a new C ABI function that replaces `map_texture_select`, and `BufferState` support for choosing the newest finished frame under its lock.
- Dart (`lib/src/texture/map_texture_controller.dart`, `map_texture_view.dart`, `lib/src/layer/map_texture_layer.dart`) and their tests. The public API doesn't change, because `MapTextureController` is internal.
- Integration tests in `packages/test_harness` that call `select` with a frame that has been replaced.
- Benchmarks on the Pixel, the Mac and the iPhone, and the documentation listed above.
