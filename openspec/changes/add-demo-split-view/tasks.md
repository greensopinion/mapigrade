## 1. Split view

- [x] 1.1 Add a file in `packages/demo/lib/src/flyover/` with the right-half clip (D196) and the seam widget with its line and labels (D197), and a widget test in `packages/demo/test/flyover/` that checks, for two viewport sizes, that the clip starts at width / 2, that the line is centered on width / 2, that the labels are on either side of the line and above the attribution button's height, and that a drag starting on the line or a label reaches the map; verify that the test passes
- [ ] 1.2 Add the "Split view" switch to the flyover screen's settings, off at opening, and while it is on put the OSM `TileLayer` (D198) in the right-half clip first among the `MapigradeLayer` children and the seam widget between `MapigradeLayer` and the attribution (D195); verify that `flutter analyze` in `packages/demo` passes and, on macOS, the scenarios "Split view off at opening", "Open the flyover screen", "Turn on the split view", "Change style in the split view" and "Turn off the split view"

## 2. Verification on devices

- [ ] 2.1 On macOS, with the split view on, play the flyover and pan, zoom and rotate the map; capture frames during the movement and verify the scenario "Seam while the camera moves": the roads and the stage route continue across the seam within 1 logical pixel, and the overlays are drawn above both halves
- [ ] 2.2 Verify the scenarios "Seam while the camera moves" and "Gesture on the seam" on the iPhone and on the Pixel, with one run per device in parallel
- [ ] 2.3 With the split view on, set the pitch to 85 with the `MapController`, and verify on macOS that above the horizon the right half shows the style's sky continuing from the left half (design, "Risks / Trade-offs")
- [ ] 2.4 Run `tool/record_readme.sh`; verify that it finishes and that the video shows no seam

## 3. Documentation and checks

- [ ] 3.1 Add the split view to the flyover's entry in `packages/demo/README.md`: the two halves, the tile source, and that it is off by default; verify by reading that it agrees with the "Split view" requirement
- [ ] 3.2 Run `flutter analyze` and `flutter test` in `packages/demo`; verify that both pass and that no Dart file of the demo imports a library under `package:flutter_mapigrade/src/` (scenario "Demo imports")
