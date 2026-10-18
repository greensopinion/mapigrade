## MODIFIED Requirements

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing) and viewport size that each frame was rendered with. The report SHALL identify the frame, so that Dart can tell which camera a frame corresponds to. On macOS and iOS, the system SHALL send the report when Flutter takes the frame for display, and the report SHALL include the time at which Flutter took it, on the same clock as Flutter's frame timings, so that Dart can match the frame to the Flutter frame that displayed it. On Android, the system SHALL send the report when Dart chooses the frame for display (requirement "Display slots"), and the report SHALL have no display time. Each camera update from Dart SHALL carry a sequence number, and the report SHALL include the sequence number of the camera update that the frame was rendered with. The system SHALL also report each frame when it has finished rendering, before Flutter displays it, with the same camera, viewport size, identifier and sequence number, and with the display slot that holds it.

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

### Requirement: Surface replacement and removal on Android
On Android, when the application's Flutter activity stops, the system SHALL stop rendering into the surface whose buffers Flutter displays and release it, before the activity's stop callback returns. While the activity is stopped, the system SHALL NOT render. When the activity starts again, the system SHALL render the next frame into a new surface with the most recent camera, without recreating the map, its style or its loaded tiles. After a resize, the system SHALL render the next frame into a surface of the new physical size, under the same condition.

#### Scenario: Surface removed under memory pressure
- **WHEN** Android reports a trim memory level of `TRIM_MEMORY_BACKGROUND` while the application is in the background, and the application then returns to the foreground
- **THEN** the application does not crash, no render error is reported, and after the return a frame with the most recent camera is displayed without the style being loaded again

#### Scenario: Activity stops and starts
- **WHEN** on Android the application's Flutter activity stops and starts again while the map shows a loaded style
- **THEN** no render error is reported, and after the start a frame with the most recent camera is displayed without the style being loaded again

#### Scenario: Resize replaces the surface
- **WHEN** the map widget is resized on Android
- **THEN** the map renders into a surface of the new physical size, and frames after the resize fill the widget without stretching

### Requirement: Display slots
Each map SHALL have display slots: four on macOS and iOS, each with its own Flutter texture, and six on Android, which share one Flutter texture. Dart SHALL choose, for each Flutter frame, which finished frame it displays, by displaying the texture of that frame's slot and telling the system which slot it chose. On macOS and iOS, the system SHALL NOT render into a slot from the time Dart chooses it until a Flutter frame that displays a later chosen slot has been rasterized. On Android, where Flutter doesn't report when it has finished with a frame, the system SHALL NOT render into a slot from the time Dart chooses it until Dart has chosen three later frames. A finished frame that Dart hasn't chosen MAY be replaced by a newer frame. When Dart chooses a frame that the slot no longer holds, because a newer frame replaced it or, on macOS and iOS, a resize replaced the slots, the system SHALL record nothing and SHALL tell Dart, and Dart SHALL keep displaying the frame it chose before. While Dart displays a slot, the contents that Flutter displays for its texture SHALL be the frame that Dart was told the slot holds, including during a resize, until Dart chooses another frame. The system SHALL meet the requirements "Rendering on demand", "No CPU readback on the frame path" and "Frame rate" with the slots.

#### Scenario: Displayed frame matches the chosen frame
- **WHEN** Dart chooses the slot of a finished frame and displays its texture
- **THEN** the Flutter frame displays that frame, and the frame-displayed report for that Flutter frame has the identifier of that frame

#### Scenario: Chosen slot is not overwritten
- **WHEN** on macOS or iOS Dart chooses slot A in one Flutter frame and slot B in the next, while the map renders on every Flutter frame
- **THEN** the system doesn't render into slot A until the Flutter frame that displays slot B has been rasterized

#### Scenario: Chosen slot is not overwritten on Android
- **WHEN** on Android Dart chooses slot A in one Flutter frame and slots B, C and D in the following Flutter frames, while the map renders on every Flutter frame
- **THEN** the system doesn't render into slot A until Dart has chosen slot D

#### Scenario: Chosen frame already replaced
- **WHEN** the map renders ahead and replaces a finished frame after Dart was told of it, and Dart then chooses that frame
- **THEN** the system tells Dart that it didn't record the choice, doesn't render into the slot of the frame Dart chose before, and Flutter keeps displaying that frame

#### Scenario: Resize with a chosen slot
- **WHEN** the viewport is resized while Dart displays a slot
- **THEN** Flutter keeps displaying the frame that slot held until Dart chooses another frame, and no frame shows an empty or partially rendered buffer

#### Scenario: Frame rate with slots
- **WHEN** the frame-rate benchmark runs on the reference iPhone and the reference Mac with Dart choosing the newest finished slot in each Flutter frame
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report compares it with the rate measured before slots

#### Scenario: Frame rate with slots on Android
- **WHEN** the frame-rate benchmark runs on the reference Android device with Dart choosing the newest finished slot in each Flutter frame
- **THEN** the median rendered frame rate is at least 30 frames per second, and the report compares it with the rate measured with one slot
