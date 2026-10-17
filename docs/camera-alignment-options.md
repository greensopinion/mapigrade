# Map and overlay alignment during camera changes: options

This document describes the alignment problem that Stage 3 measured (flutter-map-layer change) and the options for the Stage 3 decision. The measurements are in `benchmarks.md` (Alignment during camera changes). Logical pixels are abbreviated px.

Decision (2026-10-11): option 1, accept the current behavior, with option 5, camera prediction, as the next experiment. The reasons and the criteria for the experiment are in the change's design (`openspec/changes/archive/2026-10-11-flutter-map-layer/design.md`, Results and decision).

Since then, camera prediction (option 5) became the layer's default (2026-10-11), and on 2026-10-12 we removed the compensating transform (remove-camera-transform change). The layer now offers camera prediction and no alignment (option 3). The sections below describe the options as they were at the Stage 3 decision.

## Problem

In integration model A, `flutter_map` controls the camera and draws the overlays, and MapLibre renders the base map into a Flutter texture on its own thread. When the camera changes in Flutter frame N, the overlays are drawn at the new camera in frame N. The map frame for that camera is rendered on the map thread and reaches the screen one or more Flutter frames later. Until then the screen shows an older map frame below the new overlays.

`MapLibreTextureLayer` corrects this with a compensating transform. It moves, scales and rotates the displayed map frame to where the current `flutter_map` camera places it. Dart builds the transform during the Flutter frame's build, from the camera of the last displayed map frame that Dart has been notified of. Flutter's raster thread chooses the displayed map frame later, in `copyPixelBuffer`, and often chooses a newer frame than the one the transform was built for. The transform then corrects for more camera movement than the displayed frame lags by.

Measured on 2026-10-11 on the reference Mac (window 1600x1000) and the reference iPhone, release builds, 3 runs each:

- At rest, the map and the overlays are aligned within 0.1 px.
- During pans, Flutter displays a newer map frame than the transform was built for in about 79% of Flutter frames (77.6–87.2% over all pan phases and runs).
- With the transform, the map is one Flutter frame of camera movement off the overlays at p50. Without it, the map is two Flutter frames off. At 120 Hz one Flutter frame of movement is the pan speed divided by 120:

  | Pan speed | With transform, p50 / p95 | Without transform, p50 / p95 |
  | --- | --- | --- |
  | 100 px/s | 0.83 / 1.67 px | 1.67 / 2.5 px |
  | 500 px/s | 4.17 / 8.33 px | 8.33 / 12.5 px |
  | 1,000 px/s | 8.33 / 16.7 px | 16.7 / 25 px |
  | 2,000 px/s | 16.7 / 33.3 px | 33.3 / 50 px |

- Rotating at 90 degrees per second gives 12.35 px at p50 with the transform on the Mac and 6.72 px on the iPhone. Zooming at 1 level per second gives 5.46 px on the Mac and 2.96 px on the iPhone.
- When the transform moves the displayed map frame, it uncovers strips at the viewport edges where nothing is drawn. During a pan at 1,000 px/s the strips are 16 px wide, two Flutter frames of movement, in almost every moving frame.
- A screen capture of the Mac window matched the computed error within 0.06 px, so these numbers describe what reaches the screen.
- In a manual check on the Mac and the iPhone, the overlays visibly appeared to float above the map during fast pans and rotations, and realigned when the movement stopped. Very fast pans and rotations showed the empty strips.

The alignment threshold during camera changes isn't decided. The roadmap's criterion for Stage 3 is: if the texture is visibly misaligned with the overlays, don't present it as a drop-in base layer, and consider model B.

## Options

The options differ in the offset between map and overlays during camera changes, the empty strips at the edges, the latency between a gesture and what the screen shows, and the work and rendering cost they add. Options 2 and 5 can be combined with the others.

### 1. Accept the current behavior

Keep the layer as it is. Document the offset during camera changes and the strips as known limitations, and keep the other options as future work.

- Offset: as measured, one Flutter frame of movement at p50 (8.33 px at 1,000 px/s).
- Strips: as measured, two Flutter frames of movement (16 px at 1,000 px/s).
- Work: none. Stage 4 (Android) can start next.
- The offset is small at slow drags (0.83 px at 100 px/s) and disappears at rest. It is visible during flings.
- The alignment threshold would be set at the measured behavior, for example one Flutter frame of movement at p50. The roadmap's criterion for Stage 3 is not met, because the offset is visible, so the layer would be presented with this limitation stated, or the criterion changed.

### 2. Add overscan

Render each map frame larger than the viewport by a margin on every side, and draw it offset by the margin. When the transform moves the frame, it reveals the margin instead of empty space.

- Offset: unchanged.
- Strips: removed while the transform moves the frame by less than the margin. A margin of 16 px covers pans up to about 1,000 px/s with the current transform. Rotation needs more at the corners, and zooming out needs more on every edge.
- Cost: more pixels to render. A margin of 10% on each side is 1.44 times the pixels. On the iPhone a frame already takes about 8.2 ms against a refresh interval of 8.33 ms, so a margin lowers the frame rate, and a lower frame rate increases the offset and the strip width.
- Work: moderate. The transform already places a frame by its own center and size, so the alignment math hardly changes.
- Not applicable since the remove-camera-transform change: without the transform the layer uncovers no strips.

### 3. Remove the compensating transform

Draw the texture where the layer is, without a transform.

- Offset: two Flutter frames of movement at p50 (16.7 px at 1,000 px/s), twice the current offset.
- Strips: none, because the texture isn't moved.
- Work: removes code. It also removes the case in which the transform would move the frame out of view, which the layer now has to detect.
- This option makes the floating look worse and is listed for completeness.
- Done in the remove-camera-transform change (2026-10-12), together with camera prediction (option 5) as the default. `CameraAlignment.none` selects this option alone.

### 4. Overlays follow the texture

Draw the overlays at the camera of the displayed map frame instead of the current camera, by applying the inverse transform to the overlay layers. The map and the overlays then move together, and both lag the gesture.

- With the current pipeline, Dart knows only the last displayed map frame it has been notified of, the same frame the current transform uses. In about 79% of Flutter frames the screen shows a newer map frame, so the overlays would be one Flutter frame of movement off the map, as now. This option aligns exactly only together with option 6, which tells Dart which frame each Flutter frame displays.
- Strips: none, because the texture isn't moved.
- Latency: the overlays lag the gesture by the same one or two Flutter frames as the map. Touch input on overlays, for example tapping a marker, is then hit-tested against positions that are one or two frames old.
- Work: small on its own; the transform math exists. It needs `flutter_map` layers to accept a transform, or a wrapper around them.

### 5. Predict the camera

Send MapLibre the camera that `flutter_map` is expected to have when the map frame is displayed, extrapolated from the current camera velocity and the measured lag, instead of the current camera.

- Offset: during steady pans, rotations and zooms, close to 0 if the prediction matches the lag. When the gesture accelerates, stops or reverses, the prediction is wrong for a few frames, and the map overshoots and returns.
- Strips: depend on whether the transform stays, and how far it then moves the frame.
- Work: small. The alignment benchmark measures the result directly.
- Measured (camera-prediction change, 2026-10-11), without the transform, with leads of 1 to 3 refresh intervals. With a lead of 1, pans at 1,000 px/s had a p50 error of 0 or 8.33 px on the Mac and 8.33 px on the iPhone, with the map lagging by 4.2–7.9 px on average and no strips; after abrupt stops and reversals the map ran ahead by 7–8 px and 22–25 px. A lead of 2 had a p50 error of 0.02 px on the iPhone but felt worse in a manual check. In the manual check on both devices a lead of 1 felt best; the overlays floated only while a fling decelerated.
- Decision (2026-10-11): make a lead of 1 the default. Results in `benchmarks.md`; the decision in the camera-prediction change's design. The camera-prediction-default change made `CameraAlignment.prediction()` the layer's default, and the remove-camera-transform change removed `CameraAlignment.transform`, which selected the behavior of option 1. `CameraAlignment.none` selects that of option 3.

### 6. One Flutter texture per display buffer

Register each display buffer as its own Flutter texture. Dart chooses which texture each Flutter frame shows, so the displayed map frame and its transform are part of the same Flutter scene, and the transform always matches the displayed frame.

- Offset: expected close to 0 during camera changes, apart from rounding. Not measured.
- Strips: wider than now. Dart can choose only frames it has been notified of, so the displayed frame is older than with the current pipeline, and the transform moves it further. Option 2 is needed with it.
- Latency: the map shows older frames than now, but the transform hides the difference while the camera moves.
- Work: large. It changes how the native core hands frames to Flutter on macOS and iOS: buffer lifetime, texture registration, and the frame-available notifications.
- Cost: possibly a lower frame rate, because a buffer stays in use until Dart releases it. Not measured.
- With option 4 instead of the transform, it aligns the overlays exactly without strips, at the cost of overlay latency.

### 7. Model B: MapLibre controls the camera

MapLibre handles gestures and camera animation, and the Flutter overlays follow MapLibre's camera.

- Offset: depends on how the overlays follow MapLibre's camera, and has the same kind of timing problem unless the displayed frame's camera reaches Dart with the frame.
- Work: very large. The concept doc lists gestures, camera animation, sources, layers, annotations, projection and more, well over the 20 to 30 C functions of model A.
- The roadmap names it as the fallback if model A's alignment fails.

## Comparison

| Option | Offset at 1,000 px/s, p50 | Strips | Overlay latency | Work | Measured |
| --- | --- | --- | --- | --- | --- |
| 1. Accept | 8.33 px | 16 px | none | none | yes |
| 2. Overscan | unchanged | covered up to the margin | none | moderate | no |
| 3. No transform | 16.7 px | none | none | removes code | yes |
| 4. Overlays follow the texture | 8.33 px alone; close to 0 with 6 | none | 1–2 frames | small | no |
| 5. Predict the camera | lead 1: 0 or 8.33 px (Mac), 8.33 px (iPhone); 4.2–7.9 px behind on average | none | none | small | yes |
| 6. One texture per buffer | expected close to 0 | wider than now; needs 2 | none | large | no |
| 7. Model B | depends | depends | depends | very large | no |

## Manual check with children (layer-children-alignment change, task 5.4)

The layer-children-alignment change took options 6 and 4 together: the overlays are children of the layer, which draws them at the camera of the map frame it displays. On 2026-10-17 we checked the harness's `flutter_map` page with the polyline and the markers as children, with `predict1` and with `none`: pans, flings, abrupt stops, reversals, and taps on a marker during a pan.

- macOS: the overlays stayed exactly on the map in every motion. Map and overlays together trail the pointer slightly, by an amount that changes with the pointer's speed and acceleration. `predict1` made this trailing least noticeable for natural pointer movements. We kept the lag and `predict1` as the default.
- iPhone (by finger): the overlays stayed exactly on the map in every motion. The trailing felt the same as on the Mac, and `predict1` was again the best.
- iPhone, second look: in slow, steady pans `predict2` seemed to track the finger better, though the finger hides part of the map. The camera-prediction change's iPhone measurements agree: in steady pans the map was 0.1 to 0.5 px ahead of the live camera with `predict2` and 0.8 to 7.9 px behind with `predict1`, but at abrupt stops `predict2` ran 14.7 px ahead against 6.7 to 6.9 px. On the Mac `predict1` was closer.
- Decision: the children's lag is acceptable, and `predict1` stays the default on both platforms.
- Taps: a tap on a marker of the stopped map hit the marker. A tap during a pan was too hard to coordinate by hand, and we judged it an unusual pattern; the widget test "a polyline hit-tests where it is drawn" covers hit tests while the displayed camera differs from the live one.
- Skipped renders: in one of 72 benchmark phases (task 5.3), the map skipped 2 renders in a stall of about 117 ms. We accepted it; it doesn't show that four slots are too few.
