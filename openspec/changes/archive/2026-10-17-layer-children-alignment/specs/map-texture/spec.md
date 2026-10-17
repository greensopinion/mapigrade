## MODIFIED Requirements

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing) and viewport size that each frame was rendered with. The report SHALL identify the frame, so that Dart can tell which camera a frame corresponds to. On macOS and iOS, the system SHALL send the report when Flutter takes the frame for display, and the report SHALL include the time at which Flutter took it, on the same clock as Flutter's frame timings, so that Dart can match the frame to the Flutter frame that displayed it. On Android, the system SHALL send the report when the frame has been queued for display, and the report SHALL have no display time. Each camera update from Dart SHALL carry a sequence number, and the report SHALL include the sequence number of the camera update that the frame was rendered with. On macOS and iOS the system SHALL also report each frame when it has finished rendering, before Flutter displays it, with the same camera, viewport size, identifier and sequence number, and with the display slot that holds it (requirement "Display slots").

#### Scenario: Frame camera is reported
- **WHEN** a new frame becomes available for display
- **THEN** Dart receives the camera and viewport size the frame was rendered with, an identifier of that frame, and the sequence number of the camera update it was rendered with

#### Scenario: Display time matches a Flutter frame
- **WHEN** on macOS or iOS, Flutter takes a frame for display while it rasterizes a Flutter frame
- **THEN** the reported display time lies between the start and the end of that Flutter frame's rasterization, as reported by Flutter's frame timings

#### Scenario: No display time on Android
- **WHEN** on Android, a frame has been queued for display
- **THEN** Dart receives the frame's camera, viewport size and identifier, and the report has no display time

#### Scenario: Finished frame is reported
- **WHEN** on macOS or iOS a frame finishes rendering
- **THEN** Dart receives the frame's slot, identifier, camera, viewport size and camera sequence number before any Flutter frame displays it

#### Scenario: Camera updates faster than the map renders
- **WHEN** Dart sends camera updates with sequence numbers 1, 2 and 3 before the map renders a frame
- **THEN** the next rendered frame reports sequence number 3

## ADDED Requirements

### Requirement: Display slots
On macOS and iOS each map SHALL have four display slots, each with its own Flutter texture. Dart SHALL choose, for each Flutter frame, which finished frame it displays, by displaying the texture of that frame's slot and telling the system which slot it chose. The system SHALL NOT render into a slot from the time Dart chooses it until a Flutter frame that displays a later chosen slot has been rasterized. A finished frame that Dart hasn't chosen MAY be replaced by a newer frame. When Dart chooses a frame that the slot no longer holds, because a newer frame replaced it or a resize replaced the slots, the system SHALL record nothing and SHALL tell Dart, and Dart SHALL keep displaying the frame it chose before. While Dart displays a slot, the contents that Flutter displays for its texture SHALL be the frame that Dart was told the slot holds, including during a resize, until Dart chooses a frame of the new size. On Android each map SHALL have one display slot, and Dart SHALL NOT be told of frames before they are displayed. The system SHALL meet the requirements "Rendering on demand", "No CPU readback on the frame path" and "Frame rate" with the slots.

#### Scenario: Displayed frame matches the chosen frame
- **WHEN** on macOS or iOS Dart chooses the slot of a finished frame and displays its texture
- **THEN** the Flutter frame displays that frame, and the frame-displayed report for that Flutter frame has the identifier of that frame

#### Scenario: Chosen slot is not overwritten
- **WHEN** on macOS or iOS Dart chooses slot A in one Flutter frame and slot B in the next, while the map renders on every Flutter frame
- **THEN** the system doesn't render into slot A until the Flutter frame that displays slot B has been rasterized

#### Scenario: Chosen frame already replaced
- **WHEN** on macOS or iOS the map renders ahead and replaces a finished frame after Dart was told of it, and Dart then chooses that frame
- **THEN** the system tells Dart that it didn't record the choice, doesn't render into the slot of the frame Dart chose before, and Flutter keeps displaying that frame

#### Scenario: Resize with a chosen slot
- **WHEN** on macOS or iOS the viewport is resized while Dart displays a slot
- **THEN** Flutter keeps displaying the frame that slot held until Dart chooses a frame of the new size, and no frame shows an empty or partially rendered buffer

#### Scenario: Frame rate with slots
- **WHEN** the frame-rate benchmark runs on the reference iPhone and the reference Mac with Dart choosing the newest finished slot in each Flutter frame
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report compares it with the rate measured before slots
