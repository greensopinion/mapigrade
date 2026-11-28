## MODIFIED Requirements

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing and pitch, and for a `MapigradeMap` every field of the `map-widget` requirement "Camera model"), the viewport size and the projection that each frame was rendered with. The projection SHALL be the matrix with which the frame drew the map, so that Dart converts coordinates to the frame's screen positions as the frame drew them. The report SHALL identify the frame, so that Dart can tell which camera a frame corresponds to. On macOS and iOS, the system SHALL send the report when Flutter takes the frame for display, and the report SHALL include the time at which Flutter took it, on the same clock as Flutter's frame timings, so that Dart can match the frame to the Flutter frame that displayed it. On Android, the system SHALL send the report when Dart chooses the frame for display (requirement "Display slots"), and the report SHALL have no display time. Each camera update from Dart SHALL carry a sequence number, and the report SHALL include the sequence number of the camera update that the frame was rendered with. The system SHALL also report each frame when it has finished rendering, before Flutter displays it, with the same camera, viewport size, identifier and sequence number, and with the display slot that holds it.

#### Scenario: Frame camera is reported
- **WHEN** a new frame becomes available for display
- **THEN** Dart receives the camera, viewport size and projection the frame was rendered with, an identifier of that frame, and the sequence number of the camera update it was rendered with

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

#### Scenario: Projection matches the frame
- **WHEN** a frame rendered with pitch 60 is reported, and Dart converts a coordinate with the reported projection
- **THEN** the position equals the position at which MapLibre's own projection of that frame places the coordinate, within 0.1 logical pixels
