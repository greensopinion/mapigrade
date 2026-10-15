## 1. Package

- [ ] 1.1 Verify that the change `layer-metrics` is archived, so that `LayerMetrics` and the `metrics` parameter exist in the package; stop otherwise
- [ ] 1.2 Create `packages/demo` with `flutter create --platforms=android,ios,macos --org com.greensopinion --project-name mapigrade_demo` (D114), add it to the workspace in the root `pubspec.yaml` with `resolution: workspace` and `publish_to: none`, add the dependencies, set the bundle identifiers, and copy the example's platform values (Android `minSdk`, `abiFilters` and `gradle.properties`, iOS and macOS deployment targets, macOS network client entitlement) and its `analysis_options.yaml`; verify that `flutter pub get` at the root succeeds and that a diff of the platform values against the example shows only the identifiers
- [ ] 1.3 Add `lib/main.dart` with the app and the screen that states that the map isn't supported, and `lib/src/map_screen.dart` with a `FlutterMap` whose first child is `MapigradeLayer` with the Liberty style and an `onError` that shows the message; verify that `flutter run -d macos` shows the map and that dragging, pinching and rotating work

## 2. Stage data

- [ ] 2.1 Write `tool/waypoints.json` with the facts of stages 9, 7 and 4 from the spec's table, each with the `source` URL of its official stage page, and waypoints chosen from the official stage maps (D116): stage 9 through the Col d'Èze circuit and the Chemin des Vinaigriers, stage 7 through the Col de la Grande Limite, the Col du Colombier, the Col de Suzette, Beaumes-de-Venise and Bédoin, stage 4 through the Lacets de Marsannay; verify by reading each official stage page that the facts match
- [ ] 2.2 Write `tool/route_stages.dart` (D116) and run it to write `assets/tdff_2026.geojson`; verify that a second run writes the same file, that the asset is smaller than 200 KB, and that each route follows the race route in a GeoJSON viewer, adding waypoints where it doesn't
- [ ] 2.3 Write `lib/src/stages.dart`, which parses the asset into stage objects, and a test in `test/stages_test.dart` for the scenario "Data file contents" (order, facts, route ends within 1 km of the start and the finish); verify that the test passes

## 3. Overlays and attribution

- [ ] 3.1 Write `lib/src/stage_layers.dart` with the polylines, the start and finish pins, the bubbles and the shared pin for a loop (D117), and a control that hides and shows them; verify on macOS the scenarios "Stage 7 overlays", "Loop stage" and "Rotated map"
- [ ] 3.2 Write `lib/src/styles.dart` with the four styles and their attribution entries, add the style picker and `RichAttributionWidget` with the OpenStreetMap entry and the note that the routes are approximate (D120); verify on macOS the scenarios "Change style", "OpenFreeMap style" and "Routes are labelled approximate"

## 4. Metrics and alignment

- [ ] 4.1 Write `lib/src/rates.dart` and tests in `test/rates_test.dart` for the rates, for the average render time, and for an interval without rendered frames (D115); verify that the tests pass
- [ ] 4.2 Write `lib/src/metrics_panel.dart` with one `LayerMetrics` for the map screen, the 1 s timer and the UI rate from frame timings (D115); verify on macOS the scenarios "Camera moves" and "Map at rest" of the requirement "Metrics display"
- [ ] 4.3 Add the alignment setting (prediction with a lead of 1, 2 or 3, or none); verify on macOS the scenario "No alignment" and that the metrics continue after the change

## 5. Flyover

- [ ] 5.1 Write `lib/src/flyover.dart` (D118) and tests in `test/flyover_test.dart` for: the same camera for the same time and viewport; the stage order and the end at Dijon; the skipped finish of the loop stage; the rotation back to 0 before each transition; the zoom dip of a transition between stages; verify that the tests pass
- [ ] 5.2 Write `lib/src/flyover_player.dart` with the warm-up pass and the stop rules (D119), and add the play and stop controls and the warm-up choice; verify on macOS the scenarios "Stage order", "Warm-up pass" and "Stop by touch", and that a scroll-wheel zoom also stops the flyover

## 6. Platforms and documentation

- [ ] 6.1 Run the demo on the iOS simulator and on the Android emulator; verify on each the scenario "Demo runs on each platform", that the flyover plays to the end, and that the metrics update
- [ ] 6.2 Run the demo in a release build on the iPhone and on the Pixel; verify that the metrics show map frame rates while the flyover plays, and record them in the demo's README
- [ ] 6.3 Write `packages/demo/README.md` (what the demo shows, how to run it, the sources of the stage data, how to regenerate the routes, the routing service's usage policy), and update the repository layout in the root `README.md` with `packages/demo/` and the path of the internal library, `lib/src/testing.dart`, also in `docs/limitations.md`; verify by reading that every path the files name exists
- [ ] 6.4 Run `flutter analyze` and `flutter test` in `packages/demo`, and verify that both pass and that no Dart file of the demo imports a library under `package:flutter_mapigrade/src/` (scenario "Demo imports")
