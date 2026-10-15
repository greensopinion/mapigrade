## Context

See proposal.md for motivation and scope, and specs/map-layer/spec.md (requirement "Metrics") for the behavior. The in-flight change `publish-readiness` uses decisions up to D108; decisions here are numbered from D109.

Current state, as checked in this repository on 2026-10-14:

- The native map keeps its counters in a `map_texture_stats` struct (`src/core/map_texture_api.h`), guarded by `stats_mutex_`. The map thread increments them as it renders. `map_texture_get_stats` (`src/core/map_texture_api.cpp`) copies the struct under the mutex; it returns `MAP_TEXTURE_ERROR_DISPOSED` once the map is disposed.
- Dart reads them with `MapTextureController.stats()`, a synchronous `@Native` call that returns `MapTextureStats`. Only the test harness calls it today.
- `presented_frames` is incremented only in `MapTexture::Present()`, which Flutter's Darwin embedders call when they take a display buffer. The surface path that Android uses, `RenderIntoSurface()`, increments `rendered_frames` and emits the frame-displayed event, but not `presented_frames`. `SurfaceFrameIsReportedWithoutDisplayTime` in `test/native/map_texture_tests.cpp` asserts that it stays 0.
- `render_update_total_ns` adds up the duration of every `mln_render_session_render_update` call, including calls that found nothing to render and failed calls.
- `MapigradeLayer` is a `StatelessWidget` that builds the internal `MapTextureLayer`. `_MapTextureLayerState` creates the controller in `didChangeDependencies`, keeps it across style changes (`didUpdateWidget` loads the new style into the same map), and disposes it in `dispose`. A new `key` gives a new state, and so a new map. Flutter mounts the new state before it disposes the old one.
- The widget tests in `test/layer/map_texture_layer_test.dart` inject `createController` and use `_FakeController implements MapTextureController`. `MapTextureStats` has only a private constructor from the FFI struct.

## Goals / Non-Goals

**Goals:**
- Taking a snapshot costs one FFI call and no allocation beyond the snapshot; a layer whose metrics nobody reads costs nothing more than today.
- No native code runs for metrics when the native library isn't available (requirement "Unsupported architectures").
- The C API and the counter struct stay unchanged.

**Non-Goals:**
- Exact counts at disposal (proposal, Non-goals).
- Counting the frames Flutter takes from the Android surface: Flutter reports no such event on Android (design D58).

## Decisions

### D109. `LayerMetrics` holds a reference to one controller, and the layer binds it

`lib/src/layer/layer_metrics.dart` declares both public types and two functions that the main library doesn't export:

```dart
final class LayerMetrics {
  LayerMetrics();
  LayerMetricsSnapshot snapshot();
}

void bindMetrics(LayerMetrics metrics, MapTextureController controller);
void releaseMetrics(LayerMetrics metrics, MapTextureController controller);
```

`LayerMetrics` has two private fields: the controller it reads, and the values it keeps after that controller is released. Because the functions are in the same file, they can set the private fields; the export directive lists only `LayerMetrics` and `LayerMetricsSnapshot`, so applications can't call them (requirement "Exported names").

- `bindMetrics` sets the controller and clears the kept values, so the counts start from the new map's values.
- `releaseMetrics` does nothing unless the object's controller is `controller`. Otherwise it reads `controller.stats()`, keeps the values, and clears the controller.
- `snapshot()` reads the bound controller's counters when it has one and the controller isn't disposed. Otherwise it returns the kept values, or zeros. If `stats()` throws `MapTextureException`, it returns the kept values, or zeros, so a snapshot never throws.

The check in `releaseMetrics` handles a new `key` with the same object. The new state binds the object to the new map, and the old state's release then finds a different controller and does nothing. If Flutter disposed the old state first, the release would keep the old values and the bind would then replace them. In both orders the object reports the new map from 0. The same rule applies when the application gives one object to two layers: the object reports the layer that was given it last.

*Alternatives:*
- Add the counts of each disposed map to totals (the first proposal). The user decided on 2026-10-14 that a new key gives new counts.
- An assertion when one object is given to a second map. With the same object and a new key, the new state binds before the old one is disposed, so the assertion would fail for a case that the spec allows.
- A public attach method on `LayerMetrics`. That would be API that applications must not call.

### D110. Snapshot values and the clock

`LayerMetricsSnapshot` is a final class with a private constructor, value equality and a `toString`:

| Field | Source |
|---|---|
| `time` (`Duration`) | `elapsed` of one `Stopwatch` per process, started when the library first creates a snapshot |
| `displayedFrames` (`int`) | `presentedFrames` |
| `renderedFrames` (`int`) | `renderedFrames` |
| `renderTime` (`Duration`) | `renderUpdateTotal` |

`renderTime` includes the render calls that found nothing to render. The doc comment says so, so that `renderTime / renderedFrames` is read as an upper bound of the average render time per frame. On the copy path, the copy into the display buffer isn't included; copy-free is the default on every platform.

The constructor is private so that adding a field later doesn't break applications. Applications that need snapshots in their own tests can wrap the type.

*Alternatives:*
- A timestamp from the native clock, written when the counters are copied. That needs a new field in `map_texture_stats` and a C API change. The difference from Dart's clock is the duration of the FFI call.
- `DateTime.now()`. It isn't monotonic.
- A public constructor. It makes every later field a breaking change, or forces it to be optional.

### D111. The layer binds when it creates its map and releases before it disposes it

`MapigradeLayer` gets an optional `metrics` parameter and passes it to `MapTextureLayer`, which gets the same parameter. `_MapTextureLayerState`:

- after `create` succeeds in `didChangeDependencies`, calls `bindMetrics(widget.metrics, controller)` when `metrics` isn't null. When creation fails, nothing is bound, so the snapshot is zero and no native code runs for it;
- in `didUpdateWidget`, when the object is a different object and the state has a controller, calls `releaseMetrics(old, controller)` and `bindMetrics(new, controller)`;
- in `dispose`, calls `releaseMetrics(widget.metrics, controller)` before `controller.dispose()`.

The values kept at disposal may lack a frame that the map thread renders between `stats()` and `dispose()` (proposal, Non-goals).

### D112. The surface path counts displayed frames

`RenderIntoSurface()` increments `stats_.presented_frames` in the same locked block as `rendered_frames`, after `RenderUpdate` has queued the frame on the surface. The comment of `presented_frames` in `map_texture_api.h` and of `presentedFrames` in `MapTextureStats` states the meaning on each platform. `SurfaceFrameIsReportedWithoutDisplayTime` expects 1 in place of 0.

`pickup_wait_*` and `present_to_render_*` stay Apple-only. They depend on the time at which Flutter takes a frame, which Android doesn't report. No code in the test harness reads `presentedFrames` on Android.

### D113. A test constructor for the counters

`MapTextureStats` gets a constructor marked `@visibleForTesting`, `MapTextureStats.forTesting({...})`, whose named parameters default to 0. The widget tests' fake controller returns values from it, so they can check D109 and D111 without a native map. The integration test in `packages/test_harness/integration_test/map_layer_test.dart` checks the scenarios that need the native map ("Camera moves", "Map at rest") on macOS, the iOS simulator and the Android emulator.

## Risks / Trade-offs

- [On Android `displayedFrames` always equals `renderedFrames`, so the difference that shows rendering ahead on Apple platforms is never visible there.] → The doc comment and the README state it.
- [`snapshot()` takes the same mutex as the map thread's counters. An application that takes a snapshot in every Flutter frame contends with the map thread once per frame.] → The lock covers a copy of the struct only. The README shows snapshots once per second.
- [An application gives one object to two layers that both stay in the tree, and reads the counts of only one of them.] → D109 defines which one; the doc comment of `metrics` says to give each layer its own object.
- [`renderTime` overstates the average per frame when the map makes render calls that render nothing.] → The doc comment states it (D110).

## Migration Plan

The change only adds API. Version 0.0.1 isn't published, so `CHANGELOG.md` lists the new types under 0.0.1.
