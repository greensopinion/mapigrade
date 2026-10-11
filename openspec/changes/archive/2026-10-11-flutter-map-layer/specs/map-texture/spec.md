## MODIFIED Requirements

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing) and viewport size that each displayed frame was rendered with. The report SHALL identify the frame, so that Dart can tell which camera the currently displayed frame corresponds to. The report SHALL also include the time at which Flutter took the frame for display, on the same clock as Flutter's frame timings, so that Dart can match the frame to the Flutter frame that displayed it.

#### Scenario: Frame camera is reported
- **WHEN** a new frame becomes available for display
- **THEN** Dart receives the camera and viewport size the frame was rendered with, and an identifier of that frame

#### Scenario: Display time matches a Flutter frame
- **WHEN** Flutter takes a frame for display while it rasterizes a Flutter frame
- **THEN** the reported display time lies between the start and the end of that Flutter frame's rasterization, as reported by Flutter's frame timings
