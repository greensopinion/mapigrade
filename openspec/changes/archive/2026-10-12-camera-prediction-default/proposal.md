## Why

The camera-prediction change measured camera prediction instead of the compensating transform, and on 2026-10-11 we decided to make prediction with a lead of 1 display refresh interval the default of `MapLibreTextureLayer` (`openspec/changes/archive/2026-10-11-camera-prediction/design.md`, "Results and decision"). It missed the measured pan criterion (pan1000 p50 8.33 px on the iPhone, 0 or 8.33 px on the Mac; limit 4 px) and met the fling criterion. In the manual check on the Mac and the iPhone it felt best: the overlays floated only while a fling decelerated, and no strips were uncovered at the edges. The transform floated and uncovered 16 px strips.

Today the layer selects its alignment with two experimental parameters, `compensatingTransform` and `cameraPrediction`, and prediction ignores `compensatingTransform`. With prediction as the default, the default value of `compensatingTransform` (true) would have no effect, which misleads readers of the API.

## What Changes

- **BREAKING** (experimental API only): `MapLibreTextureLayer` replaces `compensatingTransform` and `cameraPrediction` with one parameter, `alignment`. Its values are camera prediction with a lead in refresh intervals, the compensating transform, or neither.
- The default of `alignment` is camera prediction with a lead of 1, drawn without the transform. **BREAKING** for applications that rely on the default drawing with the transform: they select the transform explicitly.
- The example's `flutter_map` page, the alignment benchmark and the integration tests use `alignment`. The page starts in `predict1` mode. The benchmark's `ALIGNMENT_MODE` values and their default (`transform`) don't change, so the procedures in `benchmarks.md` measure what they measured before.
- The tests cover the new default: the static alignment cases run with the default layer and with the transform.
- The documentation describes the new default and the parameter: the layer's API documentation, `limitations.md`, `docs/camera-alignment-options.md` and roadmap row 3 of the concept document.

Out of scope: removing the transform code, a different lead per platform or display refresh rate, an adaptive lead, a benchmark with drag input timing, and Android.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: "Camera prediction" is on by default with a lead of 1; "Compensating transform" applies only when the layer is configured with it; the layer offers one alignment option with three values instead of two independent options; "Alignment measurement" names its configurations (transform, neither, prediction at a stated lead) instead of "the default".

## Impact

- Code: `packages/flutter_mapigrade/lib/src/layer/` (the alignment type, the layer's parameter and its documentation; the type is exported from `package:flutter_mapigrade/flutter_mapigrade.dart`); `example/lib/alignment_mode.dart`, `flutter_map_page.dart` and `alignment_benchmark.dart`. The predictor, the transform, the native core and `lib/src/texture/` don't change.
- API: `compensatingTransform` and `cameraPrediction` are removed; `alignment` is added. Both removed parameters were marked experimental and existed only since the camera-prediction change.
- Tests: `example/integration_test/static_alignment_test.dart` and `map_layer_test.dart`.
- Documentation: `limitations.md`, `docs/camera-alignment-options.md`, `docs/maplibre-native-ffi-flutter-texture-concept.md`, `packages/flutter_mapigrade/lib/src/layer/README.md`.
