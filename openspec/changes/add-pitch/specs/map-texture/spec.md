## MODIFIED Requirements

### Requirement: Camera control
The system SHALL set the map camera from Dart, using center latitude and longitude, zoom, bearing, and pitch. When Dart sends camera updates faster than the map renders, the system SHALL render the most recent camera; it is not required to render intermediate cameras. A camera update SHALL NOT block the Dart caller until a frame renders.

#### Scenario: Camera change is displayed
- **WHEN** a Dart caller sets the camera to a known center, zoom, bearing and pitch
- **THEN** a later displayed frame shows the map at that camera

#### Scenario: Rapid camera updates
- **WHEN** a Dart caller sends camera updates on every Flutter frame for several seconds
- **THEN** each displayed frame shows the most recent camera received before that frame was rendered, and the system does not build up a backlog of earlier cameras

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing, pitch) and viewport size that each frame was rendered with. The report SHALL identify the frame, so that Dart can tell which camera a frame corresponds to. On macOS and iOS, the system SHALL send the report when Flutter takes the frame for display, and the report SHALL include the time at which Flutter took it, on the same clock as Flutter's frame timings, so that Dart can match the frame to the Flutter frame that displayed it. On Android, the system SHALL send the report when Dart chooses the frame for display (requirement "Display slots"), and the report SHALL have no display time. Each camera update from Dart SHALL carry a sequence number, and the report SHALL include the sequence number of the camera update that the frame was rendered with. The system SHALL also report each frame when it has finished rendering, before Flutter displays it, with the same camera, viewport size, identifier and sequence number, and with the display slot that holds it.

#### Scenario: Frame camera is reported
- **WHEN** a new frame becomes available for display
- **THEN** Dart receives the camera and viewport size the frame was rendered with, an identifier of that frame, and the sequence number of the camera update it was rendered with

#### Scenario: Display time matches a Flutter frame
- **WHEN** on macOS or iOS, Flutter takes a frame for display while it rasterizes a Flutter frame
- **THEN** the reported display time lies between the start and the end of that Flutter frame's rasterization, as reported by Flutter's frame timings

#### Scenario: No display time on Android
- **WHEN** on Android, Dart chooses a finished frame for display
- **THEN** Dart receives the frame's camera, viewport size and identifier, and the report has no display time

#### Scenario: Finished frame is reported
- **WHEN** a frame finishes rendering
- **THEN** Dart receives the frame's slot, identifier, camera, viewport size and camera sequence number before any Flutter frame displays it

#### Scenario: Camera updates faster than the map renders
- **WHEN** Dart sends camera updates with sequence numbers 1, 2 and 3 before the map renders a frame
- **THEN** the next rendered frame reports sequence number 3
