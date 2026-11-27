## MODIFIED Requirements

### Requirement: Gallery
The demo SHALL open at a gallery that lists its showcases in this order: "Flyover", "Inspect features", "Polylines" and "Pitch and markers". Each entry SHALL show the showcase's title and a sentence that states what the developer can try on its screen. Choosing an entry SHALL open the showcase's screen. Each showcase screen SHALL have its own map, which the screen creates when it opens and disposes when it closes. Each showcase screen SHALL have a control that goes back to the gallery, and the platform's back navigation SHALL also go back to the gallery. The gallery SHALL list only showcases of features that a user of an application sees or does; it SHALL NOT list settings such as HTTP headers, the layer's alignment or the tile cache size.

#### Scenario: Launch
- **WHEN** the demo starts without the recording mode
- **THEN** it shows the gallery with "Flyover", then "Inspect features", then "Polylines", then "Pitch and markers", each with a sentence that states what to try, and no map

#### Scenario: Open and close a showcase
- **WHEN** the developer chooses "Inspect features", and then uses the screen's control to go back
- **THEN** the inspect screen shows its map, and after going back the gallery is shown and the inspect screen's map is disposed

#### Scenario: Platform back navigation
- **WHEN** the developer uses the Android back gesture on the flyover screen
- **THEN** the demo shows the gallery

## ADDED Requirements

### Requirement: Pitch and markers
The "Pitch and markers" screen SHALL display a `MapigradeMap`, without `flutter_map`, with every gesture of the `map-gestures` capability on. When the screen opens, the map SHALL show a mountain area in Liberty at pitch 50. The screen SHALL draw upright pins at points of interest and wind arrows that lie on the ground and point in the wind's direction, with `MapigradeMarkers`. A control SHALL turn perspective scaling of the pins on and off. A tap on the map SHALL show the tap's coordinate and the name of the topmost feature at the tap, and a long press SHALL drop a pin at its coordinate. Buttons SHALL fly the camera to a flat view and back to a pitched one. The screen SHALL show the camera's center, zoom, bearing and pitch, updated from the camera stream, and SHALL offer the styles of the requirement "Styles".

#### Scenario: Open the screen
- **WHEN** the developer chooses "Pitch and markers" in the gallery
- **THEN** the map is pitched, the pins stand upright, and the wind arrows lie on the ground

#### Scenario: Tilt and turn
- **WHEN** the developer tilts and turns the map with two fingers
- **THEN** the pins stay upright at their coordinates, the arrows turn with the map, and the camera readout follows

#### Scenario: Tap and long press
- **WHEN** the developer taps a road and then long-presses another place
- **THEN** the screen shows the road's coordinate and name, and a pin appears at the long-pressed place
