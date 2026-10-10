## ADDED Requirements

### Requirement: Supported platforms
The system SHALL support macOS 14.3 or later on arm64, iOS 15.5 or later on arm64 devices, and the iOS simulator on arm64 Macs. The same Dart API SHALL work on every supported platform without platform-specific calls from the application.

#### Scenario: Example runs on each platform
- **WHEN** the example app is built and run on macOS, on an iPhone, and on the iOS simulator, using the same Dart code
- **THEN** on each platform the map appears in the widget, and style, camera, resize and dispose work as specified

#### Scenario: Release build on iPhone
- **WHEN** the example app is built in release mode and installed on an iPhone
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears

### Requirement: No rendering while the application is in the background
On iOS, while the application is in the background, the system SHALL NOT submit GPU work for the map. Dart commands sent while the application is in the background SHALL be accepted, and SHALL take effect when the application returns to the foreground. When the application returns to the foreground, the system SHALL resume rendering and display a frame rendered with the most recent camera.

#### Scenario: Background during continuous camera changes
- **WHEN** the application moves to the background while Dart changes the camera on every Flutter frame, and returns to the foreground after 10 seconds
- **THEN** no map frames are rendered while the application is in the background, the application does not crash, no render error is reported, and frames resume after the return to the foreground

#### Scenario: Camera set while in the background
- **WHEN** Dart sets the camera while the application is in the background
- **THEN** after the application returns to the foreground, a displayed frame reports that camera

#### Scenario: Dispose while in the background
- **WHEN** Dart disposes the map while the application is in the background
- **THEN** the system releases the map's resources without deadlock, and no events follow the dispose

### Requirement: Memory warnings release cached renderer resources
On iOS, when the operating system reports a memory warning, the system SHALL ask the renderer to release cached resources that it can rebuild. The map SHALL continue to render and display frames after the warning.

#### Scenario: Memory warning during use
- **WHEN** the operating system reports a memory warning while a map is displayed
- **THEN** the application does not crash, and a later camera change produces a displayed frame with that camera

## MODIFIED Requirements

### Requirement: Viewport size and pixel ratio
The system SHALL render the map at the widget's logical size multiplied by the device pixel ratio, so that one rendered pixel corresponds to one physical pixel. When the widget's size or the device pixel ratio changes, the system SHALL render subsequent frames at the new size and ratio.

#### Scenario: Window resize
- **WHEN** the user resizes the window that contains the map widget
- **THEN** after the resize, the map fills the widget's new bounds without stretching, and features keep their size in logical pixels

#### Scenario: Device pixel ratio change
- **WHEN** the window moves to a display with a different device pixel ratio
- **THEN** the map renders at the new ratio, and text and lines remain sharp

#### Scenario: Orientation change
- **WHEN** an iPhone that shows the map full screen rotates between portrait and landscape
- **THEN** after the rotation, the map fills the widget's new bounds without stretching, and features keep their size in logical pixels

### Requirement: Frame rate
During continuous camera changes on the reference Mac and on the reference iPhone, the system SHALL display at least 30 frames per second. The target is 60 frames per second or the display's refresh rate. Measured results SHALL be reported against both values.

#### Scenario: Continuous pan
- **WHEN** Dart changes the camera on every Flutter frame for 30 seconds at a fixed zoom over a loaded, cached area, with the window at 1600x1000 logical pixels
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report states the median, p95 and p99 frame durations

#### Scenario: Continuous pan on iPhone
- **WHEN** Dart changes the camera on every Flutter frame for 30 seconds at a fixed zoom over a loaded, cached area, with the map full screen in portrait orientation on the reference iPhone, in a release build
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report states the median, p95 and p99 frame durations
