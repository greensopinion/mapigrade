## MODIFIED Requirements

### Requirement: Map follows the flutter_map camera
The system SHALL set the map camera from the `flutter_map` camera whenever the `flutter_map` camera changes. The MapLibre zoom SHALL be the `flutter_map` zoom minus 1, the MapLibre bearing SHALL be the negated `flutter_map` rotation, and the map viewport SHALL be the size of the `flutter_map` viewport before rotation. Pitch SHALL be 0. In the camera prediction mode the system SHALL set the predicted camera instead (requirement "Camera prediction").

#### Scenario: Camera change
- **WHEN** the `flutter_map` camera changes through a gesture or a camera controller call
- **THEN** a later displayed map frame reports the converted camera

#### Scenario: Camera jump larger than the viewport
- **WHEN** the `flutter_map` camera moves in one step by more than the viewport
- **THEN** a later displayed map frame reports the new camera, and the map shows it

#### Scenario: Rotated map
- **WHEN** the `flutter_map` rotation is 30 degrees
- **THEN** the map is rotated by the same angle in the same direction as the overlays, and fills the viewport without empty corners when the camera is at rest

### Requirement: Camera prediction
The system SHALL provide a camera prediction mode for the layer, with a lead given as a number of display refresh intervals. The layer SHALL provide one alignment option with two values: camera prediction at a stated lead, or no alignment. Camera prediction with a lead of 1 SHALL be the layer's default. In the prediction mode the system SHALL set the map camera to the converted `flutter_map` camera extrapolated by the lead from the camera's velocity over the last Flutter frames, for center, zoom and bearing. When the `flutter_map` camera hasn't changed since the previous Flutter frame, the predicted camera SHALL equal the converted camera. With either value, the system SHALL draw the displayed map frame at the position of the layer, without moving, scaling or rotating it.

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

### Requirement: Alignment measurement
The system SHALL provide a measurement mode that records, for each Flutter frame during camera changes, the map frame that Flutter displayed and the `flutter_map` camera. From these it SHALL compute the alignment error in logical pixels: the largest distance at the viewport corners and center between where the displayed map frame, as the layer draws it, draws a coordinate and where the overlays draw it. The measurement mode SHALL run with the layer configured with camera prediction at a stated lead or with no alignment, and SHALL report the configuration. It SHALL include phases in which the pan stops abruptly, decelerates as a `flutter_map` fling does, and reverses direction, and for these SHALL report the overshoot: the largest alignment error from the moment the camera's motion changes (an abrupt stop, the start of a deceleration, or a reversal) until half a second after the camera is at rest or moves at constant speed again, and the overshoot ahead: over the same time, the largest distance at the viewport center by which the drawn map is ahead of the overlays in the direction of motion before the change, or 0 if it isn't ahead.

#### Scenario: Pan at a stated speed
- **WHEN** the alignment benchmark pans at a constant stated speed in logical pixels per second
- **THEN** the report states the speed, the layer configuration, and the p50, p95 and largest alignment error

#### Scenario: Pan that stops
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and stops abruptly, or decelerates to rest as a `flutter_map` fling does
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead of each stop, as p50 and largest over the stops in the phase

#### Scenario: Pan that reverses
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and reverses direction abruptly
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead after each reversal, as p50 and largest over the reversals in the phase

## REMOVED Requirements

### Requirement: Compensating transform
**Reason**: Camera prediction is the layer's default since the camera-prediction-default change, and on 2026-10-12 we decided to drop the transform. It is the only part of the layer that needs the camera of the frame Flutter displays, which Android's `SurfaceProducer` can't report exactly.
**Migration**: Use the default alignment (camera prediction, lead 1), or no alignment. Recorded transform results stay in `benchmarks.md`.
