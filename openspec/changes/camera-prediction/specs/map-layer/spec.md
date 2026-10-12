## ADDED Requirements

### Requirement: Camera prediction
The system SHALL provide an experimental camera prediction mode for the layer, off by default, with a lead given as a number of display refresh intervals. In this mode the system SHALL set the map camera to the converted `flutter_map` camera extrapolated by the lead from the camera's velocity over the last Flutter frames, for center, zoom and bearing, and SHALL draw the map without the compensating transform. When the `flutter_map` camera hasn't changed since the previous Flutter frame, the predicted camera SHALL equal the converted camera.

#### Scenario: Steady pan
- **WHEN** the prediction mode is on with a lead of n refresh intervals, and the `flutter_map` camera pans at a constant speed
- **THEN** the camera the map renders is ahead of the converted camera by n refresh intervals of that movement, in the direction of the pan

#### Scenario: Camera at rest
- **WHEN** the prediction mode is on and the `flutter_map` camera stops changing
- **THEN** a later displayed map frame reports the converted camera, and the map and the overlays meet the requirement "Alignment at rest"

#### Scenario: Antimeridian
- **WHEN** the prediction mode is on and the `flutter_map` camera pans across the antimeridian
- **THEN** the velocity uses the shorter longitude difference, and the predicted camera does not jump by a world width

## MODIFIED Requirements

### Requirement: Map follows the flutter_map camera
The system SHALL set the map camera from the `flutter_map` camera whenever the `flutter_map` camera changes. The MapLibre zoom SHALL be the `flutter_map` zoom minus 1, the MapLibre bearing SHALL be the negated `flutter_map` rotation, and the map viewport SHALL be the size of the `flutter_map` viewport before rotation. Pitch SHALL be 0. In the camera prediction mode the system SHALL set the predicted camera instead (requirement "Camera prediction").

#### Scenario: Camera change
- **WHEN** the `flutter_map` camera changes through a gesture or a camera controller call
- **THEN** a later displayed map frame reports the converted camera

#### Scenario: Rotated map
- **WHEN** the `flutter_map` rotation is 30 degrees
- **THEN** the map is rotated by the same angle in the same direction as the overlays, and fills the viewport without empty corners when the camera is at rest

### Requirement: Compensating transform
Unless the layer is configured without the compensating transform, while the camera of the displayed map frame differs from the current `flutter_map` camera, the system SHALL draw the map with a transform that moves, scales and rotates the frame so that each coordinate in the frame appears where the current `flutter_map` camera places it. The transform SHALL use the camera of the last displayed frame that Dart has been notified of. If the transform would move the frame entirely outside the viewport, the system SHALL draw the frame without the transform, so that Flutter draws the texture and takes the next map frame. The layer SHALL provide an option to draw the map without the compensating transform; the transform SHALL be on by default.

#### Scenario: Camera ahead of the displayed frame
- **WHEN** the `flutter_map` camera has moved by a known offset since the last displayed frame that Dart has been notified of, and the raster thread displays that frame
- **THEN** the frame is drawn shifted by that offset, and a coordinate in the frame appears at the position the current camera places it

#### Scenario: Camera jump larger than the viewport
- **WHEN** the `flutter_map` camera moves in one step by more than the viewport, so that the transform would move the displayed frame entirely outside the viewport
- **THEN** the frame is drawn without the transform, and a later displayed map frame reports the new camera

#### Scenario: Antimeridian
- **WHEN** the `flutter_map` camera pans across the antimeridian
- **THEN** the transform uses the shorter longitude difference, and the map does not jump by a world width

#### Scenario: Transform turned off
- **WHEN** the layer is configured without the compensating transform and the `flutter_map` camera moves
- **THEN** the displayed map frame is drawn where the layer is, without a transform, and no strips are uncovered at the viewport edges

### Requirement: Alignment measurement
The system SHALL provide a measurement mode that records, for each Flutter frame during camera changes, the map frame whose camera the transform used, the map frame that Flutter displayed, and the `flutter_map` camera. From these it SHALL compute the alignment error in logical pixels, the largest distance at the viewport corners and center between where the displayed map frame draws a coordinate and where the overlays draw it, both with the transform and without it. The measurement mode SHALL run with the layer configured as the default, without the transform, or with camera prediction at a stated lead, and SHALL report the configuration. It SHALL include phases in which the pan stops abruptly, decelerates as a `flutter_map` fling does, and reverses direction, and for these SHALL report the overshoot: the largest alignment error of the drawn map from the moment the camera's motion changes (an abrupt stop, the start of a deceleration, or a reversal) until half a second after the camera is at rest or moves at constant speed again, and the overshoot ahead: over the same time, the largest distance at the viewport center by which the drawn map is ahead of the overlays in the direction of motion before the change, or 0 if it isn't ahead.

#### Scenario: Pan at a stated speed
- **WHEN** the alignment benchmark pans at a constant stated speed in logical pixels per second
- **THEN** the report states the speed, the fraction of Flutter frames whose displayed map frame differs from the frame the transform used, and the p50, p95 and largest alignment error with and without the transform

#### Scenario: Pan that stops
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and stops abruptly, or decelerates to rest as a `flutter_map` fling does
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead of each stop, as p50 and largest over the stops in the phase

#### Scenario: Pan that reverses
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and reverses direction abruptly
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead after each reversal, as p50 and largest over the reversals in the phase
