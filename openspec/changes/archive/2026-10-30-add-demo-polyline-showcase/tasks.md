## 1. Routes

- [x] 1.1 Write `lib/src/polylines/routes.dart` with the four routes and their drawing properties (D205), and `test/polylines/routes_test.dart`; verify that the test passes and checks that every route has at least two points inside downtown New York, that the list is created once, and the order of the routes
- [x] 1.2 Draw the routes on macOS over Liberty and take a screenshot at zoom 17 along each route; verify that every route follows the streets or the water it names

## 2. Screen and gallery

- [x] 2.1 Write `lib/src/polylines/polyline_screen.dart` (D204, D206) and add the gallery entry (D207); verify that `flutter analyze` and `flutter test` in `packages/demo` pass, and on macOS the scenarios "Launch" and "Open the polyline screen"
- [x] 2.2 Verify on macOS the scenarios "Buildings hide the routes", "Routes on top", "Width in meters" and "Change style on the polyline screen", with screenshots; if buildings hide too little of the routes, apply the change of the design's first risk and check again
- [x] 2.3 Run the demo on the iOS simulator and on the Android emulator; verify the scenario "Open the polyline screen" and that the placement control works on both

## 3. Documentation

- [x] 3.1 Add one sentence for the polyline showcase to `packages/demo/README.md`; verify by reading that it names the screen as the gallery does
- [x] 3.2 Run `flutter analyze` and `flutter test` in `packages/demo`; verify that both pass and that no Dart file of the demo imports a library under `package:flutter_mapigrade/src/` (scenario "Demo imports")
