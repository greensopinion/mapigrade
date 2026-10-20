## MODIFIED Requirements

### Requirement: Display slots
Each map SHALL have display slots: four on macOS and iOS, each with its own Flutter texture, and six on Android, which share one Flutter texture. In each Flutter frame that Dart builds, Dart SHALL ask the system to choose the newest finished frame that Dart hasn't chosen, and the system SHALL choose the frame that is finished at the time of the request. The system SHALL return the chosen frame's slot, identifier, camera, viewport size and camera sequence number, and Dart SHALL display the texture of that slot in the same Flutter frame. When no finished frame exists that Dart hasn't chosen, the system SHALL record nothing and SHALL tell Dart, and Dart SHALL keep displaying the frame it chose before. On macOS and iOS, the system SHALL NOT render into a slot from the time Dart chooses it until a Flutter frame that displays a later chosen slot has been rasterized. On Android, where Flutter doesn't report when it has finished with a frame, the system SHALL NOT render into a slot from the time Dart chooses it until Dart has chosen three later frames. A finished frame that Dart hasn't chosen MAY be replaced by a newer frame. While Dart displays a slot, the contents that Flutter displays for its texture SHALL be the frame that the system returned for the slot, including during a resize, until Dart chooses another frame. The system SHALL meet the requirements "Rendering on demand", "No CPU readback on the frame path" and "Frame rate" with the slots.

#### Scenario: Displayed frame matches the chosen frame
- **WHEN** Dart asks the system to choose a frame, and displays the texture of the returned slot
- **THEN** the Flutter frame displays the returned frame, and the frame-displayed report for that Flutter frame has the identifier of that frame

#### Scenario: Chosen frame already replaced
- **WHEN** the map finishes a frame, reports it, and replaces it with a newer finished frame before Dart builds the next Flutter frame
- **THEN** in that Flutter frame the system chooses the newer frame and returns its identifier and camera, and Flutter displays the newer frame, not the frame Dart chose before

#### Scenario: Frame finished after the report Dart handled last
- **WHEN** the map finishes a frame and Dart builds a Flutter frame before it has handled the frame's finished-frame report
- **THEN** the system chooses that frame in that Flutter frame

#### Scenario: No new finished frame
- **WHEN** Dart asks the system to choose a frame, and every finished frame has been chosen already
- **THEN** the system records nothing and tells Dart, doesn't render into the slot of the frame Dart chose before, and Flutter keeps displaying that frame

#### Scenario: Chosen slot is not overwritten
- **WHEN** on macOS or iOS Dart chooses slot A in one Flutter frame and slot B in the next, while the map renders on every Flutter frame
- **THEN** the system doesn't render into slot A until the Flutter frame that displays slot B has been rasterized

#### Scenario: Chosen slot is not overwritten on Android
- **WHEN** on Android Dart chooses slot A in one Flutter frame and slots B, C and D in the following Flutter frames, while the map renders on every Flutter frame
- **THEN** the system doesn't render into slot A until Dart has chosen slot D

#### Scenario: Resize with a chosen slot
- **WHEN** the viewport is resized while Dart displays a slot
- **THEN** Flutter keeps displaying the frame that slot held until Dart chooses another frame, and no frame shows an empty or partially rendered buffer

#### Scenario: Frame rate with slots
- **WHEN** the frame-rate benchmark runs on the reference iPhone and the reference Mac with Dart asking the system to choose the newest finished frame in each Flutter frame
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report compares it with the rate measured before slots

#### Scenario: Frame rate with slots on Android
- **WHEN** the frame-rate benchmark runs on the reference Android device with Dart asking the system to choose the newest finished frame in each Flutter frame
- **THEN** the median rendered frame rate is at least 30 frames per second, and the report compares it with the rate measured with one slot
