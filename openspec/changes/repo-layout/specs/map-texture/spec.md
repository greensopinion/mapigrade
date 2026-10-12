## MODIFIED Requirements

### Requirement: Supported platforms
The system SHALL support macOS 14.3 or later on arm64, iOS 15.5 or later on arm64 devices, the iOS simulator on arm64 Macs, and Android 10 (API level 29) or later on arm64 devices and emulators. The same Dart API SHALL work on every supported platform without platform-specific calls from the application.

#### Scenario: Example runs on each platform
- **WHEN** the test harness is built and run on macOS, on an iPhone, on the iOS simulator, on an Android device and on an arm64 Android emulator, using the same Dart code
- **THEN** on each platform the map appears in the widget, and style, camera, resize and dispose work as specified

#### Scenario: Release build on iPhone
- **WHEN** the test harness is built in release mode and installed on an iPhone
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears

#### Scenario: Release build on Android
- **WHEN** the test harness is built in release mode and installed on the reference Android device
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears with a style and tiles loaded over HTTPS

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
- **WHEN** the color check (`packages/test_harness/lib/color_check.dart`) runs in each mode the platform offers
- **THEN** the map's fill and background colors match the Flutter swatches of the same colors within 2/255 per channel
