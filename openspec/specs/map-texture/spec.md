# map-texture Specification

## Purpose

Displays a MapLibre Native map as a Flutter `Texture` widget that composes with other Flutter widgets, and lets Dart code control the map's style, camera, viewport and lifecycle. The capability is specified for macOS only.

## Requirements

### Requirement: Map displays in a composable Flutter widget
The system SHALL display the rendered map through a Flutter `Texture` widget. It SHALL NOT use a platform view. Flutter widgets placed above the map in a `Stack` SHALL be drawn on top of the map and SHALL receive pointer input as they would over any other widget.

#### Scenario: Map appears after style load
- **WHEN** a Dart caller creates a map, loads a valid style, and places the map widget in the widget tree
- **THEN** the widget shows the rendered map for the current camera within the widget's bounds

#### Scenario: Flutter overlay above the map
- **WHEN** a Flutter widget is placed above the map widget in a `Stack`
- **THEN** the overlay widget is drawn on top of the map and receives pointer events in its bounds

### Requirement: Style loading
The system SHALL load a map style from a URL or from a JSON string. It SHALL report to Dart when the style has loaded and when loading the style fails. A failure SHALL include a message that describes the cause.

#### Scenario: Style loads from URL
- **WHEN** a Dart caller loads a style from a reachable URL
- **THEN** the system reports that the style loaded, and the map renders using that style

#### Scenario: Style fails to load
- **WHEN** a Dart caller loads a style from an unreachable URL or from invalid JSON
- **THEN** the system reports a style load failure with a descriptive message, and the application does not crash

#### Scenario: Style is replaced
- **WHEN** a Dart caller loads a second style after the first one has loaded
- **THEN** the map renders using the second style

### Requirement: Camera control
The system SHALL set the map camera from Dart, using center latitude and longitude, zoom, and bearing. When Dart sends camera updates faster than the map renders, the system SHALL render the most recent camera; it is not required to render intermediate cameras. A camera update SHALL NOT block the Dart caller until a frame renders.

#### Scenario: Camera change is displayed
- **WHEN** a Dart caller sets the camera to a known center, zoom and bearing
- **THEN** a later displayed frame shows the map at that camera

#### Scenario: Rapid camera updates
- **WHEN** a Dart caller sends camera updates on every Flutter frame for several seconds
- **THEN** each displayed frame shows the most recent camera received before that frame was rendered, and the system does not build up a backlog of earlier cameras

### Requirement: Viewport size and pixel ratio
The system SHALL render the map at the widget's logical size multiplied by the device pixel ratio, so that one rendered pixel corresponds to one physical pixel. When the widget's size or the device pixel ratio changes, the system SHALL render subsequent frames at the new size and ratio.

#### Scenario: Window resize
- **WHEN** the user resizes the window that contains the map widget
- **THEN** after the resize, the map fills the widget's new bounds without stretching, and features keep their size in logical pixels

#### Scenario: Device pixel ratio change
- **WHEN** the window moves to a display with a different device pixel ratio
- **THEN** the map renders at the new ratio, and text and lines remain sharp

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing) and viewport size that each displayed frame was rendered with. The report SHALL identify the frame, so that Dart can tell which camera the currently displayed frame corresponds to.

#### Scenario: Frame camera is reported
- **WHEN** a new frame becomes available for display
- **THEN** Dart receives the camera and viewport size the frame was rendered with, and an identifier of that frame

### Requirement: Rendering on demand
The system SHALL render a frame only when the map needs a new frame, for example after a camera, style, size or data change, or during a style transition. When the map does not change, the system SHALL NOT render frames.

#### Scenario: Idle map
- **WHEN** the style and tiles have loaded and Dart sends no further commands for 10 seconds
- **THEN** the system renders no new frames during that period

### Requirement: No CPU readback on the frame path
The system SHALL NOT copy rendered frame pixels into CPU memory on the path from rendering to display. Frames SHALL reach Flutter through GPU memory only. GPU-to-GPU copies are permitted.

#### Scenario: Frame path inspection
- **WHEN** the frame path is inspected in source and in a GPU capture during camera changes
- **THEN** no rendered frame is read back into CPU memory, encoded, or uploaded from Dart

### Requirement: Frame rate
During continuous camera changes on the reference Mac, the system SHALL display at least 30 frames per second. The target is 60 frames per second or the display's refresh rate. Measured results SHALL be reported against both values.

#### Scenario: Continuous pan
- **WHEN** Dart changes the camera on every Flutter frame for 30 seconds at a fixed zoom over a loaded, cached area, with the window at 1600x1000 logical pixels
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report states the median, p95 and p99 frame durations

### Requirement: Lifecycle and resource release
The system SHALL release the map, its render resources, its threads and its Flutter texture registration when Dart disposes the map. Creating and disposing maps repeatedly SHALL NOT increase memory use or thread count without bound. Calls made after dispose SHALL fail with an error and SHALL NOT crash.

#### Scenario: Dispose releases resources
- **WHEN** a Dart caller creates and disposes a map 50 times in sequence
- **THEN** thread count returns to its value before the first create, and memory use stays within a bounded range

#### Scenario: Call after dispose
- **WHEN** a Dart caller sets the camera on a map that has been disposed
- **THEN** the call reports an error and the application continues to run

#### Scenario: Widget removed while rendering
- **WHEN** the map widget is removed from the tree and the map is disposed while a frame is rendering
- **THEN** the system completes or abandons the frame, releases its resources, and does not crash or deadlock
