## MODIFIED Requirements

### Requirement: Map follows the flutter_map camera
The system SHALL set the map camera from the `flutter_map` camera whenever the `flutter_map` camera changes. The MapLibre zoom SHALL be the `flutter_map` zoom minus 1, the MapLibre bearing SHALL be the negated `flutter_map` rotation, the MapLibre pitch SHALL be the `flutter_map` pitch, and the map viewport SHALL be the size of the `flutter_map` viewport before rotation. In the camera prediction mode the system SHALL set the predicted camera instead (requirement "Camera prediction").

#### Scenario: Camera change
- **WHEN** the `flutter_map` camera changes through a gesture or a camera controller call
- **THEN** a later displayed map frame reports the converted camera

#### Scenario: Camera jump larger than the viewport
- **WHEN** the `flutter_map` camera moves in one step by more than the viewport
- **THEN** a later displayed map frame reports the new camera, and the map shows it

#### Scenario: Rotated map
- **WHEN** the `flutter_map` rotation is 30 degrees
- **THEN** the map is rotated by the same angle in the same direction as the overlays, and fills the viewport without empty corners when the camera is at rest

#### Scenario: Pitched map
- **WHEN** the `flutter_map` pitch is 45 degrees
- **THEN** a later displayed map frame reports pitch 45, and the map is tilted by the same angle in the same direction as the overlays

### Requirement: Camera prediction
The system SHALL provide a camera prediction mode for the layer, with a lead given as a number of display refresh intervals. The layer SHALL provide one alignment option with two values: camera prediction at a stated lead, or no alignment. Camera prediction with a lead of 1 SHALL be the layer's default. In the prediction mode the system SHALL set the map camera to the converted `flutter_map` camera extrapolated by the lead from the camera's velocity over the last Flutter frames, for center, zoom, bearing and pitch. The predicted pitch SHALL be limited to the range from 0 to 60 degrees. When the `flutter_map` camera hasn't changed since the previous Flutter frame, the predicted camera SHALL equal the converted camera. With either value, the system SHALL draw the displayed map frame at the position of the layer, without moving, scaling or rotating it.

#### Scenario: Default layer
- **WHEN** an application places the layer without configuring its alignment, and the `flutter_map` camera pans at a constant speed
- **THEN** the camera the map renders is ahead of the converted camera by 1 refresh interval of that movement, and the displayed map frame is drawn at the position of the layer

#### Scenario: Steady pan
- **WHEN** the prediction mode is on with a lead of n refresh intervals, and the `flutter_map` camera pans at a constant speed
- **THEN** the camera the map renders is ahead of the converted camera by n refresh intervals of that movement, in the direction of the pan

#### Scenario: Camera at rest
- **WHEN** the prediction mode is on and the `flutter_map` camera stops changing
- **THEN** a later displayed map frame reports the converted camera, and the map and the overlays meet the requirement "Alignment at rest"

#### Scenario: Antimeridian
- **WHEN** the prediction mode is on and the `flutter_map` camera pans across the antimeridian
- **THEN** the velocity uses the shorter longitude difference, and the predicted camera does not jump by a world width

#### Scenario: No alignment
- **WHEN** the layer is configured with no alignment, and the `flutter_map` camera moves
- **THEN** the map camera is the converted camera, the displayed map frame is drawn at the position of the layer, and no strips are uncovered at the viewport edges

#### Scenario: Pitch change
- **WHEN** the prediction mode is on with a lead of n refresh intervals, and the `flutter_map` pitch changes at a constant rate
- **THEN** the pitch the map renders is ahead of the converted pitch by n refresh intervals of that change, and is never above 60 degrees

### Requirement: Alignment at rest
When the camera is at rest and the map has displayed a frame for it, a geographic coordinate SHALL appear at the same screen position in the map and in `flutter_map` overlays, within 1 logical pixel.

#### Scenario: Marker at a known coordinate
- **WHEN** the style draws a marker at a coordinate, a `flutter_map` marker is placed at the same coordinate, and the camera is at rest
- **THEN** the centers of the two markers on screen are at most 1 logical pixel apart

#### Scenario: Zoom, rotation, latitude and longitude
- **WHEN** the static alignment check runs at fractional and integer zoom levels, with rotation, at latitudes up to 80 degrees, and with the camera within 1 degree of the antimeridian
- **THEN** each case meets the 1 logical pixel limit

#### Scenario: After resize
- **WHEN** the `flutter_map` viewport is resized and the camera is then at rest
- **THEN** the markers meet the 1 logical pixel limit at the new size

#### Scenario: Pitched map
- **WHEN** the static alignment check runs at pitch 30 and 60, with rotation 0 and 30, with a `flutter_map` marker, which faces the viewer, at the coordinate where the style draws a marker
- **THEN** each case meets the 1 logical pixel limit

### Requirement: Children aligned with the displayed map frame
The layer SHALL draw its children at the `flutter_map` camera that the displayed map frame was rendered for, including when the system refuses the layer's choice of a frame (requirement "Display slots" of `map-texture`): the camera from which the layer converted, or with camera prediction predicted, the map camera of that frame. In each Flutter frame, during camera changes and at rest, a geographic coordinate SHALL appear at the same screen position in the map and in the children, within 1 logical pixel. Until the map has displayed a frame, the layer SHALL draw its children at the live `flutter_map` camera. The children SHALL get the same `flutter_map` map controller and map options as the layers placed after the layer. The children SHALL receive pointer input, and a child that hit-tests its content SHALL hit-test it at the position where it draws it. The layer SHALL NOT change the camera that the layers placed after it, and `flutter_map`'s gesture handling, use.

#### Scenario: Pan with children
- **WHEN** a polyline layer is a child of the layer, and the `flutter_map` camera pans at 1,000 logical px/s
- **THEN** in each Flutter frame the polyline and the same line drawn by the style are at most 1 logical pixel apart

#### Scenario: Fling, stop and reversal with children
- **WHEN** a marker layer is a child of the layer, and the `flutter_map` camera decelerates as a fling does, stops abruptly, or reverses
- **THEN** in each Flutter frame the markers and the map meet the 1 logical pixel limit

#### Scenario: Children with camera prediction
- **WHEN** the layer has camera prediction on with a lead of 1, and its children include a marker layer
- **THEN** the markers are drawn at the predicted camera of the displayed map frame, and meet the 1 logical pixel limit

#### Scenario: Tap on a child
- **WHEN** during a pan the user taps a polyline that is a child of the layer, at a point where the screen shows it
- **THEN** the polyline layer's hit test reports the polyline

#### Scenario: Siblings keep the live camera
- **WHEN** a marker layer is a child of the layer and a scale bar is placed after the layer
- **THEN** the scale bar is drawn at the live `flutter_map` camera

#### Scenario: Before the first displayed frame
- **WHEN** the layer has children and its map hasn't displayed a frame yet
- **THEN** the children are drawn at the live `flutter_map` camera

#### Scenario: Android
- **WHEN** on the reference Android device the layer has a route and markers as children, and a tester pans and flings the map by hand
- **THEN** the route and the markers stay on the map in every Flutter frame, as the tester judges by eye

#### Scenario: Pan with children on a pitched map
- **WHEN** the `flutter_map` pitch is 45 degrees, a polyline layer is a child of the layer, and the `flutter_map` camera pans at 1,000 logical px/s
- **THEN** in each Flutter frame the polyline and the same line drawn by the style are at most 1 logical pixel apart
