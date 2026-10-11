## ADDED Requirements

### Requirement: Copy-free rendering by default
By default the system SHALL render each map frame directly into the display buffer that Flutter shows, without a GPU copy. The system SHALL provide an option, chosen when a map is created, to render each frame into a separate texture and copy it on the GPU into the display buffer. In both modes the system SHALL meet the requirements "Rendering on demand" and "No CPU readback on the frame path", and SHALL report the number of GPU copies, which is 0 for a copy-free map.

#### Scenario: Default map renders without copies
- **WHEN** a map is created without choosing a mode, and its style loads and a frame is displayed
- **THEN** the map has rendered at least one frame and reports 0 GPU copies

#### Scenario: Map with the copy
- **WHEN** a map is created with the copy option, and its style loads and a frame is displayed
- **THEN** the map reports at least one GPU copy for each rendered frame

#### Scenario: Idle copy-free map
- **WHEN** a copy-free map's style and tiles have loaded and Dart sends no further commands for 10 seconds
- **THEN** the system renders no new frames during that period

#### Scenario: Colors in both modes
- **WHEN** the color check (`example/lib/color_check.dart`) runs in each mode
- **THEN** the map's fill and background colors match the Flutter swatches of the same colors within 2/255 per channel
