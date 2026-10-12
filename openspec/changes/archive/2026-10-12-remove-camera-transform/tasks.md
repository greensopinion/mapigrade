## 1. Layer (D47, D48)

- [x] 1.1 Remove `CameraAlignment.transform` and `isTransform`, and update the class documentation as D47 states; drop the `transform` and `isTransform` cases from `camera_alignment_test.dart`; verify that the package unit tests pass
- [x] 1.2 Move the conversion and projection code from `camera_transform.dart` to `camera_projection.dart`, remove `frameTransform`, `layerTransform` and the overlap test, update the imports in `camera_prediction.dart`, `alignment_error.dart` and `lib/testing.dart`, and rename `camera_transform_test.dart` to `camera_projection_test.dart` with only its conversion group; verify with `flutter analyze` and the package unit tests
- [x] 1.3 Remove the `Transform` from `MapLibreTextureLayer.build`, keeping the rebuild on each displayed frame (D32); verify with `flutter analyze` and `git grep -n 'Transform(' packages/flutter_mapigrade/lib` returning nothing in `lib/src/layer/`

## 2. Measurement (D49)

- [x] 2.1 Change `alignmentError` to take `target` and `shown` and return `error` and `center`, and update `alignment_error_test.dart` as D50 states; verify that the package unit tests pass
- [x] 2.2 Update the alignment benchmark as D49 states (no `used`, no transform fields, `ALIGNMENT_MODE` default `predict1`, `transform` rejected) and its header comment; verify with `flutter analyze` in `example/` and a short macOS release run (`ALIGNMENT_PHASE_S=5`, phase pan1000) without `ALIGNMENT_MODE` that reports mode `predict1` and an `error_drawn_px` p50 of 0 or 8.33 px, as in `benchmarks.md`, and a run with `ALIGNMENT_MODE=transform` that exits with the unknown-mode error

## 3. Example and integration tests (D50)

- [x] 3.1 Remove `AlignmentMode.transform` and the page's `transform` segment; verify by running the example's `flutter_map` page on macOS: it starts in `predict1`, offers `none`, `predict1` and `predict2`, and the map is aligned with the markers at rest after switching modes
- [x] 3.2 Update `static_alignment_test.dart` (default layer only) and `map_layer_test.dart` (no transform row); verify that both files pass on macOS

## 4. Documentation

- [x] 4.1 Describe the transform as removed in `limitations.md` (Alignment during camera changes, Camera prediction, Known limitations), `docs/camera-alignment-options.md` (option 3 done in this change; overscan not applicable), the Decision column of roadmap row 3 in `docs/maplibre-native-ffi-flutter-texture-concept.md`, and `packages/flutter_mapigrade/lib/src/layer/README.md`; add a note at the transform results in `benchmarks.md` that the mode was removed in this change; verify with `git grep -n 'CameraAlignment.transform\|isTransform\|layerTransform\|frameTransform'` returning matches only in `openspec/changes/archive/` and in the `benchmarks.md` note
