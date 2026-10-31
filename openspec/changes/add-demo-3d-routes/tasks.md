## 1. Files and pins

- [x] 1.1 Move `lib/src/polylines/` to `lib/src/routes/`, rename `PolylineScreen` to `RoutesScreen` in `routes_screen.dart`, move the test to `test/routes/`, and delete `lib/src/three_d/` (D208); verify that `flutter analyze` and `flutter test` in `packages/demo` pass and that no file refers to `ThreeDScreen` or `src/polylines/`
- [x] 1.2 Build the pins from `demoRoutes` in `routes.dart` (D210), and extend `test/routes/routes_test.dart`; verify that the test passes and checks that there are two pins per route, at its first and last points, with opaque colors, and the gradient route's pins in its first and last gradient colors

## 2. Screen and gallery

- [ ] 2.1 Add the pitch, the slider and the `MarkerLayer` to `RoutesScreen`, and change the gallery entry and the panel title (D209, D210, D211); verify that `flutter analyze` and `flutter test` in `packages/demo` pass, and on macOS the scenarios "Launch" and "Open the 3D routes screen" with a screenshot
- [ ] 2.2 Add the orbit (D212); verify that `flutter analyze` and `flutter test` in `packages/demo` pass, and on macOS the scenarios "Play the orbit" with screenshots at four rotations a quarter turn apart, "Stop the orbit by touch" and "Pitch during the orbit"
- [ ] 2.3 Verify on macOS, with screenshots, the scenarios "Buildings hide the routes", "Routes on top", "Change the pitch", "Gestures on a pitched map", "Width in meters" and "Change style on the 3D routes screen", and the opening view in a window of an iPhone's size; if the routes don't fit the opening view, apply the design's first risk and check again
- [ ] 2.4 Run the demo on an iPhone and on the Android emulator, one background command per device; verify the scenarios "Open the 3D routes screen", "Play the orbit" and "Tilt gesture" with a two-finger vertical drag on both, and terminate the app on each device afterwards

## 3. Recording

- [x] 3.1 Move `recording.dart` to `lib/src/common/`, add the showcase variable, open the chosen screen in `main.dart`, and add the recording mode to `RoutesScreen` (D213); verify that `flutter analyze` and `flutter test` in `packages/demo` pass, a unit test for parsing the showcase variable, including an unknown value, and the scenarios "Launch the 3D routes recording" and "Ready and go for 3D routes" by starting the release build from a shell
- [x] 3.2 Add the showcase argument to `record_readme.sh` (D213); verify the scenarios "Make the 3D routes video" and "Title card for 3D routes" by running it and reading frames of the video at 0 s, 3.5 s, 10 s and 19 s, and "Make the video" by running it without the argument
- [x] 3.3 Update the recording sections of `packages/demo/README.md` and `CONTRIBUTING.md` for the showcase argument; verify by reading

## 4. Documentation and order

- [x] 4.1 Replace the Polylines line in `packages/demo/README.md` with one short sentence for 3D routes; verify by reading that it names the showcase as the gallery does
- [x] 4.2 Run `flutter analyze` and `flutter test` in `packages/demo`; verify that both pass and that no Dart file of the demo imports a library under `package:flutter_mapigrade/src/` (scenario "Demo imports")
- [ ] 4.3 Before archiving this change, check that `raise-flutter-map-pitch-limit` is archived; verify that `openspec/specs/demo-app/spec.md` has the requirement "3D view" with the slider to 85, so that this change's removal applies
