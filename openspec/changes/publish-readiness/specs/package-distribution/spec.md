## Purpose

Defines what the published `flutter_mapigrade` package contains, where an application's build gets the MapLibre Native FFI libraries from, how one FFI release version applies to every platform, and how the repository checks that an application builds from the published archive alone.

## ADDED Requirements

### Requirement: Published archive contents
The archive that `flutter pub publish` creates for the package SHALL NOT contain a MapLibre Native FFI library, framework or xcframework for any platform. Every file that an application's build of the package reads SHALL be in the archive or SHALL be a download that the requirement "Native libraries from the pinned release" names. The package's pubspec SHALL name the repository and the issue tracker, and SHALL NOT prevent publishing. A dry run of `flutter pub publish` from a clean checkout SHALL report no warnings.

#### Scenario: Dry run
- **WHEN** a developer runs `flutter pub publish --dry-run` in the package directory of a clean checkout
- **THEN** the command reports no warnings, and the file list it prints contains no file with the extension `.so`, `.a`, `.dylib`, `.framework` or `.xcframework`

#### Scenario: Dry run with a local FFI build
- **WHEN** the checkout also contains a local FFI build that the repository's builds use
- **THEN** the file list of the dry run is the same as in a checkout without it

### Requirement: Native libraries from the pinned release
The package SHALL state one version of the upstream MapLibre Native FFI release. An application's build of the package SHALL get the FFI libraries for Android, iOS and macOS from that release's published artifacts and from no other source. On Android the build SHALL get the libraries for `arm64-v8a`, `armeabi-v7a` and `x86_64` from Maven Central. On iOS and macOS the build SHALL download one archive of the framework from a URL that the package states, and SHALL check it against a SHA-256 checksum that the package states. The FFI headers, the FFI library that the plugin links against and the notice files in the package SHALL come from the same release version.

#### Scenario: Checksum mismatch
- **WHEN** the framework archive that the build downloads doesn't match the checksum in the package
- **THEN** the build of the iOS or macOS application fails with an error that names the archive, and the application isn't built

#### Scenario: Pins disagree
- **WHEN** the release version, the framework URL or the checksum that one platform's build uses differs from the version or the values that the package states for it
- **THEN** a unit test of the package fails and names the value that differs

#### Scenario: Headers differ from the release
- **WHEN** the FFI headers in the package differ from the headers of the pinned release, and the release's artifacts are available to the test
- **THEN** a test fails and names the header

### Requirement: Application build from the published archive
An application that depends on the package, with the package's files exactly as the published archive contains them, SHALL build on a machine that has no checkout of this repository and no local FFI build. The release Android build SHALL contain, for each of `arm64-v8a`, `armeabi-v7a` and `x86_64`, the FFI library and the plugin's native library. The iOS and macOS builds SHALL contain the FFI framework. The build SHALL need network access only until the downloads that the requirement "Native libraries from the pinned release" names are cached on the machine.

#### Scenario: Consumer build in CI
- **WHEN** CI copies the files that the dry run lists to a directory outside the checkout, creates a new Flutter application that depends on that directory, and builds a release APK, an iOS simulator build, an iOS device build without code signing and a macOS build on a runner without an FFI build
- **THEN** every build succeeds, the APK's `lib/` directory contains `libmaplibre-native-c.so` and `libflutter_mapigrade.so` for each of the three ABIs, and the iOS and macOS applications contain `MaplibreNativeC.framework`

#### Scenario: Build reads a file outside the package
- **WHEN** a change makes the package's Android or Apple build read a file through a path outside the package directory
- **THEN** the CI consumer build fails

#### Scenario: Release build on each Android ABI
- **WHEN** a release build of the consumer application loads a style over HTTPS on an `arm64-v8a` device, on an `x86_64` emulator and as an `armeabi-v7a` installation
- **THEN** the map appears with the style and tiles loaded

### Requirement: Local FFI build for repository development
When this repository's checkout contains a local FFI build, builds of the example and the test harness SHALL use the local FFI build in place of the release artifacts, for every platform that the local build installed. A build SHALL NOT combine libraries of the local build and of the release. The Android build output SHALL state which of the two the build uses. Builds from the published archive SHALL use the release artifacts.

#### Scenario: Local FFI build present
- **WHEN** a developer runs `scripts/build_maplibre_ffi.sh` and then builds the test harness for Android and macOS
- **THEN** the builds use the libraries of the local build, and the Android build output states that it uses the local FFI build

#### Scenario: No local FFI build
- **WHEN** the checkout has no local FFI build and a developer builds the test harness for Android and macOS
- **THEN** the builds use the release artifacts, and the Android build output states the release version
