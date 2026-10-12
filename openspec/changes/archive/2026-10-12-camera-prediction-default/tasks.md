## 1. Alignment option (D43, D44)

- [x] 1.1 Add `CameraAlignment` to `lib/src/layer/` with `prediction({double lead = 1})`, `transform` and `none`, value equality, and an assertion that the lead is greater than 0; export it from `package:flutter_mapigrade/flutter_mapigrade.dart`; verify with a unit test of the default lead, equality and hash codes
- [x] 1.2 Replace `compensatingTransform` and `cameraPrediction` on `MapLibreTextureLayer` with `alignment`, default `CameraAlignment.prediction()`, and document each value and the class as D44 states; verify with `flutter analyze` and the package unit tests

## 2. Example and tests (D45, D46)

- [x] 2.1 Map `AlignmentMode` to `CameraAlignment` and use `alignment` in the `flutter_map` page and the alignment benchmark; the page starts in `predict1`, and `ALIGNMENT_MODE` keeps its default `transform`; verify with `flutter analyze` in `example/` and a short macOS benchmark run (`ALIGNMENT_PHASE_S=5`, phase pan1000) in `transform` and `predict1` modes that reports the same p50 and p95 as in `benchmarks.md` (8.33 / 16.67 px and 0 or 8.33 / 16.67 px)
- [x] 2.2 Update `static_alignment_test.dart` to run every case with the default layer and with `CameraAlignment.transform`, and `map_layer_test.dart` as D46 states (named configurations, a test that the default layer has no `Transform` while the camera moves, the camera-after-stop test with the default layer); verify that both files pass on macOS
- [x] 2.3 Run the example's `flutter_map` page on macOS; verify that it starts in `predict1` and that the map is aligned with the markers at rest in each mode after switching

## 3. Documentation

- [x] 3.1 Describe the new default and the `alignment` parameter in `limitations.md` (including that prediction was measured only on 120 Hz displays), option 5 of `docs/camera-alignment-options.md`, the Decision column of roadmap row 3 in `docs/maplibre-native-ffi-flutter-texture-concept.md`, and `packages/flutter_mapigrade/lib/src/layer/README.md`; verify that no document outside `openspec/changes/archive/` and `benchmarks.md` describes the transform as the layer's default or names `compensatingTransform` or `cameraPrediction` as current parameters (`git grep`)
