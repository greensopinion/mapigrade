## Why

Stage 3 accepted the `flutter_map` layer with a visible offset during camera changes: with the compensating transform the map is one Flutter frame of camera movement off the overlays at p50, 8.33 logical px during a pan at 1,000 px/s, and the transform uncovers 16 px strips at the viewport edges (`docs/camera-alignment-options.md`, `benchmarks.md`). The Stage 3 decision named camera prediction (option 5) as the next experiment, before Stage 4, because it is Dart code in the layer and Android would get it too.

Camera prediction can't improve on the transform when both are used: the transform maps the frame it was built for exactly to the current camera, so the remaining error is the camera difference between that frame and the newer frame Flutter displays, one frame of movement, whether or not both frames were rendered at a predicted camera. The experiment therefore tests prediction instead of the transform. Without the transform the map is two Flutter frames of movement behind at p50 and three at p95, so a prediction two frames ahead should bring the p50 error close to 0 without strips. The risk is overshoot when a gesture stops or reverses, which a constant-speed pan doesn't show.

## What Changes

- Add an experimental camera prediction mode to `MapLibreTextureLayer`: the layer sends MapLibre the `flutter_map` camera extrapolated from its recent velocity by a configurable number of display refresh intervals, and draws the texture without the compensating transform. The current behavior stays the default.
- Add the layer option to turn the compensating transform off, which the prediction mode uses and which the benchmark also measures alone.
- Extend the alignment benchmark: a mode selected at build time (transform, or prediction with a lead of 1, 2 or 3 refresh intervals), new phases in which the pan stops abruptly, decelerates like a `flutter_map` fling, and reverses, and an overshoot measure for the time after a stop.
- Add a switch for the mode to the example's `flutter_map` page, for a manual check of how dragging and flinging feel.
- Measure on the reference Mac and the reference iPhone, and decide with the criteria set in Stage 3: keep prediction if the p50 offset during the pan at 1,000 px/s is at most 4 logical px and the overshoot after a stop is smaller than the current offset (8.33 px); otherwise record the result and drop it.

Out of scope: making prediction the default (a decision recorded at the end, implemented separately if taken), prediction combined with the transform (no gain, see Why), overscan, per-buffer textures, pitch, and Android.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: "Compensating transform" can be turned off by a layer option; a new requirement "Camera prediction" for the experimental mode; "Alignment measurement" gains stop, deceleration and reversal phases and an overshoot measure.

## Impact

- Code: `packages/flutter_mapigrade/lib/src/layer/` (prediction, layer options); `example/lib/alignment_benchmark.dart` (modes, phases, overshoot); `example/lib/flutter_map_page.dart` (mode switch). The native core and `lib/src/texture/` don't change.
- API: two new optional parameters on `MapLibreTextureLayer`, marked experimental; existing code keeps its behavior.
- Measurement: results in `benchmarks.md`, the decision in the change's design, `limitations.md` and `docs/camera-alignment-options.md`.
