## Why

Stages 1 and 2 of the roadmap in `docs/maplibre-native-ffi-flutter-texture-concept.md` showed that the texture core renders fast enough on macOS and iOS. Stage 3 tests integration model A: MapLibre renders the base layer, and `flutter_map` controls the camera, gestures and overlays. Model A is acceptable only if the map texture stays aligned with the overlays during camera changes. The texture is rendered on the map thread and lags the overlays by one or more Flutter frames (`limitations.md`). The concept doc plans to correct the lag with a compensating transform.

The transform has a timing problem. Dart builds it on the UI thread from the camera of the last displayed frame that Dart knows about. Flutter's raster thread chooses the displayed frame later, in `copyPixelBuffer`, and can choose a newer frame than the one the transform was built for. Then the transform is wrong by the camera change between the two map frames. We don't know how often this happens or how large the error is. This change builds the layer with the simple transform (the last-reported-frame transform) and measures its error. If the error is too large, a later change can make the displayed frame and its transform part of the same Flutter scene (per-buffer textures: one Flutter texture per display buffer).

## What Changes

- Add a `flutter_map` layer widget in `lib/src/layer/`. It creates and disposes a map, fills the `flutter_map` viewport, and sets the MapLibre camera from the `flutter_map` camera on every camera change.
- Convert the `flutter_map` camera to the MapLibre camera: MapLibre zoom = `flutter_map` zoom − 1, MapLibre bearing = −`flutter_map` rotation, viewport = the non-rotated size of the `flutter_map` camera.
- Wrap the texture in a compensating transform that maps the camera of the last reported displayed frame to the current `flutter_map` camera (the last-reported-frame transform).
- Report the time at which Flutter took each displayed frame, so that each frame can be matched to the Flutter frame that showed it.
- Add alignment instrumentation: for each Flutter frame, record the map frame used for the transform and the map frame shown, and compute the alignment error in logical pixels, without a transform and with the last-reported-frame transform.
- Add a static alignment test: a style marker and a `flutter_map` marker at the same coordinates, compared in a screenshot with the camera at rest.
- Add a `flutter_map` page to the example app and an alignment benchmark at several pan speeds. Measure on the reference Mac and the reference iPhone, and check the computed error against a capture of the Mac screen at 120 Hz.
- Add `flutter_map` as a dependency of `flutter_mapigrade`, pinned to an exact version. Only `lib/src/layer/` imports it (design D9 of the macOS slice).

We haven't set the alignment threshold yet. This change measures first. The threshold, and the decision whether per-buffer textures are needed, are recorded with the results.

Out of scope: per-buffer textures, rendering a margin beyond the viewport (overscan), the comparison with `flutter_map_maplibre`, map padding, pitch, Android, and MapLibre-side gestures. Each of these depends on the results of this change or belongs to a later stage.

## Capabilities

### New Capabilities

- `map-layer`: a `flutter_map` layer that displays the map texture as the base layer at the `flutter_map` camera, with a compensating transform, a static alignment requirement, and alignment measurement.

### Modified Capabilities

- `map-texture`: the requirement "Camera of each displayed frame" also reports the time at which Flutter took the frame for display, on the clock that Flutter's frame timings use.

## Impact

- Code: new Dart code in `packages/flutter_mapigrade/lib/src/layer/`; `lib/src/texture/` gains the display time in `FrameCamera`; `src/core/` records the time in `Present` and adds it to the frame-displayed event. The existing Dart API stays source-compatible.
- Dependencies: `flutter_map` and its dependency `latlong2` become dependencies of `flutter_mapigrade` and of the example app.
- Example: a new page that shows the map in a `FlutterMap` with marker and polyline overlays, and an alignment benchmark mode.
- Measurement: alignment results in `benchmarks.md`, and the Stage 3 decision in the roadmap of the concept doc.
