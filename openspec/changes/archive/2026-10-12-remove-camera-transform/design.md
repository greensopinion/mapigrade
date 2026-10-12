## Context

See proposal.md for motivation and scope, and specs/map-layer/spec.md for the requirements. The designs of the flutter-map-layer change (D21 to D30), the camera-prediction change (D31 to D36) and the camera-prediction-default change (D43 to D46) apply, except where a decision here replaces one. Decisions here are numbered from D47.

Current state, as checked in this repository on 2026-10-12:

- `CameraAlignment` (`lib/src/layer/camera_alignment.dart`) has `prediction({lead = 1})`, `transform` and `none`, and `isTransform`, which only the layer reads.
- `lib/src/layer/camera_transform.dart` holds two kinds of code. The transform: `frameTransform`, `layerTransform` and its overlap test. The camera conversion and the projection: `ViewCamera`, `viewCameraOf`, `mercator`, `worldSize`, `screenPosition`, `worldPosition`. `camera_prediction.dart` and `alignment_error.dart` use the conversion and the projection. `camera_prediction.dart` has its own `_wrap`. `lib/testing.dart` exports `ViewCamera` and `viewCameraOf`.
- `alignmentError` (`alignment_error.dart`) takes the overlay camera (`target`), the frame the transform was built from (`used`) and the frame Flutter displayed (`shown`), and returns the error with and without the transform, and the center offset for each.
- The alignment benchmark (`example/lib/alignment_benchmark.dart`) records `used` for each build, counts `mismatch_fraction` (frames whose displayed frame differs from `used`), reports `error_with_transform_px`, `error_without_transform_px` and `error_drawn_px`, and picks the drawn error with `transformDrawn`. `ALIGNMENT_MODE` defaults to `transform` (D45).
- The layer rebuilds on every displayed frame. Prediction needs this rebuild so that after the camera stops the layer sets the converted camera instead of the last predicted one (D32).
- `test/layer/camera_transform_test.dart` tests `frameTransform` and `layerTransform`, and in its last group the camera conversion against `flutter_map`.

## Goals / Non-Goals

**Goals:**
- No code path that draws the map with a transform remains, and no API value selects one.
- Prediction and no alignment draw, and are measured, exactly as before.

**Non-Goals:**
- Changing the predictor, the camera conversion or the rebuild on each displayed frame.
- Changing the texture API: `FrameCamera`, `frames` and `displayedFrame` stay, because the benchmark, the timing probe and the texture tests use them.
- New measurements on Apple devices. Nothing that prediction or no alignment draws changes.

## Decisions

### D47. `CameraAlignment` keeps two values (amends D43)

`CameraAlignment.transform` and `isTransform` are removed. `CameraAlignment` keeps `prediction({double lead = 1})`, the default, and `none`, with value equality as before. The class documentation states what each value does during camera changes, as D44 requires, without the transform figures.

*Alternatives:*
- Replace the class with a nullable `lead` (null meaning none). This is the form D43 rejected, because turning prediction off would mean passing `null`.
- Keep `transform` as deprecated. The package is unpublished, so no application needs a deprecation period.

### D48. The transform code is removed; the conversion moves to `camera_projection.dart`

`frameTransform`, `layerTransform` and the overlap test are removed. The rest of `camera_transform.dart` moves unchanged to `lib/src/layer/camera_projection.dart`, so that the file name says what it holds. `camera_prediction.dart`, `alignment_error.dart`, `lib/testing.dart` and the tests import the new file. `MapLibreTextureLayer.build` wraps the `MapTextureView` only in the `ClipRect`.

D23's fallback (no transform when the frame would be out of view) goes with the transform. The camera jump test in `map_layer_test.dart` stays: it now checks the scenario "Camera jump larger than the viewport" of "Map follows the flutter_map camera".

*Alternative:* keep the file name. Readers would look for a transform in it.

### D49. The alignment error and the benchmark measure the drawn map only (amends D26, D45)

`alignmentError({required target, required shown})` returns the error of the shown frame as the layer draws it (stretched to the viewport, without a transform) and its center offset. `AlignmentError` keeps two fields, `error` and `center`.

The benchmark:

- no longer records `used` for each build, and drops `mismatch_fraction`, `error_with_transform_px`, `error_without_transform_px` and `transformDrawn`;
- keeps `error_drawn_px`, `offset_along_pan_px`, the overshoot fields and every timing and matching field under the same names, so that results stay comparable with the prediction rows in `benchmarks.md`;
- defaults `ALIGNMENT_MODE` to `predict1`, and rejects `transform` as it rejects any unknown mode.

The video mode (D29) runs in the selected mode, so its default changes from the transform to `predict1`. The capture tool doesn't change.

*Alternative:* keep `error_without_transform_px` as a second name for `error_drawn_px`. Without a transform the two are always equal.

### D50. Example and tests

- `AlignmentMode` drops `transform`. The `flutter_map` page offers `none`, `predict1` and `predict2`, and still starts in `predict1`.
- `static_alignment_test.dart` runs every case with the default layer only. At rest the predicted camera equals the converted camera, so a run with `none` would draw the same frame.
- `map_layer_test.dart` drops the transform row of the test "has no Transform while the camera moves" and keeps the rows for the default layer, `none` and lead 2, each expecting no `Transform`.
- `camera_alignment_test.dart` drops the `transform` and `isTransform` cases. `alignment_error_test.dart` keeps the cases without a transform, under the new field names, and drops those that test the transform. `camera_transform_test.dart` is renamed `camera_projection_test.dart`, and keeps only its conversion group.

## Risks / Trade-offs

- [Someone wants the transform again, for example for a platform without prediction] → It is in git history at the commit before this change, and the transform results stay in `benchmarks.md`.
- [Results from before this change that set no `ALIGNMENT_MODE` measured the transform; rerunning the same procedure now measures `predict1`] → Each result line states its mode. `benchmarks.md` gets a note at the transform results that the mode was removed in this change.
- [`docs/camera-alignment-options.md` lists options that only make sense with the transform (overscan for the uncovered strips)] → The options document records the removal at option 3 and marks overscan as not applicable without the transform.

## Migration Plan

Replace `alignment: CameraAlignment.transform` with the default or `CameraAlignment.none`. Rolling back means reverting this change.
