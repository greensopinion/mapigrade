## MODIFIED Requirements

### Requirement: Native notices in the license registry
An application that depends on the package SHALL list, in Flutter's license registry, one license entry for each notice file of the MapLibre Native FFI that applies to the platform the application runs on, without calling any code of the package. Each entry SHALL contain the notice file's text unchanged and SHALL name the component that the file covers.

On every supported platform the entries SHALL be:

| Package name in the entry | Notice file |
| --- | --- |
| MapLibre Native FFI | the FFI's `LICENSE` |
| MapLibre Native | `licenses/maplibre-native.md` |
| ICU | `licenses/icu.txt` |
| FastPFOR | `licenses/fastpfor.txt` |
| nunicode | `licenses/nunicode.txt` |
| PMTiles | `licenses/pmtiles.txt` |

On Android the entries SHALL also include:

| Package name in the entry | Notice file |
| --- | --- |
| MapLibre Native FFI Rust crates | `licenses/rust.md` |
| Android NDK C++ runtime | `licenses/cxx-runtime.txt` |
| Kotlin | `licenses/kotlin.txt` |
| Kotlin NOTICE | `licenses/kotlin-notice.txt` |
| rustls-platform-verifier | `licenses/rustls-platform-verifier-notice.txt` |

Applications for macOS and iOS SHALL NOT list the five Android entries, and SHALL NOT contain their notice files.

The package SHALL NOT read the notice files before an application reads the license registry.

#### Scenario: License page on Android
- **WHEN** an application that depends on the package and contains no code that refers to licenses opens `showLicensePage` on Android
- **THEN** the page lists the six entries for every platform and the five Android entries, and each entry shows the text of its notice file

#### Scenario: License page on macOS and iOS
- **WHEN** such an application opens `showLicensePage` on macOS or iOS
- **THEN** the page lists the six entries for every platform, and none of the five Android entries

#### Scenario: Apple app bundle
- **WHEN** an application that depends on the package is built for macOS or iOS
- **THEN** the application bundle contains the six notice files for every platform and none of the five Android notice files

#### Scenario: Registry not read
- **WHEN** an application starts and never reads the license registry
- **THEN** the package doesn't load any notice file
