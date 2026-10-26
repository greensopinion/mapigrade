## 1. Pitch limit and far limit

- [x] 1.1 Raise `MapOptions.pitchLimit` to 85 and add `MapCamera`'s internal `groundViewport` and far limit (design decisions 1 and 2); verify unit tests that the far limit is in the viewport only above 70.82°, its position at 85° on a 393 × 851 viewport, and the scenarios "Maximum pitch above 60" and "Maximum pitch above 85"
- [x] 1.2 Use `groundViewport` for the footprint (`size`, `pixelOrigin`, `pixelBounds`, `visibleBounds`); verify unit tests that the camera at pitch 60 is unchanged and that the visible bounds at 85° contain the bottom corners and the ends of the far limit and are finite
- [x] 1.3 Change the conversions above the far limit (design decision 4); verify unit tests for the scenarios "Above the horizon", "Above the far limit", "Matches the camera model" at 85° and "Round trip"

## 2. Layers

- [x] 2.1 Clip `MobileLayerTransformer`'s child to the visible ground polygon (design decision 3); verify widget tests that nothing is drawn above the far limit at 85°, the scenario "Nothing drawn beyond the far limit", and that the existing pitched layer tests pass unchanged
- [x] 2.2 Use `groundViewport` in `TileCoverCalculator`; verify unit tests that the cover at 85° covers the viewport below the far limit and that covers at pitch 60 are unchanged, and a widget test for the scenario "Viewport below the far limit covered"
- [x] 2.3 Check the polygon and polyline culling and hit testing at 85°; verify widget tests that a polygon near the far limit is drawn and that a tap above the far limit hits nothing

## 3. Gestures, controller and fits

- [x] 3.1 Move pointers and focal points above the far limit onto it in `MapInteractiveViewer` (design decision 5); verify widget tests for the scenario "Drag above the far limit" and a scroll-wheel zoom with the cursor above the far limit, and that the existing gesture tests pass unchanged
- [x] 3.2 Make the map controller's offset methods treat positions above the far limit as without an offset; verify unit tests at 85°
- [x] 3.3 Use `groundViewport` in the pitched camera fits; verify unit tests for the scenario "Fit bounds at pitch 85" and fit coordinates and fit inside bounds at 85°

## 4. Fork documentation and checks

- [x] 4.1 Update the documentation of `MapOptions.maxPitch` and `pitchLimit` and the example's Pitch page (limit 85, the far limit, the background color above it); verify `dart doc` reports no new warnings
- [x] 4.2 Run `flutter analyze` and `flutter test` on the fork's branch; verify both pass
- [x] 4.3 Run the tile harness on the Pixel at pitch 70, 80 and 85, and the frame times at 60 and 85; record the results in design.md and terminate the harness afterwards

## 5. mapigrade

- [x] 5.1 Set MapLibre Native's maximum pitch to `fm.MapOptions.pitchLimit` with `mln_map_set_bounds` when `flutter_mapigrade` creates a map (design decision 6); verify a test that a map frame at pitch 85 reports pitch 85, for the scenario "Pitch above 60"
- [x] 5.2 Update the camera prediction and 3D view tests and documentation that state 60 degrees; verify the `flutter_mapigrade` and demo tests pass, including the scenario "Pitch change" with a maximum of 85
- [x] 5.3 Run the static alignment check at pitch 85 on the Mac; record the result in design.md
- [x] 5.4 Ask the user to check the demo's 3D view at 85° on the Mac and the iPhone, and the fork example's Pitch page on the iPhone, for the far limit, gaps and gesture behavior near it; record the result in design.md

## 6. Geometry behind the camera

- [x] 6.1 Change the far limit's pixel test of a polygon beyond the far limit so that the polygon is in front of the camera, and amend the far limit's commit; verify `flutter test` passes on current Flutter and on Flutter 3.27.0
- [x] 6.2 Clip polygon rings at the line of design decision 8 in the polygon painter; verify unit tests of the clip, a widget test that a polygon reaching behind the camera at pitch 85 is drawn below the far limit at the positions that the pitched projection gives, that it fails on Flutter 3.27.0 without the clip, and that the tests pass on current Flutter and on Flutter 3.27.0
- [x] 6.3 Run upstream CI's checks (format, analyze with fatal infos and warnings, tests, pana) on current Flutter and the tests on Flutter 3.27.0 for both commits

