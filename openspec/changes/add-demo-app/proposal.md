## Why

Developers who want to evaluate `flutter_mapigrade` have two apps to choose from, and neither fits. The example shows one style and one marker, and it must stay minimal: the `publish-readiness` CI job copies its `lib/main.dart` into a new consumer app. The test harness has a style list, a map frame rate counter and scripted pans, but it selects them with `--dart-define`, prints results for scripts, and states that it is not a usage example. We want an app that a developer builds from source and uses to try styles, gestures and overlays on their own devices while watching frame rates, and that plays a flyover that someone can record.

## What Changes

- A new app, `packages/demo`, added to the workspace with `publish_to: none`. It runs on Android, iOS and macOS.
- The demo shows the map with `MapigradeLayer` as the base layer of a `FlutterMap`, with `flutter_map` gestures, a style picker, and a display of the map's displayed and rendered frame rates, its average render time per frame, and the Flutter UI frame rate. The map values come from snapshots of a `LayerMetrics`, the public API that the change `layer-metrics` adds, taken once per second; the UI frame rate comes from Flutter's frame timings.
- The first version offers keyless styles only: OpenFreeMap Liberty, Bright and Positron, and the MapLibre demo tiles.
- Settings for the alignment mode (camera prediction with a lead, or none), so that a developer can compare them while the camera moves.
- A Tour de France Femmes avec Zwift 2026 overlay with stages 9, 7 and 4, in that order. Each stage has a green start pin with a bubble that states the stage, its distance and its winner, a red finish pin, and a polyline along the route. Where a stage starts and finishes at the same place (stage 9, Nice to Nice), one marker shows both.
- A flyover that plays a fixed sequence for each stage: the start, the whole route, the finish, then to the next stage by zooming out, panning and zooming in. The camera position is a function of elapsed time, so every run shows the same view at the same time. An optional warm-up pass plays the sequence once to load tiles before the visible run. A touch on the map stops the flyover.
- A stage data file in the demo's assets, with each stage's facts and route coordinates. The routes are approximate: a script in `packages/demo/tool/` computes them with a router on OpenStreetMap data from waypoints that we choose, and we commit its output. The demo states that the routes are approximate. Stage facts come from a cited source; where sources disagree (the distance of stage 7 is 146.8 km in one table and 144 km in another), we use the figure from letourfemmes.fr.
- OpenStreetMap attribution on the map.
- The demo imports only `package:flutter_mapigrade/flutter_mapigrade.dart`, so that its code shows what an application can use. When the demo gives the layer a new key, it creates a new `LayerMetrics` with it.

Non-goals:

- No video recording in the demo.
- No distribution of built apps (app stores, TestFlight, Play tracks, signed macOS builds).
- No pitch: the map supports center, zoom and bearing only.
- No styles that need an API key, and no place to enter keys. We plan to add both later.
- No mode in which the camera follows the route.
- No change to the package: the metrics API is the change `layer-metrics`.
- No change to the example or the test harness.

## Capabilities

### New Capabilities

- `demo-app`: the demo app's platforms, styles, frame rate display, alignment settings, Tour de France overlay, flyover sequence, stage data and its sources, and attribution.

### Modified Capabilities

None.

## Impact

- New package: `packages/demo/` (Dart sources, Android, iOS and macOS runners, assets, `tool/` script). Dependencies: `flutter_map` 8.3.2 and `latlong2`, at the versions the example uses, and `url_launcher` for the attribution links.
- Workspace: `pubspec.yaml` at the repository root adds `packages/demo`.
- Package: none. The demo depends on `LayerMetrics` and the `metrics` parameter of `MapigradeLayer` from the change `layer-metrics`, which is archived before this one.
- Network: the demo loads styles and tiles from OpenFreeMap and demotiles.maplibre.org. The route script calls a routing service once per stage when we run it; the design chooses the service and checks its usage policy.
- Data licensing: the routes are derived from OpenStreetMap data under the ODbL, which the attribution covers.
- Documentation: `README.md` (repository layout and how to run the demo). The layout in `README.md` and `docs/limitations.md` name `lib/testing.dart`; the library is `lib/src/testing.dart`, which this change corrects.
- Interaction with `publish-readiness`: the demo's `android/gradle.properties` needs the same local FFI setting as the example and the test harness (task 5.3 of that change), whichever change is archived second.
