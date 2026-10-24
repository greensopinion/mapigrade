## 1. Code layout and gallery

- [x] 1.1 Move the demo's files into `lib/src/common/` and `lib/src/flyover/` as D191 states, rename `MapScreen` to `FlyoverScreen`, and move the tests with their files; verify that `flutter analyze` and `flutter test` in `packages/demo` pass
- [x] 1.2 Extract the style picker and the panel card with its header into `lib/src/common/`, and use them in `FlyoverScreen`; verify on macOS that the flyover screen looks and behaves as before (scenario "Change style")
- [x] 1.3 Add `lib/src/gallery.dart` and the gallery entries in `main.dart` (D190), move `Recording.fromEnvironment()` to `main.dart`, and give `FlyoverScreen` the recording mode and the back control as parameters; verify on macOS the scenarios "Launch", "Open the flyover screen" and "Go back during the flyover", and on the Android emulator the scenario "Platform back navigation"
- [x] 1.4 Run `tool/record_readme.sh`; verify the scenario "Launch in the recording mode", that the script finishes, and that the video starts in Nice with the title card and shows the flyover as before

## 2. Style patch

- [x] 2.1 Write `lib/src/inspect/style_patch.dart` (D192) and tests in `test/inspect/style_patch_test.dart` with a fixture style that has a vector source with several source layers, a GeoJSON source, a raster source, background, fill, line and symbol layers, and relative `url`, `tiles`, `sprite` and `glyphs` values; verify that the tests pass and check: one fill, outline, line and circle layer per pair of source and source layer, appended after the style's layers; no highlight for raster and background layers; the geometry-type filters; opacity read from `feature-state`; relative URLs resolved against the style URL; the style's own layers unchanged
- [x] 2.2 Run the patch on the JSON of the four styles fetched from their URLs, in a test that is skipped without a network connection; verify that each result has highlight layers for every vector source layer the style draws from

## 3. Inspect screen

- [x] 3.1 Write `lib/src/inspect/inspect_screen.dart` with the map, the `LayerController`, the style fetch with a per-screen cache, the progress indicator until the first style arrives, the failure message, and the attribution (D192); verify on macOS that the screen shows Liberty, that each style can be chosen, and the scenario "Style can't be fetched" with the network turned off
- [x] 3.2 Add the tap query and the selection (D193), with one query per own style layer and the layer IDs from the style patch, with a test in `test/inspect/style_patch_test.dart` for those layer IDs (topmost first, no highlight, raster or background layers); verify that the test passes, and on macOS the scenarios "Tap a road", "Building in a park", "Merged buildings", "Choose another feature at the tap", "Feature state read back", "Feature state of a label", "Tap another feature", "Tap where no feature is drawn", "Highlight a polygon" and "Highlight a label", and record whether the features of each style have IDs (scenario "Feature without an ID")
- [x] 3.3 Write `lib/src/inspect/feature_panel.dart` (D194) and a widget test in `test/inspect/feature_panel_test.dart` for the style layer ID, the geometry type and number of parts, the state, the list of other hits and choosing one, the properties sorted by key, the "none" source layer, a non-string value, and the statement for a feature without an ID; verify that the test passes
- [x] 3.4 Verify on macOS the scenarios "Change style with a selection" and "Style per screen"

## 4. Platforms and documentation

- [x] 4.1 Run the demo on the iOS simulator and on the Android emulator; verify the scenario "Demo runs on each platform" for both showcase screens, and that a tap highlights a feature on each
- [x] 4.2 Update `packages/demo/README.md` with the gallery, the inspect screen, and the known limits (features without IDs, buildings merged into one feature, label hit areas while the camera moves), and the demo's line in the layout in `CONTRIBUTING.md`; verify by reading that every path the files name exists
- [x] 4.3 Run `flutter analyze` and `flutter test` in `packages/demo`; verify that both pass and that no Dart file of the demo imports a library under `package:flutter_mapigrade/src/` (scenario "Demo imports")
