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
- **WHEN** an iPhone or an Android phone that shows the map full screen rotates between portrait and landscape
- **THEN** after the rotation, the map fills the widget's new bounds without stretching, and features keep their size in logical pixels

### Requirement: Camera of each displayed frame
The system SHALL report to Dart the camera (center, zoom, bearing) and viewport size that each frame was rendered with. The report SHALL identify the frame, so that Dart can tell which camera a frame corresponds to. On macOS and iOS, the system SHALL send the report when Flutter takes the frame for display, and the report SHALL include the time at which Flutter took it, on the same clock as Flutter's frame timings, so that Dart can match the frame to the Flutter frame that displayed it. On Android, the system SHALL send the report when the frame has been queued for display, and the report SHALL have no display time.

#### Scenario: Frame camera is reported
- **WHEN** a new frame becomes available for display
- **THEN** Dart receives the camera and viewport size the frame was rendered with, and an identifier of that frame

#### Scenario: Display time matches a Flutter frame
- **WHEN** on macOS or iOS, Flutter takes a frame for display while it rasterizes a Flutter frame
- **THEN** the reported display time lies between the start and the end of that Flutter frame's rasterization, as reported by Flutter's frame timings

#### Scenario: No display time on Android
- **WHEN** on Android, a frame has been queued for display
- **THEN** Dart receives the frame's camera, viewport size and identifier, and the report has no display time

### Requirement: Frame rate
During continuous camera changes on the reference Mac, on the reference iPhone and on the reference Android device, the system SHALL display at least 30 frames per second. The target is 60 frames per second or the display's refresh rate. Measured results SHALL be reported against both values.

#### Scenario: Continuous pan
- **WHEN** Dart changes the camera on every Flutter frame for 30 seconds at a fixed zoom over a loaded, cached area, with the window at 1600x1000 logical pixels
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report states the median, p95 and p99 frame durations

#### Scenario: Continuous pan on iPhone
- **WHEN** Dart changes the camera on every Flutter frame for 30 seconds at a fixed zoom over a loaded, cached area, with the map full screen in portrait orientation on the reference iPhone, in a release build
- **THEN** the median displayed frame rate is at least 30 frames per second, and the report states the median, p95 and p99 frame durations

#### Scenario: Continuous pan on Android
- **WHEN** Dart changes the camera on every Flutter frame for 30 seconds at a fixed zoom over a loaded, cached area, with the map full screen in portrait orientation on the reference Android device, in a release build
- **THEN** the median rendered frame rate is at least 30 frames per second, and the report states the median, p95 and p99 frame durations, the Android version, and the renderer Flutter uses

### Requirement: Supported platforms
The system SHALL support macOS 14.3 or later on arm64, iOS 15.5 or later on arm64 devices, the iOS simulator on arm64 Macs, and Android 10 (API level 29) or later on arm64 devices and emulators. The same Dart API SHALL work on every supported platform without platform-specific calls from the application.

#### Scenario: Example runs on each platform
- **WHEN** the example app is built and run on macOS, on an iPhone, on the iOS simulator, on an Android device and on an arm64 Android emulator, using the same Dart code
- **THEN** on each platform the map appears in the widget, and style, camera, resize and dispose work as specified

#### Scenario: Release build on iPhone
- **WHEN** the example app is built in release mode and installed on an iPhone
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears

#### Scenario: Release build on Android
- **WHEN** the example app is built in release mode and installed on the reference Android device
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears with a style and tiles loaded over HTTPS

### Requirement: No rendering while the application is in the background
On iOS while the application is in the background, and on Android while the application's Flutter activity is stopped, the system SHALL NOT submit GPU work for the map. Dart commands sent during that time SHALL be accepted, and SHALL take effect when the application returns to the foreground. When the application returns to the foreground, the system SHALL resume rendering and display a frame rendered with the most recent camera.

#### Scenario: Background during continuous camera changes
- **WHEN** the application moves to the background while Dart changes the camera on every Flutter frame, and returns to the foreground after 10 seconds
- **THEN** no map frames are rendered while the application is in the background, the application does not crash, no render error is reported, and frames resume after the return to the foreground

#### Scenario: Camera set while in the background
- **WHEN** Dart sets the camera while the application is in the background
- **THEN** after the application returns to the foreground, a frame reports that camera

#### Scenario: Dispose while in the background
- **WHEN** Dart disposes the map while the application is in the background
- **THEN** the system releases the map's resources without deadlock, and no events follow the dispose

### Requirement: Memory warnings release cached renderer resources
When the operating system reports memory pressure (a memory warning on iOS; on Android, a trim memory level of `TRIM_MEMORY_BACKGROUND` or higher, or low memory), the system SHALL ask the renderer to release cached resources that it can rebuild. The map SHALL continue to render and display frames afterwards.

#### Scenario: Memory warning during use
- **WHEN** the operating system reports memory pressure while a map is displayed
- **THEN** the application does not crash, and a later camera change produces a frame with that camera

### Requirement: Copy-free rendering by default
By default the system SHALL render each map frame directly into the display buffer that Flutter shows, without a GPU copy. On macOS and iOS, the system SHALL provide an option, chosen when a map is created, to render each frame into a separate texture and copy it on the GPU into the display buffer. On Android, the system SHALL render every map directly into the display buffer, and the option SHALL have no effect. In every mode the system SHALL meet the requirements "Rendering on demand" and "No CPU readback on the frame path", and SHALL report the number of GPU copies, which is 0 for a copy-free map.

#### Scenario: Default map renders without copies
- **WHEN** a map is created without choosing a mode, and its style loads and a frame is displayed
- **THEN** the map has rendered at least one frame and reports 0 GPU copies

#### Scenario: Map with the copy
- **WHEN** on macOS or iOS, a map is created with the copy option, and its style loads and a frame is displayed
- **THEN** the map reports at least one GPU copy for each rendered frame

#### Scenario: Copy option on Android
- **WHEN** on Android, a map is created with the copy option, and its style loads and a frame is displayed
- **THEN** the map reports 0 GPU copies

#### Scenario: Idle copy-free map
- **WHEN** a copy-free map's style and tiles have loaded and Dart sends no further commands for 10 seconds
- **THEN** the system renders no new frames during that period

#### Scenario: Colors in both modes
- **WHEN** the color check (`example/lib/color_check.dart`) runs in each mode the platform offers
- **THEN** the map's fill and background colors match the Flutter swatches of the same colors within 2/255 per channel

## ADDED Requirements

### Requirement: Surface replacement and removal on Android
On Android, when Flutter removes the surface the map renders into, the system SHALL stop using it before Flutter's removal callback returns, and SHALL NOT render until Flutter provides a surface again. When Flutter provides a surface again, or a new surface after a resize, the system SHALL render the next frame into it with the most recent camera, without recreating the map, its style or its loaded tiles.

#### Scenario: Surface removed under memory pressure
- **WHEN** Android reports a trim memory level of `TRIM_MEMORY_BACKGROUND` while the application is in the background, so that Flutter removes the surface, and the application then returns to the foreground
- **THEN** the application does not crash, no render error is reported, and after the return a frame with the most recent camera is displayed without the style being loaded again

#### Scenario: Resize replaces the surface
- **WHEN** the map widget is resized on Android
- **THEN** the map renders into a surface of the new physical size, and frames after the resize fill the widget without stretching
