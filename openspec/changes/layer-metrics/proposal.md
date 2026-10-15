## Why

A developer who evaluates `flutter_mapigrade`, or tunes a style on a device, can't see how fast the map renders: the frame counters exist natively, but only the test harness reads them, through the internal `src/testing.dart` library. We plan a demo app that shows the map frame rate, and it has to use the public API to show developers what they can use in their own apps. This change adds that API; the demo is a later change.

## What Changes

- A new public type, `LayerMetrics`, that an application creates and passes to `MapigradeLayer` with a new optional parameter, `metrics`. Without it, the layer behaves as today.
- `LayerMetrics.snapshot()` returns a `LayerMetricsSnapshot` with cumulative values:
  - `time`: the time of the snapshot on a monotonic clock, so that an application computes rates from two snapshots with one clock.
  - `displayedFrames`: the map frames given to Flutter for display. On macOS and iOS, a frame counts when Flutter takes it for display; on Android, when the map has queued it for display. On Android every rendered frame is queued, so the count equals `renderedFrames` there.
  - `renderedFrames`: the frames MapLibre rendered.
  - `renderTime`: the total time the map spent rendering.
- Dart reads the values when the application calls `snapshot()`, with one synchronous FFI call that copies the native counters. The native side sends nothing to Dart, so the API costs nothing while no application reads it.
- A `LayerMetrics` reports the counts of one map, from the map's creation. Before the layer has a map, every count is 0. A style change keeps the map, so the counts continue. When the layer disposes its map, the object keeps the map's last counts: it reads them just before it disposes the map, and so it can miss a frame that the map renders between the read and the dispose. A new `key` gives the layer a new map; an application creates a new `LayerMetrics` with the new key. If it passes the same object, the counts start again from 0, as with a new object.
- Android: the native map counts the frames it queues for display. Today the counter of displayed frames is 0 on Android, because only the Apple path increments it.

Non-goals:

- No per-frame stream or callback in the public API.
- No counters beyond the four values above in this change. The package MAY add members to exported types later.
- No Flutter UI frame rate: Flutter reports it through `SchedulerBinding.addTimingsCallback`.
- No averages or rates computed by the package, and no support for analytics in production.
- No exact count at map disposal: that needs `map_texture_dispose` to return the final counters, which changes the C API for at most one frame.
- No demo app; `add-demo-app` covers it and depends on this change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `package-api`: the requirement "Exported names" adds `LayerMetrics` and `LayerMetricsSnapshot` to the names the main library exports, nine in all.
- `map-layer`: a new requirement, "Metrics", states the values a snapshot contains, what they count on each platform, and which map's counts an object reports: before the layer has a map, after a style change, after the layer disposes its map, and after a new `key`.

## Impact

- Dart: `lib/flutter_mapigrade.dart` (exports), `lib/src/layer/mapigrade_layer.dart` (the `metrics` parameter), a new source file for the two types, `lib/src/layer/map_texture_layer.dart` (reads the counters before it disposes its map), `lib/src/texture/map_texture_controller.dart` (a constructor of the counters for tests), `test/api_test.dart` (the export list).
- Native: `src/core/map_texture.cpp` increments the counter of displayed frames on the surface path that Android uses. The C API and the counter struct don't change.
- Tests: widget tests with a fake controller for the zero snapshot, the counts after disposal and after a new key; a C++ test that the surface path counts displayed frames; an integration test in `packages/test_harness` on macOS, the iOS simulator and the Android emulator that pans the camera and checks that `displayedFrames` and `renderedFrames` increase, and that they don't change while the map is idle.
- Documentation: `README.md` and `CHANGELOG.md` describe the API.
- Interaction with `add-demo-app`: that change's proposal states that the demo imports `src/testing.dart` and uses `MapTextureLayer`. It needs an update to use `MapigradeLayer` and `LayerMetrics`.
