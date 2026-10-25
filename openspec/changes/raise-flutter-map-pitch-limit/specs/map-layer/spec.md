## MODIFIED Requirements

### Requirement: Map follows the flutter_map camera
The system SHALL set the map camera from the `flutter_map` camera whenever the `flutter_map` camera changes. The MapLibre zoom SHALL be the `flutter_map` zoom minus 1, the MapLibre bearing SHALL be the negated `flutter_map` rotation, the MapLibre pitch SHALL be the `flutter_map` pitch, the MapLibre map's maximum pitch SHALL be the `flutter_map` pitch limit (85 degrees), and the map viewport SHALL be the size of the `flutter_map` viewport before rotation. In the camera prediction mode the system SHALL set the predicted camera instead (requirement "Camera prediction").

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

#### Scenario: Pitch above 60
- **WHEN** the `flutter_map` pitch is 85 degrees
- **THEN** a later displayed map frame reports pitch 85, and the map is tilted by the same angle in the same direction as the overlays

### Requirement: Camera prediction
The system SHALL provide a camera prediction mode for the layer, with a lead given as a number of display refresh intervals. The layer SHALL provide one alignment option with two values: camera prediction at a stated lead, or no alignment. Camera prediction with a lead of 1 SHALL be the layer's default. In the prediction mode the system SHALL set the map camera to the converted `flutter_map` camera extrapolated by the lead from the camera's velocity over the last Flutter frames, for center, zoom, bearing and pitch. The predicted pitch SHALL be limited to the range from 0 to the `flutter_map` pitch limit, 85 degrees. When the `flutter_map` camera hasn't changed since the previous Flutter frame, the predicted camera SHALL equal the converted camera. With either value, the system SHALL draw the displayed map frame at the position of the layer, without moving, scaling or rotating it.

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
- **THEN** the pitch the map renders is ahead of the converted pitch by n refresh intervals of that change, and is never above 85 degrees
