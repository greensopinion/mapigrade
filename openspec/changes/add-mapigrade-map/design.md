## Context

After `port-ffi-gesture-recognizer` and `split-mapigrade-package`, `mapigrade` contains the native core, `MapTextureController`, `MapigradeController` and the polylines, and the map thread keeps each frame's `frame_projection` (D226). The only widget is `MapigradeLayer` in `flutter_mapigrade`, whose camera comes from `flutter_map`: Dart writes each camera into the camera slot with a sequence number, the map thread submits the latest one, and `MapTextureLayer` draws its children at the `flutter_map` camera of the frame it chose with `selectNewest` (`docs/architecture.md`).

The FFI provides what a widget needs when MapLibre owns the camera: camera commands with transition outcomes (`mln_map_update_camera`, `mln_map_fit_camera_to_lat_lng_bounds`, `mln_map_cancel_camera_transitions`), bounds and zoom and pitch limits (`mln_map_set_bounds`), camera events with their source, and the gesture recognizer (`gesture.h`), which takes the host's raw input and moves the camera itself with camera commands. The frame projection's matrix takes Web Mercator x and y from 0 to 1 and z in meters to the frame's clip space, in the clip depth convention of the device's API.

See proposal.md for the motivation and the specs for the requirements.

## Goals / Non-Goals

**Goals:**
- Overlays drawn by Flutter stay on the displayed frame under pitch, with no camera in Dart other than the displayed frame's.
- Gestures that feel like each platform's, and that share input with Flutter widgets by Flutter's rules.
- `MapigradeLayer` unchanged.

**Non-Goals:**
- Terrain, web, globe projection, the free camera, the projection mode, and markers built only near the viewport.
- Pitch in `MapigradeLayer`, which depends on `flutter_map`.

## Decisions

### D235. MapLibre owns the camera of a `MapigradeMap`

`MapTextureController` gets a mode in which the map owns its camera. In that mode Dart never writes the camera slot. The map is created at the initial camera and limits, and the camera changes only through gestures and camera commands. The frame report keeps its camera sequence number for the layer; for `MapigradeMap` it is unused, because no camera in Dart has to be matched to a frame.

Alternative: keep the camera in Dart and send absolute cameras, as the layer does. That is model 1 of the exploration. It needs Dart to reproduce MapLibre's transform for gestures, glides, limits and, later, terrain.

### D236. Camera commands and limits through the command queue

The C ABI gets functions for jump, ease, fly, fit to bounds and cancel. Each carries a request id, and the limits get a function of their own. They go through the ordered command queue, and the map thread submits them as FFI commands with an end handler. The handler reports the outcome as a new event with the request id, which completes the command's `Future`. Limits map to `mln_bound_options`, and `GeoBounds` to `mln_lat_lng_bounds`.

### D237. Gesture input on the platform thread, with a fallback

`MapigradeMap`'s input adapter calls a new C ABI function that passes one `mln_gesture_input` to `mln_gesture_recognizer_handle` on the calling thread and returns the result: whether the input was handled, the next tick, the box zoom rectangle and the events. The recognizer sends its camera moves to the map as FFI commands itself, so the input never waits for the map thread. A Flutter `Ticker` calls the tick function while the result asks for a tick every frame, and a `Timer` handles a tick at a time.

`gesture.h` doesn't state which threads may call the recognizer. The first task asks upstream or reads mln-rs to find out. If calls must come from one thread other than the platform thread, inputs go through a queue of their own to the map thread, and the result's events return as events; the adapter then decides the gesture arena without the result (D238), as it does anyway.

### D238. A gesture arena member that forwards to the recognizer

The adapter is a recognizer of its own in a `RawGestureDetector` around the texture, with these rules:

- **Tracking.** It tracks every pointer that hits the map, and keeps each pointer's events until it wins the arena or loses.
- **Accepting.** It accepts a pointer when the pointer moves past the pan slop with pan on, or when a second pointer goes down on the map.
- **Releasing.** It releases a pointer whose movement only a disabled part of `MapigradeGestures` would use.
- **Taps.** It doesn't accept a pointer on its lift. A child's tap recognizer, which is deeper in the hit test and so earlier in the arena, therefore wins a tap on the child.
- **Replay.** When it wins, it sends the kept events to the recognizer in order, so that the ground under the finger catches up with the finger.

Trackpad pinch and scroll arrive as `PointerPanZoom` events. Their pan becomes a continuous `MLN_GESTURE_INPUT_DELTA`, and their scale and rotation an `MLN_GESTURE_INPUT_PINCH` with the event's phase. The mouse wheel goes through Flutter's `PointerSignalResolver` as discrete deltas of a third of a level per detent, so that an enclosing scrollable doesn't also scroll. Held Shift and Ctrl, and the right mouse button, become `MLN_GESTURE_INPUT_MODES` and the pointer's modes. The keyboard goes through a `Focus` around the map as discrete deltas. A click on the map requests focus.

Alternative: a `Listener` that sends every pointer to the recognizer. It takes no part in the arena, so a marker's tap would also move or tap the map, and a list around the map would scroll while the map pans.

### D239. Taps come from the recognizer, delayed for double taps in Dart

The recognizer reports `TAP` when the first tap lifts and `DOUBLE_TAP` on the second. When double-tap zoom is on, the adapter holds a `TAP` for Flutter's `kDoubleTapTimeout` and drops it when a `DOUBLE_TAP` arrives. When double-tap zoom is off, it calls `onTap` at once. `LONG_PRESS` calls `onLongPress`. A tap of the right button with no drag calls `onSecondaryTap`. The tap's coordinate comes from `MapigradeFrame.unproject` on the frame displayed when the tap lifted.

### D240. Momentum per platform

The recognizer is created with momentum for `defaultTargetPlatform`. On iOS and macOS: `MLN_MOMENTUM_DECAY_MODEL_FRICTION` with a half-life of 346 ms on every part. On Android: `MLN_MOMENTUM_DECAY_MODEL_CURVE` with its defaults. The other recognizer defaults stay: the snap to north within 7 degrees and its notch, and the release speeds that glide. `MapigradeGestures` maps to the parts' `enabled` and `glides` fields, the snap, and the tap zoom amounts.

### D241. The frame projection in Dart

`map_texture_select_newest` also returns the frame's matrix as 16 doubles, the frame's pitch, and the clip depth convention. `MapigradeFrame` keeps them with the frame's camera and logical size, all as doubles.

- **Projecting a coordinate.** Convert it to Web Mercator x and y in [0, 1) and z in meters, choosing the x of the copy of the world nearest the camera's center. Multiply by the matrix and divide by w; the viewport transform then gives logical pixels. A w of 0 or less has no position.
- **Projecting a position.** Invert the matrix, cast the ray through the position, and intersect it with z = 0. A ray that doesn't meet the ground in front of the camera has no coordinate.

Projecting a position assumes that the ground is the Mercator plane at altitude 0. Over terrain the ground is above that plane, and on a globe it is a sphere. So the terrain change replaces the intersection with a call to the FFI's projection on the drawn terrain, and the globe change replaces it with an intersection with the sphere. The globe change also has to find out what `frame_projection` contains when the map draws a globe.

A test compares the projection with `mln_map_projection_pixel_for_lat_lng` on the same frame.

Alternative: call the FFI projection for each conversion. That costs an FFI call per point and blocks the build on the map's snapshot lock. The matrix is never newer than the frame, while the FFI projection is of the map's current view.

### D242. `MapigradeFrame` as an inherited model, markers as a render object

`MapigradeMap` builds an `InheritedWidget` with each displayed frame's `MapigradeFrame`, so that widgets that read it rebuild once per displayed frame, as flutter_map's layers do.

`MapigradeMarkers` is a multi-child render object widget. Its render object listens to the displayed frame through a `ValueListenable` that `MapigradeMap` provides, not through the inherited model, so a new frame calls `markNeedsPaint` without rebuilding the markers. Layout lays each child out with loose constraints, and runs only when the children or the widget's size change.

Paint computes a transform for each marker:

- **Upright.** A translation to the projected point, minus the alignment's offset in the child. With perspective scaling, a scale of w at the center divided by w at the point.
- **On the ground.** The frame's matrix composed with a basis on the ground plane at the point. The basis maps one logical pixel of the child to the ground distance of one logical pixel at the camera's center, turned by the bearing for the rotation alignment `viewport`.
- **Rotation alignment `map` when upright.** A rotation by the bearing.

Markers are painted in order of decreasing w, then list order. Hit testing goes through the same transforms in reverse paint order. A marker is skipped in paint and hit testing when:

- its w is 0 or less;
- its clip z is outside the depth range of the convention;
- its transformed bounds miss the widget.

Every child stays mounted.

Alternative: rebuild a `Stack` of `Positioned` children each frame, as flutter_map's `MarkerLayer` does. The spec requires that a marker's child isn't rebuilt per frame.

### D243. Camera streams from frames and camera events

The map thread records the source of each FFI camera event and the snapshot generation it applies to. Each published frame carries the source of the last camera change it includes. `cameraChanges` emits a `CameraChange` when the displayed frame's camera differs from the previous displayed frame's.

The rest stream emits when all of these hold:

- an FFI camera-did-change event that isn't animated has arrived;
- no pointer is down on the map;
- the recognizer asks for no tick;
- a frame with that camera has been displayed.

It emits at most once per rest.

### D244. `Mapigrade` holds the process-wide settings

`Mapigrade.isSupported` and `Mapigrade.maximumCacheSizeBytes` hold the values. `MapigradeLayer`'s static members read and write them through the integration library.

### D245. Haptics and the box zoom

A `NOTCH` event plays `HapticFeedback.selectionClick()` on iOS and Android unless the widget's setting turns it off. While `box_zoom_active` is set, `MapigradeMap` draws the result's rectangle above the texture and below its children.

### D246. Where a web backend would differ

Two decisions here would change for web, because a Web Worker can't answer synchronously:

- `MapigradeTap.coordinate` and `MapigradeFrame.unproject`, which are synchronous.
- Terrain elevation for markers, which the terrain change will read synchronously from the FFI projection. On web it would be an asynchronous cache.

Everything else works the same on web: the frame matrix, markers, controllers and streams. The web follow-up starts from these two.

### D247. `MapigradeCamera` has every field of `mln_camera`

`MapigradeCamera` has the center, the center altitude, the zoom, the bearing, the pitch, the roll, the field of view and the padding, as `mln_camera` does. `map_texture_select_newest` returns them for each frame beside the matrix (D241). The camera commands set the bit of `mln_camera_options` only for the fields that the command's camera sets (D236), and `cameraChanges` compares all of them (D243). The frame matrix already includes them, so neither the markers nor `MapigradeFrame` need code for them.

The free camera (`mln_map_set_free_camera_options`) and the projection mode (`mln_map_set_projection_mode`) aren't fields of `mln_camera`, and stay out of this change. A later change can add them as commands without changing `MapigradeCamera`.

Alternative: only the center, zoom, bearing and pitch, with fields added when an application needs them. The camera of the displayed frame would then not be the whole camera that the frame was drawn with, and the camera stream would miss changes to the padding or the roll.

## Risks / Trade-offs

- [The recognizer's thread rules don't allow calls from the platform thread] → D237's fallback; the first task settles it before the adapter is written.
- [The pointer events replayed after the map wins make the map jump] → Check on the iPhone and the Pixel; if the jump is visible, send only the movement after the slop.
- [The latency from a gesture to the displayed frame is noticeable, because the camera moves on the map thread] → The latency measurement reports it on each device; children lag the finger as the map does, so they stay aligned.
- [A 346 ms half-life feels too long for a map] → The manual device check decides, and D240 changes the half-life if needed.
- [Flutter's double-tap timeout differs from the recognizer's double-tap window] → An adapter test covers taps on both sides of the timeout; if the windows differ, the adapter uses the recognizer's.
- [Many markers cost more than flutter_map's culling, because every child stays mounted] → The frame-rate benchmark with many markers measures it; a builder that builds only nearby markers can be added later.
- [The clip depth convention differs between Metal and OpenGL] → D241 passes the convention with the matrix, and the hiding tests run on macOS and Android.

## Migration Plan

Additive: `MapigradeLayer` and its applications don't change, apart from `MapigradeLayer`'s static members delegating to `Mapigrade`. Archive `split-mapigrade-package` before this change, because this change's deltas for `package-api` and `feature-query` modify requirements in the form that change gives them.
