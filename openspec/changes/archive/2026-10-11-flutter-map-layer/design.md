## Context

See proposal.md for motivation and scope, and specs/map-layer/spec.md and specs/map-texture/spec.md for the requirements. The designs of the macOS slice (D1 to D10) and the iOS slice (D11 to D20), both in `openspec/changes/archive/`, apply unchanged. Decisions here are numbered from D21.

Current state, as checked in this repository on 2026-10-10:

- The native core marks a buffer as presented and sends `MAP_TEXTURE_EVENT_FRAME_DISPLAYED` in `MapTexture::Present()` (`src/core/map_texture.cpp`), which `copyPixelBuffer` calls on Flutter's raster thread. Dart receives the event through a `NativeCallable.listener`, asynchronously, after that raster frame. `MapTextureController.frames` and `displayedFrame` expose it.
- With render ahead (D19), the map thread can publish a new frame between a Flutter frame's build and its rasterization, so the frame that raster takes can be newer than the last frame Dart has been notified of.
- `MapTextureView` sizes the map from its `LayoutBuilder` constraints and shows a `Texture`.
- `test/texture_boundary_test.dart` checks that `lib/src/texture/` doesn't import `package:flutter_map`.
- `example/integration_test/color_measurement.dart` captures the map with `RepaintBoundary.toImage`, which includes the texture layer.
- `example/lib/benchmark.dart` pans at `panSpeed = 0.2`, which at MapLibre zoom 14 is about 102 logical px/s.

Facts checked in `flutter_map` 8.3.1 (the newest version in the local pub cache):

- `MapCamera` has `center` (`LatLng`), `zoom`, `rotation` in degrees, `nonRotatedSize`, and `size`, the bounding box of the rotated viewport.
- `MarkerLayer` positions markers from `camera.pixelOrigin`, which is `projectAtZoom(center, zoom) - size.center(Offset.zero)`, without rounding. `pixelBoundsAtZoom` floors the projected center, but it is used for bounds, not for marker positions.
- Layers that rotate with the map wrap their content in `MobileLayerTransformer` (an `OverflowBox` of `camera.size` and `Transform.rotate`).
- `FlutterMap` lays out its children in a `Stack` the size of the map widget.
- `flutter_map` depends on `latlong2`, `http`, `path_provider` and others.

## Goals / Non-Goals

**Goals:**
- A measurement whose result decides whether per-buffer textures are needed, with an error per Flutter frame that we can trust.
- A layer whose behavior at rest is already exact, so that the measured error during camera changes comes only from timing.

**Non-Goals:**
- Making the error small. This change measures it; per-buffer textures or other changes come later if needed.
- Filling the strips at the viewport edges that the transform uncovers during camera changes (overscan).
- A public API for the layer beyond what the example needs. Its name and parameters can change.

## Decisions

### D21. The layer owns its map

The layer is a `StatefulWidget`, named `MapLibreTextureLayer` as in the concept doc. It takes a style URL or JSON and an optional callback that receives the `MapTextureController` (for the example and the tests). It creates the controller in `initState` with the view's device pixel ratio, and disposes it in `dispose`. It reads the camera with `MapCamera.of(context)`, so it rebuilds on every camera change.

It doesn't use `MobileLayerTransformer`: MapLibre rotates the map itself (D22), so the texture keeps the size of the non-rotated viewport and isn't rotated by Flutter, apart from the compensating transform (D23).

*Alternative:* the application creates the controller and passes it in. We rejected it for now, because no user needs to share a controller. The callback gives the tests access.

### D22. Camera conversion

```
MapLibre latitude, longitude = flutter_map center
MapLibre zoom                = flutter_map zoom - 1   (512 px tiles vs 256 px tiles)
MapLibre bearing             = -flutter_map rotation
MapLibre viewport            = camera.nonRotatedSize, at the device pixel ratio
```

The layer calls `setCamera` during build when the converted camera differs from the last one it sent. Calling native code from build is a side effect, but `setCamera` only writes the latest-camera slot and signals the map thread (D3 of the macOS slice), and calling it during build starts the render about one frame earlier than a post-frame callback would.

The static alignment test (D27) checks the zoom offset and the sign of the bearing. Both come from `flutter_map_maplibre` and haven't been verified in this repository. Result, 2026-10-10: the static alignment test passed for all cases on macOS (largest distance 0.042 logical px) and on the iOS simulator (iPhone 16 Pro, largest 0.071 logical px), so both are correct. The frame-displayed event reports the bearing with the sign it was set with; the integration test `camera change shows up in the frame camera` now checks the sign.

### D23. Compensating transform (last-reported-frame transform)

The layer wraps the `Texture` in a `ClipRect` and a `Transform`. The matrix maps the camera of `controller.displayedFrame` (R) to the current converted camera (C). Pseudocode, in Web Mercator coordinates normalized to [0, 1) and in logical pixels:

```
// pseudocode
worldSize(z)      = 512 * 2^z
screen(cam, w)    = rotate(-cam.bearing) * ((w - mercator(cam.center)) * worldSize(cam.zoom))
                    + cam.viewportSize / 2
T(R -> C)         = point p on R's frame  ->  screen(C, world point that R drew at p)
                  = translate(C.viewportSize / 2) * rotate(-C.bearing) * scale(2^(C.zoom - R.zoom))
                    * translate(worldSize(R.zoom) * wrap(mercator(R.center) - mercator(C.center)))
                    * rotate(R.bearing) * translate(-R.viewportSize / 2)
wrap(d)           = d.x moved into [-0.5, 0.5) by whole worlds; d.y unchanged
```

`R.viewportSize` is the frame's `physicalSize / scaleFactor`, so a frame rendered before a resize is placed correctly. The rotation signs follow D22 and are checked by the transform's unit tests and the static alignment test. Until the first frame is displayed, the layer shows the texture without a transform.

The layer also draws the texture without a transform when the transform would move the frame entirely outside the viewport, for example after a camera jump larger than the viewport. Flutter doesn't draw a texture that lies entirely outside its clip, so it doesn't call `copyPixelBuffer`, no new frame is displayed, and the transform would never be updated: the layer would stay empty. We found this in the alignment benchmark on 2026-10-10, where the camera jumps 3,000 px between phases. The check intersects the transformed frame with the viewport as rectangles, not as bounding boxes, because with rotation the bounding box of a frame can overlap the viewport while the frame doesn't. The error computation (D26) applies the same rule.

The transform is an affine map in screen space. For pan, zoom and rotation without pitch, Web Mercator screen positions under two cameras differ by exactly such a map, so with R equal to the displayed frame the result is exact apart from the uncovered edges.

### D24. Display time of each frame

`MapTexture::Present()` records the current time when it marks a new frame as presented, and the frame-displayed event carries it. `FrameCamera` gains a `displayTime` field in microseconds on the clock of `FrameTiming` (`FrameTiming.timestampInMicroseconds`).

Which clock `FrameTiming` uses is the first thing to check (task 1.1). We expect the engine's monotonic clock (`fml::TimePoint::Now()`), and the core then reads the same clock. If the engine clock can't be read from the plugin, the core reports its own clock, and the measurement estimates the offset between the two clocks from frames where only one display event falls into a raster interval.

Result of task 1.1 (Flutter 3.47.5, engine af7e796e16, Dart b530c21f7d), checked on 2026-10-10:

- The rasterizer records `rasterStart` and `rasterFinish` with `fml::TimePoint::Now()` (`shell/common/rasterizer.cc`). `DartVMInitializer` sets the clock source of `fml::TimePoint` to `Dart_TimelineGetTicks` (`runtime/dart_vm_initializer.cc`), which on macOS and iOS returns `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (`runtime/vm/os_macos.cc` in the Dart SDK). The macOS and iOS vsync waiters convert the display link time to the same clock.
- The plugin can read this clock directly. The core reads `CLOCK_MONOTONIC_RAW` in `DisplayClockUs()`. It doesn't use its `NowNs()` for the display time: `std::chrono::steady_clock` reads `CLOCK_UPTIME_RAW` on Apple platforms, which stops while the device sleeps, so it differs from `CLOCK_MONOTONIC_RAW` by the total sleep time since boot.
- The probe (`example/lib/timing_probe.dart`, profile build, 10 s pan at about 100 logical px/s) found the display time between `rasterStart` and `rasterFinish` of a `FrameTiming` for all 1,193 displayed map frames on the reference Mac (120 Hz), and for all 853 on the reference iPhone (120 Hz).

The clocks are the same, so the offset fallback isn't needed.

### D25. Matching Flutter frames to map frames

During an alignment run, the example records three streams and matches them after the run:

1. **Builds.** A persistent frame callback (`SchedulerBinding.addPersistentFrameCallback`) records for every Flutter frame its engine frame number (`PlatformDispatcher.instance.frameData.frameNumber`), the `flutter_map` camera C_N, and the map frame k_used whose camera the layer's transform used. A persistent callback runs for every frame, including frames in which the layer doesn't rebuild.
2. **Frame timings.** `SchedulerBinding.addTimingsCallback` provides `frameNumber`, `rasterStart` and `rasterFinish` for each frame.
3. **Display events.** `controller.frames` provides (k, camera, display time).

A build is matched to its `FrameTiming` by frame number. Both numbers come from the engine's `FrameTimingsRecorder` of that frame. The map frame shown in Flutter frame N, k_shown, is the display event whose display time falls in `[rasterStart_N, rasterFinish_N]`. If there is none, Flutter didn't take a new frame, and k_shown is the same as for frame N−1. Frames that can't be matched are excluded and counted in the report.

Matching runs after the run, not during frames, so that the measurement doesn't change the timing it measures.

Flutter also rasterizes frames without a build, when only the texture changed. Such a frame shows a new map frame with the camera and transform of the last build, so the measurement includes it with that build's C_N and k_used, and reports the number of these frames separately.

Result of task 1.2, checked on 2026-10-10 with the probe from task 1.1:

- `currentSystemFrameTimeStamp` doesn't equal `FrameTiming.vsyncStart` of the same frame. `Animator::BeginFrame` passes the vsync target time to Dart (`shell/common/animator.cc`), and `vsyncStart` is the vsync start. The probe measured target minus start as 8,316 to 8,334 µs on the reference Mac and 8,333 to 8,334 µs on the reference iPhone, one refresh period at 120 Hz.
- Matching by vsync timestamp is therefore wrong even where it finds an exact match: the target time of frame N usually equals `vsyncStart` of frame N+1. The probe found such matches for 616 of 1,203 builds on the Mac and 12 of 1,200 on the iPhone.
- We chose frame numbers over matching by order, the fallback planned here, because Flutter rasterizes frames without a build when only a texture changed, and those frames would shift an order-based match.
- By frame number, each build matched exactly one `FrameTiming`: 1,203 of 1,203 builds on the Mac and 1,200 of 1,200 on the iPhone, in 10 s pans.

### D26. Error computation

For each matched Flutter frame N and each reference point q (the four viewport corners and the center):

```
// pseudocode
g          = coordinate that the overlays draw at q under C_N
withT      = T(k_used -> C_N) (screen(k_shown, g))
withoutT   = screen(k_shown, g)
error_N    = max over q of |withT - q|;  errorWithoutT_N = max over q of |withoutT - q|
```

The implementation (`lib/src/layer/alignment_error.dart`) also applies the stretch of the `Texture` widget, which scales a frame from its own size to the viewport, and the layer's matching correction (`layerTransform`), so that frames rendered before a resize are measured as Flutter draws them. With equal sizes it reduces to the pseudocode above.

If k_shown = k_used, the error with the transform is 0 by construction. The report gives, per pan speed, the fraction of frames with k_shown ≠ k_used and the p50, p95 and largest error with and without the transform. The computation is a pure function with unit tests.

### D27. Static alignment test

An integration test loads a JSON style with a background and a GeoJSON source with one point, drawn by a `circle` layer in a color that appears nowhere else. A `flutter_map` `CircleMarker` at the same coordinate is drawn in a second color. With the camera at rest and the map idle, the test captures the map with `RepaintBoundary.toImage` twice, with the overlay hidden and visible, and computes each disc's center as the centroid of its color's pixels. The cases are those in the spec: integer and fractional zoom, rotation, latitudes up to 80 degrees, near the antimeridian, after a resize.

Capturing two images avoids the overlay hiding part of the style's disc and shifting its centroid.

### D28. Alignment benchmark

The benchmark moves the `flutter_map` camera through `MapController` on every frame, as a gesture would. Phases:

- pan at 100, 500, 1,000 and 2,000 logical px/s over the London path of `benchmark.dart`
- zoom in and out at 1 zoom level per second
- rotate at 90 degrees per second

It prints one result line per phase, as the existing benchmark does, and runs on the reference Mac and the reference iPhone in release mode.

### D29. Independent check with a screen capture

On the Mac, a capture tool records the example's window with ScreenCaptureKit at 120 Hz during the 1,000 px/s pan, in a video mode of the alignment benchmark. In that mode a JSON style draws a grid of red discs from a GeoJSON source, and a `CircleLayer` draws a small blue dot at the center of each disc. The tool measures in every captured frame the distance between each disc's center and its dot, away from the viewport edges, and the width of the uncovered strips at the edges. We compare the distances with the error the benchmark computes in the same run. A few seconds at rest before the pan check the method: there the distance must be below 1 logical pixel. This checks the assumptions of D26: that MapLibre renders at the camera it reports, that the conversion and the transform are correct while the camera moves, and that the map frame Flutter takes in a raster pass is composited with the overlays of the same Flutter frame.

The capture shows the image the window server composites, not the light the display emits. The texture and the overlays are composited into one image before the display, so the display's timing can't change the distance between them.

Result, 2026-10-11 (`benchmarks.md`): at rest the captured distance was 0.03 px. During the pan at 1,000 px/s it was 8.39 px at p50, against 8.33 px computed in the same run. The uncovered strip at the edge was 16 px wide, two Flutter frames of movement, in almost every moving frame.

*Alternative:* a second device films the iPhone screen at 240 fps, which we planned first. We dropped it on 2026-10-11 because it needs a second device and manual measurement of video frames. As a result the iPhone has no check against what reaches the screen.

### D30. Dependency

`flutter_mapigrade` depends on `flutter_map` at an exact version, at least 8.3.1 (task 2.1 checks pub.dev for a newer release). On 2026-10-10 the newest release was 8.3.2 (published 2026-08-27), and both `flutter_mapigrade` and the example depend on `flutter_map: 8.3.2` and `latlong2: ^0.10.1`. 8.3.2 changes only gesture handling and `initialCameraFit` against 8.3.1, so the facts checked in 8.3.1 under Context still apply. The boundary test (D9) keeps `lib/src/texture/` free of it. The texture core can be split into its own package later, as the concept doc describes.

## Risks / Trade-offs

- [`FrameTiming` uses a clock that the plugin can't read] → D24's offset estimate. If the estimate is ambiguous, report the match rate and the error only for unambiguous frames.
- [The engine stops exposing the frame number to Dart, or numbers it differently in builds and timings] → The probe from task 1.2 reports the match rate; rerun it after a Flutter upgrade.
- [The computed error is correct by construction when k_shown = k_used, so a bug in the conversion or in the transform math doesn't show in it] → The static test (D27) and the screen capture check (D29) test those independently.
- [During camera changes the transform uncovers strips at the viewport edges, which look like misalignment in the capture] → Measure the marker distance away from the edges. The size of the strips is reported, and decides whether overscan is needed. Observed in the manual check of task 3.3 on macOS (2026-10-11): during fast pans and rotations the markers and the polyline appeared to float above the map, which trailed them by a few pixels and realigned when the movement stopped; very fast pans and rotations left small empty strips at the viewport edges.
- [The last-reported-frame transform may be worse than no transform in some frames, when the frame shown is newer than the one used] → The report gives both errors. If the transform is worse, that's a result for the decision on per-buffer textures.
- [`flutter_map` adds dependencies (`http`, `path_provider`) to every user of the package] → Accepted under decision 11 of the concept doc; the package can be split later.

## Results and decision (task 7.1)

**Terms.** The letters used so far name two different things. Models A and B are the integration models of the concept doc (section 4). The ways to time the compensating transform were lettered A to C in the discussion before this change; from here on they have names:

- **Last-reported-frame transform** (formerly option A, D23): the layer builds the transform from the camera of the last displayed frame that Dart has been notified of. This change built and measured it.
- **Overlays follow the texture** (assumed to be the unwritten option B; concept doc section 8): overlays are positioned at the camera of the last displayed frame. Every overlay gets one or two frames of input latency. With the current pipeline Dart knows only the last displayed frame it has been notified of, so alignment is exact only together with per-buffer textures (`docs/camera-alignment-options.md`, option 4).
- **Per-buffer textures** (formerly option C): one Flutter texture per display buffer, so that Dart chooses the displayed frame and its transform in the same Flutter scene.

`docs/camera-alignment-options.md` describes these and the other options (overscan, removing the transform, camera prediction, model B), numbered 1 to 7.

**Results** (`benchmarks.md`, 2026-10-11, release builds, 3 runs each; logical px):

- At rest, the map and the overlays are aligned within 0.042 px on macOS and 0.071 px on the iOS simulator (D27).
- During pans the last-reported-frame transform halves the error, from two Flutter frames of camera movement to one. At 1,000 px/s, p50 / p95 is 8.33 / 16.7 px with the transform and 16.7 / 25 px without it, on the Mac (1600x1000) and on the iPhone. At 100 px/s it is 0.83 / 1.67 px with the transform.
- The remaining error comes from the timing problem this change set out to measure: in about 79% of Flutter frames during pans (77.6–87.2% over all pan phases and runs), Flutter displays a newer map frame than the one the transform was built for. With a smaller map (800x600 or 1400x880 on the Mac), where the map keeps up at 120 Hz, that happens in more than 90% of frames, and the transform doesn't reduce the p50 error at all.
- Zoom at 1 level/s: 5.46 px at p50 on the Mac with and without the transform; on the iPhone 2.96 px with it and 5.95 px without it. Rotation at 90 degrees/s: 12.35 against 24.7 px on the Mac, 6.72 against 20.14 px on the iPhone.
- The screen capture (D29) matched the computed error within 0.06 px at p50, so the numbers describe what reaches the screen. The uncovered strip at the viewport edge was 16 px during the pan at 1,000 px/s, two Flutter frames of movement.
- In the manual check (task 3.3) the overlays visibly appeared to float above the map during fast pans, and small empty strips appeared at the edges.
- The layer didn't measurably reduce the iPhone frame rate (6.2: a 4% difference in two of three runs, accepted as run-to-run variation, cause unknown).

**Decision** (2026-10-11): continue with model A and accept the current behavior (`docs/camera-alignment-options.md`, option 1). The layer keeps the last-reported-frame transform. The offset during camera changes and the uncovered strips are documented limitations, and the other options are future work.

- **Alignment threshold:** at rest, at most 1 logical px between the map and the overlays (the static alignment requirement). During camera changes, at most one Flutter frame of camera movement at p50, which is what the layer measured; at 120 Hz that is 0.83 px at 100 px/s and 8.33 px at 1,000 px/s.
- **Roadmap criterion:** the offset during fast pans is visible, so the layer is presented as a base layer with this limitation stated, not as a drop-in base layer.
- **Next experiment: camera prediction** (option 5), in its own change before Stage 4. The layer sends MapLibre the camera extrapolated from the camera's velocity and the measured lag. It is Dart code in the layer, so Android gets it too. The benchmark gets a phase that stops and reverses the pan, because prediction is most accurate at constant speed and overshoots when a gesture stops or reverses. We keep it if the p50 offset during the pan at 1,000 px/s is at most 4 px (half of now), and the overshoot after a stop is smaller than the current offset. Otherwise we record the result and drop it.
- **Future options, not planned:** overscan (option 2) for the strips, and per-buffer textures (option 6) for exact alignment during camera changes. Model B only if model A's alignment is later found unacceptable.
- The comparison with `flutter_map_maplibre`, which the roadmap lists for Stage 3, remains open; this change left it out of scope.

## Open Questions

- None. The alignment threshold is set under Results and decision.
