## Why

Since the camera-prediction-default change, `MapLibreTextureLayer` aligns the map with camera prediction (lead 1) by default, and the compensating transform is only an option (`CameraAlignment.transform`). The transform is the only part of the layer that needs the camera of the frame Flutter displays. On Android, Flutter's `SurfaceProducer` gives the plugin no report of which frame Flutter took, so the transform would need a native report that Android can't provide exactly. On 2026-10-12 we decided to drop the transform, before the Android change, so that the layer's alignment works the same on every platform and the Android change doesn't carry it.

## What Changes

- **BREAKING** (experimental API only): `CameraAlignment.transform` and `CameraAlignment.isTransform` are removed. `CameraAlignment` keeps `prediction({double lead = 1})` (the default) and `none`.
- The layer never draws the map with a `Transform`. The transform code (`frameTransform`, `layerTransform`) is removed. The camera conversion and the Web Mercator projection, which the prediction and the alignment error use, stay.
- The alignment error computes only the error of the map as the layer draws it, without a transform. The alignment benchmark drops its `transform` mode and the result fields that compare with the transform (`error_with_transform_px`, `error_without_transform_px`, `mismatch_fraction`). Its `ALIGNMENT_MODE` default changes from `transform` to `predict1`, the layer's default.
- The example's `flutter_map` page offers `none`, `predict1` and `predict2`.
- The tests drop the transform cases.
- The documentation describes the transform as removed: `limitations.md`, `docs/camera-alignment-options.md`, the concept document's roadmap row 3, and the layer's README. `benchmarks.md` keeps its recorded transform results, with a note that the mode no longer exists.

Out of scope: the native displayed-frame report (`FrameCamera`, `MapTextureController.frames` and `displayedFrame`), which the benchmark, the timing probe and the texture tests still use; the layer's rebuild on each displayed frame, which prediction needs (D32); Android.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: "Compensating transform" is removed. "Camera prediction" no longer refers to the transform, and its last scenario covers the layer with neither alignment. "Alignment measurement" measures the error of the drawn map only, in the configurations prediction at a stated lead and neither.

## Impact

- Code: `packages/flutter_mapigrade/lib/src/layer/` (`camera_alignment.dart`, `camera_transform.dart`, `alignment_error.dart`, `map_libre_texture_layer.dart`); `example/lib/alignment_mode.dart`, `alignment_benchmark.dart`, `flutter_map_page.dart`. `lib/src/texture/` and the native core don't change.
- API: `CameraAlignment.transform` and `isTransform` are removed. The package is version 0.0.1 with `publish_to: none`.
- Tests: `packages/flutter_mapigrade/test/layer/` (`camera_alignment_test.dart`, `camera_transform_test.dart`, `alignment_error_test.dart`); `example/integration_test/static_alignment_test.dart` and `map_layer_test.dart`.
- Documentation: `limitations.md`, `benchmarks.md`, `docs/camera-alignment-options.md`, `docs/maplibre-native-ffi-flutter-texture-concept.md`, `packages/flutter_mapigrade/lib/src/layer/README.md`.
