## MODIFIED Requirements

### Requirement: Supported platforms
The system SHALL support macOS 14.3 or later on arm64, iOS 15.5 or later on arm64 devices, the iOS simulator on arm64 Macs, and Android 10 (API level 29) or later on devices and emulators with the ABI `arm64-v8a`, `armeabi-v7a` or `x86_64`. The same Dart API SHALL work on every supported platform without platform-specific calls from the application.

#### Scenario: Example runs on each platform
- **WHEN** the test harness is built and run on macOS, on an iPhone, on the iOS simulator, on an Android device, on an arm64 Android emulator and on an x86_64 Android emulator, using the same Dart code
- **THEN** on each platform the map appears in the widget, and style, camera, resize and dispose work as specified

#### Scenario: Release build on iPhone
- **WHEN** the test harness is built in release mode and installed on an iPhone
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears

#### Scenario: Release build on Android
- **WHEN** the test harness is built in release mode and installed on the reference Android device
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears with a style and tiles loaded over HTTPS

#### Scenario: Release build on 32-bit ARM
- **WHEN** the test harness is built in release mode and installed with the ABI `armeabi-v7a` on a device that runs 32-bit ARM applications
- **THEN** the app starts, Dart resolves every native function of the plugin, and the map appears with a style and tiles loaded over HTTPS
