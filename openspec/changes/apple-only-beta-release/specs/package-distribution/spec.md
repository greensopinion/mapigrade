## MODIFIED Requirements

### Requirement: Native libraries from the pinned release
`mapigrade` SHALL state one version of the upstream MapLibre Native FFI release, except in a prerelease without an FFI release as described below. An application's build of `mapigrade` SHALL get the FFI libraries for Android, iOS and macOS from that release's published artifacts and from no other source. On Android the build SHALL get the libraries for `arm64-v8a`, `armeabi-v7a` and `x86_64` from Maven Central. On iOS and macOS the build SHALL download one archive of the framework from a URL that `mapigrade` states, and SHALL check it against a SHA-256 checksum that `mapigrade` states. The FFI headers, the FFI library that the plugin links against and the notice files in `mapigrade` SHALL come from the same release version.

A prerelease of the packages, a version with a prerelease suffix such as `0.2.0-beta.1`, SHALL be allowed to pin an FFI commit that no FFI release contains, when its iOS and macOS framework comes from an archive that this repository's maintainers built from that commit and published as an asset of a GitHub release of this repository. Such a prerelease is a *prerelease without an FFI release*. In it, `mapigrade` SHALL state the FFI commit, the archive's URL and its SHA-256 checksum, and no FFI release version; the iOS and macOS builds SHALL download and check the archive as for a release; `mapigrade` SHALL NOT declare Android as a plugin platform; and the FFI headers and the notice files in `mapigrade` SHALL come from the pinned commit. A version without a prerelease suffix SHALL NOT be published without an FFI release.

#### Scenario: Checksum mismatch
- **WHEN** the framework archive that the build downloads doesn't match the checksum in `mapigrade`
- **THEN** the build of the iOS or macOS application fails with an error that names the archive, and the application isn't built

#### Scenario: Pins disagree
- **WHEN** the release version, the framework URL or the checksum that one platform's build uses differs from the version or the values that `mapigrade` states for it
- **THEN** a unit test of `mapigrade` fails and names the value that differs

#### Scenario: Stable version without an FFI release
- **WHEN** the packages' version has no prerelease suffix, and `mapigrade` states no FFI release version
- **THEN** a unit test of `mapigrade` fails and states that a stable version needs an FFI release

#### Scenario: Prerelease with a self-hosted framework
- **WHEN** the packages' version is `0.2.0-beta.1`, and `mapigrade` states an FFI commit, the URL of a framework archive among the assets of a GitHub release of this repository, and the archive's checksum
- **THEN** the unit tests of `mapigrade` pass, and an iOS build of an application downloads the archive from that URL and checks it against that checksum

#### Scenario: Prerelease that declares Android
- **WHEN** `mapigrade` states no FFI release version and declares Android as a plugin platform
- **THEN** a unit test of `mapigrade` fails and names the Android platform

### Requirement: Application build from the published archive
An application that depends on `flutter_mapigrade`, with the files of `flutter_mapigrade` and of `mapigrade` exactly as their published archives contain them, SHALL build on a machine that has no checkout of this repository and no local FFI build. The release Android build SHALL contain, for each of `arm64-v8a`, `armeabi-v7a` and `x86_64`, the FFI library and the plugin's native library. The iOS and macOS builds SHALL contain the FFI framework. The build SHALL need network access only until the downloads that the requirement "Native libraries from the pinned release" names are cached on the machine. For a prerelease without an FFI release, the release Android build SHALL succeed and contain neither the FFI library nor the plugin's native library, and on Android `Mapigrade.isSupported` and `MapigradeLayer.isSupported` SHALL be false.

#### Scenario: Consumer build in CI
- **WHEN** CI copies the files that the dry runs of both packages list to directories outside the checkout, creates a new Flutter application that depends on the `flutter_mapigrade` directory, with `mapigrade` resolved from its directory, and builds a release APK, an iOS simulator build, an iOS device build without code signing and a macOS build on a runner without an FFI build
- **THEN** every build succeeds, the APK's `lib/` directory contains `libmaplibre-native-c.so` and `libmapigrade.so` for each of the three ABIs, and the iOS and macOS applications contain `MaplibreNativeC.framework`

#### Scenario: Build reads a file outside the package
- **WHEN** a change makes `mapigrade`'s Android or Apple build read a file through a path outside the package directory
- **THEN** the CI consumer build fails

#### Scenario: Release build on each Android ABI
- **WHEN** a release build of the consumer application loads a style over HTTPS on an `arm64-v8a` device, on an `x86_64` emulator and as an `armeabi-v7a` installation
- **THEN** the map appears with the style and tiles loaded

#### Scenario: Consumer build of a prerelease without an FFI release
- **WHEN** CI runs the consumer build for a prerelease without an FFI release
- **THEN** the release APK, the iOS builds and the macOS build succeed, the APK's `lib/` directory contains neither `libmaplibre-native-c.so` nor `libmapigrade.so`, and the iOS and macOS applications contain `MaplibreNativeC.framework`

#### Scenario: Android application of a prerelease without an FFI release
- **WHEN** an application that depends on a prerelease without an FFI release runs on an Android device and places a `MapigradeMap`
- **THEN** the application starts, `Mapigrade.isSupported` is false, the map reports one `MapigradeCreateException`, and the map's children are built
