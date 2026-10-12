## 1. Predictor (D32, D33)

- [x] 1.1 Implement the velocity estimate and the predicted camera as pure Dart functions in `lib/src/layer/`; verify with unit tests: a steady pan is predicted ahead by velocity × lead / refresh rate; a camera equal to the previous build's gives the converted camera; records older than 50 ms are dropped; a pan across the antimeridian uses the shorter longitude difference; a rotation across 0/360 degrees uses the shorter angle; zoom is extrapolated linearly; the predicted latitude is clamped to the Mercator limit and the longitude normalized to [−180, 180)

## 2. Layer (D31)

- [x] 2.1 Add the `compensatingTransform` and `cameraPrediction` parameters to `MapLibreTextureLayer`, documented as experimental, with the current behavior as the default; verify that the existing package unit tests and `example/integration_test/map_layer_test.dart` and `static_alignment_test.dart` pass unchanged on macOS
- [x] 2.2 Extend the integration tests on macOS: with the transform off, the layer has no `Transform` above the texture while the camera moves; with prediction on (lead 2), the static alignment cases pass at rest, and after a camera move stops, a later displayed frame reports the converted camera; verify that the new tests pass
- [x] 2.3 Add a mode switch to the example's `flutter_map` page (transform, no transform, prediction with lead 2, and at the user's request lead 1); verify by running on macOS that each mode shows the map aligned at rest after switching

## 3. Benchmark (D34, D35)

- [x] 3.1 Add `ALIGNMENT_MODE` to the alignment benchmark, and report the mode, `error_drawn_px`, and for pan phases the mean signed offset along the pan direction; verify with a short macOS run (`ALIGNMENT_PHASE_S=5`, phase pan1000) in each of the five modes that every result line has these fields, and that `transform` mode gives the Stage 3 values at 1600x1000 (about 8.33 px at p50)
- [x] 3.2 Add the `stop`, `fling` and `reverse` phases with their motion-change times, the overshoot and the overshoot ahead (p50 and largest per phase); verify with unit tests that the fling camera follows `flutter_map`'s spring (starts at 1,000/1,000 × the viewport's shorter side px/s, covers the shorter side, ends at rest after 1.447 s) and that each overshoot window starts and ends as D35 defines, and with a macOS run that `stop` and `fling` report 10 motion changes and `reverse` 19, and their overshoot

## 4. Measurement (D36)

- [x] 4.1 Run the benchmark on the reference Mac in release mode at 1600x1000 (display at "More Space"), all five modes, 2 runs each; record the results with their conditions in `benchmarks.md`
- [x] 4.2 Run the benchmark on the reference iPhone in release mode with Auto-Lock off, modes `transform`, `none` and the best prediction lead from 4.1 (`predict1`), and at the user's request `predict2`, 2 runs each; record the results in `benchmarks.md`
- [x] 4.3 Manual check on the Mac and the iPhone: drag slowly and quickly, stop abruptly, fling, and reverse on the `flutter_map` page in transform mode and in prediction mode; record what the user observes (jitter while dragging, overshoot at stops, floating overlays) in the design

## 5. Decision

- [x] 5.1 Apply the criteria from D36 to the best prediction lead (p50 drawn error during pan1000 at most 4 px; p50 overshoot ahead in the fling phase below 8.33 px), together with the abrupt stop, the reversal and the manual check; record the results and the decision whether to make prediction the default (implemented in a separate change if taken) in the design, `limitations.md`, option 5 of `docs/camera-alignment-options.md`, and the Decision column of roadmap row 3 in `docs/maplibre-native-ffi-flutter-texture-concept.md`
