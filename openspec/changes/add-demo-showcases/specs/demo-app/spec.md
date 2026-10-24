## ADDED Requirements

### Requirement: Gallery
The demo SHALL open at a gallery that lists its showcases in this order: "Flyover" and "Inspect features". Each entry SHALL show the showcase's title and a sentence that states what the developer can try on its screen. Choosing an entry SHALL open the showcase's screen. Each showcase screen SHALL have its own map, which the screen creates when it opens and disposes when it closes. Each showcase screen SHALL have a control that goes back to the gallery, and the platform's back navigation SHALL also go back to the gallery. The gallery SHALL list only showcases of features that a user of an application sees or does; it SHALL NOT list settings such as HTTP headers, the layer's alignment or the tile cache size.

#### Scenario: Launch
- **WHEN** the demo starts without the recording mode
- **THEN** it shows the gallery with "Flyover" and then "Inspect features", each with a sentence that states what to try, and no map

#### Scenario: Open and close a showcase
- **WHEN** the developer chooses "Inspect features", and then uses the screen's control to go back
- **THEN** the inspect screen shows its map, and after going back the gallery is shown and the inspect screen's map is disposed

#### Scenario: Platform back navigation
- **WHEN** the developer uses the Android back gesture on the flyover screen
- **THEN** the demo shows the gallery

### Requirement: Flyover screen
The flyover screen SHALL be the screen that the requirements "Styles", "Metrics display", "Stage overlays", "Stage data", "Flyover", "Camera readout" and "Attribution" describe. When the flyover screen opens, its camera SHALL be over Nice at the start of stage 9, the flyover SHALL be stopped, and its settings SHALL be the settings at launch that those requirements state. Going back to the gallery SHALL stop the flyover.

#### Scenario: Open the flyover screen
- **WHEN** the developer chooses "Flyover" in the gallery
- **THEN** the map shows Nice in Liberty with the stage overlays, the camera readout and the metrics, and the flyover isn't playing

#### Scenario: Go back during the flyover
- **WHEN** the developer goes back to the gallery while the flyover plays, and then chooses "Flyover" again
- **THEN** the flyover stops when the gallery is shown, and the screen opens again over Nice with the flyover stopped

### Requirement: Inspect features
The inspect screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming and rotating enabled. A tap on the map SHALL query the features that the style's own layers draw at the tap, with `LayerController`'s query at a point and its default radius, and SHALL select a feature of the topmost style layer that draws a feature at the tap; the highlight layers of the requirement "Inspect highlight" SHALL NOT be queried. Among the features of that layer, the demo SHALL select the first that the query returns. The selection SHALL NOT depend on the order in which MapLibre returns the features of several layers, because MapLibre Native doesn't return them in style order (`docs/maplibre-query-result-order.md`). The screen SHALL show a panel that states the ID of the style layer that draws the selected feature, and the feature's source ID, source-layer ID, ID, geometry type, number of parts for a multi geometry, its feature state, and properties, with the properties as key and value rows sorted by key. After it sets the feature state of a newly selected feature, the demo SHALL query the selected feature's style layer again at the tap and show the feature state that this query returns, so that the panel shows `selected: true` without a second tap. For a feature of a symbol layer, the panel SHALL state that MapLibre Native doesn't return feature state for labels and icons (`docs/maplibre-symbol-query-feature-state.md`) in place of the state. Below the selected feature, the panel SHALL list the other features at the tap, topmost style layer first, each with its style layer ID, source-layer ID and ID. Choosing an entry of the list SHALL select that feature as a tap selects one, and the list SHALL then contain the other features of the same tap, including the feature that was selected before. The demo SHALL deselect the feature that was selected before by setting its feature state `selected: false`, not by removing the state, because MapLibre Native drops one of the changes when a removal and a change in one source layer arrive before the same render (`docs/maplibre-feature-state-coalescing.md`). When the newly selected feature has an ID, the demo SHALL then set the feature state `selected: true` on it. When it has no ID, the panel SHALL state that the feature has no ID and so can't be highlighted. A tap where the query returns no feature SHALL deselect the feature that was selected before and clear the panel. A query that fails SHALL show the failure's message and keep the selection. The screen SHALL state that a tap selects the topmost feature.

#### Scenario: Tap a road
- **WHEN** the developer taps a road in Liberty
- **THEN** the road is highlighted, and the panel states the ID of the style layer that draws the road, source `openmaptiles`, source layer `transportation`, the road's ID, and its properties, such as `class`, sorted by key

#### Scenario: Building in a park
- **WHEN** the developer taps a building in Liberty that lies inside a park
- **THEN** the building is selected and highlighted, not the park, because Liberty draws buildings above parks

#### Scenario: Merged buildings
- **WHEN** the developer taps a building in Liberty that the tiles merge with other buildings of the same height into one multi-polygon feature
- **THEN** the panel states geometry type MultiPolygon and the number of polygons, and every polygon of that feature is highlighted

#### Scenario: Choose another feature at the tap
- **WHEN** a building inside a park is selected and the developer chooses the park in the list of the other features at the tap
- **THEN** the park is highlighted and the building isn't, the panel states the park, and the list contains the building

#### Scenario: Feature state read back
- **WHEN** the developer taps a building in Liberty
- **THEN** the building is highlighted and the panel states the feature state `selected: true`, without a second tap

#### Scenario: Feature state of a label
- **WHEN** the developer taps a POI label in Liberty
- **THEN** a circle is highlighted at the label's point, and the panel states that MapLibre Native doesn't return feature state for labels and icons

#### Scenario: Select features of one source layer in turn
- **WHEN** a building is selected and the developer chooses another building of the same tap in the list, and then the first building again
- **THEN** after each choice exactly the chosen building is highlighted

#### Scenario: Tap another feature
- **WHEN** a road is selected and the developer taps a building
- **THEN** the building is highlighted, the road isn't, and the panel states the building's style layer, source, source layer, ID and properties

#### Scenario: Tap where no feature is drawn
- **WHEN** a feature is selected and the developer taps where the query returns no feature
- **THEN** no feature is highlighted and the panel shows no feature

#### Scenario: Feature without an ID
- **WHEN** the topmost feature at the tap has no ID
- **THEN** the panel states its style layer, source, source layer and properties, and that it has no ID and so can't be highlighted, and no feature is highlighted

### Requirement: Inspect highlight
The inspect screen SHALL offer the styles of the requirement "Styles", with Liberty at the screen's opening. For each style, the demo SHALL fetch the style's JSON from its URL, add highlight layers to it, and give the result to the layer. The highlight layers SHALL be drawn above the style's own layers, and SHALL draw, in one color, every feature whose feature state has `selected: true` in every source layer that the style's layers draw: a fill and its outline for a polygon, a line wider than the style's lines for a line, and a circle for a point, including the point of a label or icon. The highlight layers SHALL draw nothing for a feature without that state. Choosing another style SHALL keep the camera, the selection and the panel, and the new style SHALL highlight the selected feature when it has a feature with the same source ID, source-layer ID and ID. When the style's JSON can't be fetched or isn't a style, the demo SHALL show the failure's message and continue to run.

#### Scenario: Highlight a polygon
- **WHEN** the developer taps a building in Liberty
- **THEN** the building is filled and outlined in the highlight color, above the style's layers

#### Scenario: Highlight a label
- **WHEN** the topmost feature at the tap is a place label
- **THEN** a circle in the highlight color is drawn at the label's point

#### Scenario: Change style with a selection
- **WHEN** a road is selected in Liberty and the developer chooses Positron
- **THEN** the map shows Positron with the camera where it was, the panel still states the road, and the road is highlighted in Positron

#### Scenario: Style can't be fetched
- **WHEN** the device has no network connection and the developer opens the inspect screen
- **THEN** the demo shows the failure's message and continues to run

## MODIFIED Requirements

### Requirement: Demo app
The repository SHALL contain a demo app in `packages/demo/` that is a member of the pub workspace and is not published. The demo SHALL run on Android, iOS and macOS, on the versions and architectures the package supports. Its Dart code SHALL import only the main library of the package, `package:flutter_mapigrade/flutter_mapigrade.dart`, and no library under `package:flutter_mapigrade/src/`. Each showcase screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming and rotating enabled.

#### Scenario: Demo imports
- **WHEN** the demo's Dart files are inspected
- **THEN** they import `package:flutter_mapigrade/flutter_mapigrade.dart` and no other library of the package

#### Scenario: Demo runs on each platform
- **WHEN** the demo is built and run on macOS, on the iOS simulator and on the Android emulator, and each showcase is opened from the gallery
- **THEN** on each platform and on each showcase screen the map appears, and dragging, pinching and rotating with two fingers (or the equivalent mouse and trackpad input on macOS) move, zoom and rotate the map

#### Scenario: Device without the native library
- **WHEN** the demo runs where `MapigradeLayer.isSupported` is false
- **THEN** the demo states that the map isn't supported on this device instead of the gallery, and continues to run

#### Scenario: Map failure
- **WHEN** the layer reports a failure on a showcase screen, for example because a style can't be loaded
- **THEN** the demo shows the failure's message and continues to run

### Requirement: Styles
Each showcase screen that offers a style SHALL let the developer choose one of these styles, none of which needs an API key: OpenFreeMap Liberty (`https://tiles.openfreemap.org/styles/liberty`), OpenFreeMap Bright (`https://tiles.openfreemap.org/styles/bright`), OpenFreeMap Positron (`https://tiles.openfreemap.org/styles/positron`) and MapLibre demo tiles (`https://demotiles.maplibre.org/style.json`). Liberty SHALL be the style each time a screen opens. The style that the developer chooses on one screen SHALL NOT change the style of another screen. On the flyover screen, choosing a style SHALL keep the camera, the overlays and the metrics.

#### Scenario: Change style
- **WHEN** the developer chooses Positron on the flyover screen while the camera is over Nice
- **THEN** the map shows Positron, the camera stays over Nice, and the overlays and the metrics display continue

#### Scenario: Style per screen
- **WHEN** the developer chooses Positron on the flyover screen, goes back to the gallery and opens the inspect screen
- **THEN** the inspect screen shows Liberty

### Requirement: Attribution
Each showcase screen SHALL show on the map the attribution that the chosen style requires, and an OpenStreetMap attribution with a link to its copyright page. For the OpenFreeMap styles the attribution SHALL name OpenFreeMap, OpenMapTiles and OpenStreetMap.

#### Scenario: OpenFreeMap style
- **WHEN** the style is Liberty on either showcase screen
- **THEN** the map shows an attribution that names OpenFreeMap, OpenMapTiles and OpenStreetMap, and opening the OpenStreetMap entry leads to its copyright page

### Requirement: Recording mode
The demo SHALL have a recording mode on macOS, which the environment variable `MAPIGRADE_DEMO_RECORDING_SECONDS=<L>` turns on when the demo starts, where L is the clip length in whole seconds and is greater than 0. Without the variable, the demo SHALL behave as the other requirements state. On iOS and Android the demo SHALL ignore the variable. When the variable is set to a value that isn't a whole number greater than 0, the demo SHALL write the reason to standard error and exit with a non-zero status.

In the recording mode the demo SHALL:

- show the flyover screen at launch, without the gallery and without the control that goes back to the gallery;
- show its window without a title bar and with square corners, with a content size of 1280 × 720 points, at launch;
- show the panel with the settings section collapsed, and keep the flyover status, the camera readout, the metrics and the statement that the routes are approximate;
- when the style has loaded and the stages have loaded, play a warm-up pass that covers the flyover from its start to L + 1 s, with the panel stating that it is warming up;
- after the warm-up pass, move the camera to the flyover's camera at time 0 and hold it there until the map is at rest, meaning that it renders no frame for 1 s;
- then write the line `ready` to standard output, and start the run, the flyover from time 0, when it reads the line `go` on standard input.

The run SHALL be the flyover that the other requirements describe, with the same camera at the same time for the same viewport size. The demo SHALL exit with a non-zero status and write the reason to standard error when the map isn't at rest within 30 s after the warm-up pass, when `go` doesn't arrive within 30 s after `ready`, or when the layer reports a failure.

#### Scenario: Launch in the recording mode
- **WHEN** the macOS demo is started with `MAPIGRADE_DEMO_RECORDING_SECONDS=30`
- **THEN** it shows the flyover screen without the gallery and without the control that goes back, its window's content area is 1280 × 720 points, the settings section is collapsed, and the warm-up pass starts once the style and stages have loaded, without input

#### Scenario: Warm-up length
- **WHEN** the recording mode runs with L = 30
- **THEN** the warm-up pass plays the flyover from 0 s to 31 s and then moves the camera back to the start of stage 9 in Nice

#### Scenario: Ready and go
- **WHEN** the map is at rest at the start after the warm-up pass
- **THEN** the demo writes `ready` to standard output and doesn't move the camera until it reads `go` on standard input, and then it plays the flyover from time 0

#### Scenario: Go doesn't arrive
- **WHEN** 30 s pass after `ready` without `go` on standard input
- **THEN** the demo writes the reason to standard error and exits with a non-zero status

#### Scenario: Normal launch
- **WHEN** the demo is started without the variable
- **THEN** the demo shows the gallery, the flyover screen behaves as before when it is opened, and the demo neither writes `ready` nor reads standard input
