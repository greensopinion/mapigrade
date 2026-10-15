## 1. Native counter on Android

- [ ] 1.1 In `src/core/map_texture.cpp`, increment `stats_.presented_frames` in `RenderIntoSurface()` in the locked block that increments `rendered_frames` (D112), and update the comment of `presented_frames` in `src/core/map_texture_api.h`; change `SurfaceFrameIsReportedWithoutDisplayTime` in `test/native/map_texture_tests.cpp` to expect 1, and verify that the native tests pass

## 2. Dart types

- [ ] 2.1 Add `MapTextureStats.forTesting` with named parameters that default to 0, marked `@visibleForTesting` (D113), and update the doc comment of `presentedFrames` for both platforms; verify that `flutter analyze` reports no issues in the package
- [ ] 2.2 Create `lib/src/layer/layer_metrics.dart` with `LayerMetrics`, `LayerMetricsSnapshot`, `bindMetrics` and `releaseMetrics` (D109, D110), with doc comments that state the platform meaning of `displayedFrames`, that `renderTime` includes render calls that rendered nothing, and that each layer needs its own object and a new key needs a new object; add unit tests in `test/layer/layer_metrics_test.dart` with a fake controller for: an unbound object returns zeros; a bound object returns the controller's values; release keeps the last values and later snapshots return them; release with a different controller does nothing; `stats()` throwing `MapTextureException` returns the kept values; `time` increases between snapshots; verify that the tests pass
- [ ] 2.3 Export `LayerMetrics` and `LayerMetricsSnapshot` from `lib/flutter_mapigrade.dart` with a `show` list, and add both names to `expectedNames` in `test/api_test.dart`; verify that the API test passes, that it reports nine names, and that `bindMetrics` and `releaseMetrics` are not exported

## 3. Layer

- [ ] 3.1 Add the optional `metrics` parameter to `MapTextureLayer` and `MapigradeLayer`, and bind, swap and release it in `_MapTextureLayerState` (D111); add widget tests in `test/layer/map_texture_layer_test.dart` with `_FakeController` returning `MapTextureStats.forTesting` values for the scenarios "No map yet", "Map can't be created", "Style change", "Layer removed", "New key with the same object" and "Different object for the same map", and verify that the tests pass
- [ ] 3.2 Add a test to `test/layer/mapigrade_layer_test.dart` that `MapigradeLayer` passes `metrics` to `MapTextureLayer`, and verify that it passes

## 4. Integration

- [ ] 4.1 Add a test to `packages/test_harness/integration_test/map_layer_test.dart` for the scenarios "Camera moves" (pan for 2 s with `MapController`; on macOS and iOS `displayedFrames` ≤ `renderedFrames`, on Android equal) and "Map at rest" (two snapshots 1 s apart after the style has loaded and the map is idle), using only `package:flutter_mapigrade/flutter_mapigrade.dart` for the metrics; verify that it passes on macOS, on the iOS simulator and on the Android emulator
- [ ] 4.2 Run the existing Android branch of `map_texture_test.dart` and the benchmark on the Android emulator, and verify that both still pass and that the benchmark prints its result line

## 5. Documentation

- [ ] 5.1 Add a "Metrics" section to `packages/flutter_mapigrade/README.md` with an example that takes a snapshot once per second and computes the displayed frame rate, and that states the Android meaning of displayed frames and that a new key needs a new `LayerMetrics`; add `LayerMetrics` and `LayerMetricsSnapshot` and the `metrics` parameter to the 0.0.1 entry of `CHANGELOG.md`; verify by reading that every name the text uses exists in the code
- [ ] 5.2 Run `flutter analyze` and `flutter test` in `packages/flutter_mapigrade`, and verify that both pass
