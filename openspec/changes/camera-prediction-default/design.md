## Context

See proposal.md for motivation and scope, and specs/map-layer/spec.md for the requirements. The designs of the flutter-map-layer change (D21 to D30) and the camera-prediction change (D31 to D36, `openspec/changes/archive/2026-10-11-camera-prediction/design.md`) apply, except where a decision here replaces one. Decisions here are numbered from D43.

Current state, as checked in this repository on 2026-10-11:

- `MapLibreTextureLayer` (`packages/flutter_mapigrade/lib/src/layer/map_libre_texture_layer.dart`) has two experimental parameters (D31): `compensatingTransform` (bool, default true) and `cameraPrediction` (lead in refresh intervals, default null = off). When `cameraPrediction` is set, the layer ignores `compensatingTransform` and draws without the transform. When `cameraPrediction` changes, `didUpdateWidget` replaces the predictor.
- The layer rebuilds on every displayed frame (its `frames` listener). The transform needs this rebuild, and so does prediction: the rebuild after the camera stops sets the converted camera instead of the last predicted one (D32).
- The package is version 0.0.1 with `publish_to: none`, so no published application depends on the parameters.
- The example passes both parameters explicitly from `AlignmentMode` (`example/lib/alignment_mode.dart`): in the `flutter_map` page, the alignment benchmark, and `map_layer_test.dart`. `static_alignment_test.dart` passes only `cameraPrediction` (null or 2). The test "the layer fills the FlutterMap below the markers" uses the defaults.

## Goals / Non-Goals

**Goals:**
- An API in which every value of the alignment option has an effect, and the default is prediction with a lead of 1.
- The measured and checked behavior of each mode stays as it was in the camera-prediction change.

**Non-Goals:**
- Changing the predictor, the transform, or which frames trigger a rebuild.
- New measurements: the camera-prediction change measured `predict1` and `transform` on both reference devices, and this change doesn't change what they draw.

## Decisions

### D43. One alignment parameter (replaces D31)

`MapLibreTextureLayer` gets one parameter, `alignment`, of a new type `CameraAlignment` in `lib/src/layer/`, exported from `package:flutter_mapigrade/flutter_mapigrade.dart`. It has three values:

- `CameraAlignment.prediction({double lead = 1})`: camera prediction (D32, D33) with the lead in display refresh intervals; drawn without the transform. `lead` must be greater than 0.
- `CameraAlignment.transform`: the compensating transform (D23), without prediction.
- `CameraAlignment.none`: neither.

The default is `const CameraAlignment.prediction()`. The type has value equality, so `didUpdateWidget` replaces the predictor only when the alignment changes, as it does now when `cameraPrediction` changes. `compensatingTransform` and `cameraPrediction` are removed.

*Alternatives:*
- Keep both parameters and change the default of `cameraPrediction` to 1. That is the smallest change, but the default `compensatingTransform: true` would then have no effect, and turning prediction off would mean passing `null`.
- An enum with a separate `lead` parameter. Then `lead` has no effect with the transform or with neither, which is the same problem in another form.

### D44. The documentation states the trade-off

The API documentation of `alignment` states what each value does during camera changes: with prediction (lead 1), the map trails the overlays by up to about one frame of movement in steady pans on the reference devices (0.5 to 0.95 frames on average), and runs ahead briefly after an abrupt stop or reversal; with the transform, the map is about one frame ahead and the viewport edges show uncovered strips; with neither, it trails by about two frames. It names `benchmarks.md` as the source of the numbers. The class documentation of `MapLibreTextureLayer` describes prediction instead of the transform.

### D45. The example keeps its mode names; the benchmark default stays `transform`

`AlignmentMode` maps each mode to a `CameraAlignment` instead of two parameter values, and keeps its labels (`transform`, `none`, `predict1` to `predict3`). The `flutter_map` page starts in `predict1`, the new default. `ALIGNMENT_MODE` keeps its default `transform`, so the procedures already recorded in `benchmarks.md` (which don't set it) still measure the transform.

*Alternative:* default the benchmark to the layer's default. Then the Stage 3 procedure would silently measure prediction.

### D46. Test coverage

- `static_alignment_test.dart` runs every case with the default layer (prediction, lead 1) and with `CameraAlignment.transform`, instead of with the default (then the transform) and with lead 2. Lead 2 is no longer offered in the API documentation as a recommendation, and lead 1 is now the default.
- `map_layer_test.dart` names the configuration of each Transform test (`transform`, `none`, `prediction`) instead of "the default layer", and adds a test that the layer built without `alignment` has no `Transform` while the camera moves. The test "with prediction, the map shows the converted camera after a camera move stops" uses the default layer.
- A unit test checks `CameraAlignment`'s defaults and equality.

## Risks / Trade-offs

- [Prediction was measured only on two 120 Hz devices; at 60 Hz a lead of 1 interval is twice as long in time, and the lag in refresh intervals may differ] → The lead is in refresh intervals, which scales with the display. Stage 4 (Android) measures the default on its reference device; `limitations.md` states that only 120 Hz was measured.
- [Applications that relied on the transform get prediction] → The package is unpublished; within this repository every use is updated by this change.
- [The benchmark default (`transform`) and the layer default (prediction) differ] → The benchmark states the mode in every result line, and its header comment names the default.

## Migration Plan

Replace `compensatingTransform: false` with `alignment: CameraAlignment.none`, `cameraPrediction: n` with `alignment: CameraAlignment.prediction(lead: n)`, and the old default with `alignment: CameraAlignment.transform`. Rolling back means reverting this change; the transform code stays.
