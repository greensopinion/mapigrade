## Context

See proposal.md for motivation and scope, and specs/map-layer/spec.md for the requirements. The designs of the flutter-map-layer change (D21 to D30, `openspec/changes/archive/2026-10-11-flutter-map-layer/design.md`) apply unchanged. Decisions here are numbered from D31.

Current state, as checked in this repository on 2026-10-11:

- `MapLibreTextureLayer` (`lib/src/layer/map_libre_texture_layer.dart`) converts the `flutter_map` camera with `viewCameraOf` during build and calls `setCamera` when the converted camera differs from the last one sent. It rebuilds on every `flutter_map` camera change (`MapCamera.of`) and on every frame-displayed event (a `setState` in its `frames` listener). It draws the texture with `layerTransform`, or without a transform when no frame has been displayed or the transform would move the frame out of view.
- `MapTextureView` reads the display refresh rate from `View.of(context).display.refreshRate`.
- In a frame callback, `SchedulerBinding.currentSystemFrameTimeStamp` is the frame's vsync target time (flutter-map-layer D25), one refresh interval apart from frame to frame.
- The alignment benchmark (`example/lib/alignment_benchmark.dart`) records, per Flutter frame, the target camera C_N, the frame the transform used and the frame Flutter displayed, and computes the error with and without the transform (`alignmentError`). Its phases are functions from time to camera.
- Measured without the transform (Stage 3): the displayed map frame is two Flutter frames of camera movement behind the overlays at p50 and three at p95, on the Mac at 1600x1000 and on the iPhone.
- `flutter_map` ends a pan gesture faster than 800 px/s with a fling: an overdamped spring (`SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 5)`), starting at the release velocity and covering the viewport's shorter side (`map_interactive_viewer.dart`, 8.3.2).

## Goals / Non-Goals

**Goals:**
- A measurement that decides between prediction and the current transform with the criteria from Stage 3: p50 at most 4 px during the pan at 1,000 px/s, and p50 overshoot below 8.33 px over the stops of the fling phase.
- Prediction that leaves the alignment at rest exact.

**Non-Goals:**
- Tuning the predictor beyond the lead (no filters or adaptive leads in this change). If the fixed lead fails narrowly, the result names what a tuned predictor would have to improve.
- A stable API: the new layer parameters are experimental and can change or disappear.

## Decisions

### D31. Layer options

`MapLibreTextureLayer` gains two optional parameters, documented as experimental:

- `compensatingTransform` (bool, default true): when false, the layer draws the texture without a transform.
- `cameraPrediction` (a lead in refresh intervals, default null = off): when set, the layer sets the predicted camera (D32, D33) and draws without a transform, whatever `compensatingTransform` says.

Prediction turns the transform off because the two don't combine: with the transform, the frame the transform was built for is moved exactly to the current camera, and a newer displayed frame is off by the camera difference between the two frames, one frame of movement, whether both were rendered at predicted cameras or not.

*Alternative:* a single mode enum. Two parameters keep "no transform, no prediction" expressible, which the benchmark measures as the baseline for prediction.

### D32. Velocity of the camera

During each build the layer records the converted camera C_N with the frame's vsync target time t_N (`currentSystemFrameTimeStamp`). The velocity is the difference to the camera of two builds earlier, divided by the time between them: (C_N − C_{N−2}) / (t_N − t_{N−2}), or over one build if only one earlier build is recorded. Differences use the same coordinates as the transform: center in normalized Web Mercator with the x difference wrapped to [−0.5, 0.5) (shorter longitude difference), zoom linearly, bearing as the signed shorter angle. If C_N equals the camera of the previous build, the velocity is 0, so the camera at rest is never predicted ahead. Records older than 50 ms are dropped, so a pause between gestures starts from zero velocity.

*Alternatives:* one interval (more sensitive to uneven input events), a moving average or a filter over more frames (smoother, but responds later to a stop, which increases overshoot). Two intervals is a compromise; the manual check (task) shows whether input noise makes the map jitter.

### D33. Predicted camera

The predicted camera is C_N + velocity × lead / refresh rate, with the refresh rate from `View.of(context).display.refreshRate` (60 if unknown). The predicted center is converted back to latitude and longitude, with the latitude clamped to the Mercator limit and the longitude normalized to [−180, 180). The layer sends the predicted camera to `setCamera` when it differs from the last one sent, as it does now with the converted camera. The overlays keep using the current `flutter_map` camera.

The predictor is a pure Dart function in `lib/src/layer/` with unit tests, like the camera conversion.

### D34. Benchmark configuration

`--dart-define=ALIGNMENT_MODE=` selects the layer configuration: `transform` (default, the current behavior), `none` (no transform, no prediction), or `predict1`, `predict2`, `predict3` (prediction with that lead). Each result line states the mode, and a new field `error_drawn_px` gives the error of what the layer draws: with the transform in `transform` mode, without it otherwise. The recorded cameras of displayed frames are the cameras they were rendered with, which in prediction modes are predicted cameras, so the error computation (flutter-map-layer D26) applies unchanged.

### D35. Stop, fling and reversal phases

Three phases join the existing ones, each 20 s, at 1,000 px/s over the existing pan path:

- `stop`: pan for 1 s, then rest for 1 s, repeated.
- `fling`: pan for 1 s, then decelerate as `flutter_map`'s fling does (the spring from Context, starting at 1,000 px/s and ending after the viewport's shorter side), then rest until the 2 s cycle ends, repeated.
- `reverse`: pan, reversing the direction abruptly every 1 s.

Each phase also yields the times at which its motion changes. For each change, the overshoot is the largest drawn error over the Flutter frames whose vsync time lies from the change until 0.5 s after the camera is at rest or at constant speed again; for the fling the window starts when the deceleration starts and ends 0.5 s after the remaining distance is below 0.5 px. The result line reports p50 and largest overshoot over the changes in the phase.

### D36. Measurement plan

On the reference Mac at 1600x1000 ("More Space" display setting) and the reference iPhone, release builds, phases pan500, pan1000, pan2000, zoom, rotate, stop, fling and reverse:

- Mac: all five modes, 2 runs each. The Stage 3 runs agreed within a few hundredths of a pixel between runs, so 2 runs show the spread.
- iPhone: `transform`, `none` and the prediction lead that did best on the Mac, 2 runs each.

The decision applies the Stage 3 criteria to the best prediction lead: p50 of `error_drawn_px` during pan1000 at most 4 px, and p50 overshoot in the fling phase below 8.33 px. The abrupt stop and the reversal are reported and judged in the manual check.

## Risks / Trade-offs

- [Uneven input events make the velocity noisy, and the prediction multiplies the noise by the lead, so the map jitters while dragging by hand] → The synthetic benchmark can't show it; the manual check on the Mac and the iPhone does. If it jitters, the result names smoothing as the next step, with its cost in overshoot.
- [The lag between setting a camera and displaying its frame varies: Flutter displays a newer frame than expected in about 79% of frames] → A fixed lead can't match every frame; the measurement over leads 1 to 3 shows the best fixed lead and its p95.
- [Without the transform, rotation and zoom errors are uncorrected unless predicted too] → D32 predicts zoom and bearing as well; the zoom and rotate phases measure them.
- [Prediction changes the frames MapLibre renders, which could change its frame rate] → Each result line reports the map frame rate; compare with the `transform` mode.
- [Leads larger than the real lag make the map run ahead of the overlays during steady pans] → The pan phases show it as error in the opposite direction; the error measure is a distance, so the report also needs the sign: report the mean signed offset along the pan direction for pan phases.

## Open Questions

- None that change the plan. Whether prediction becomes the default is decided after the measurements and implemented separately.
