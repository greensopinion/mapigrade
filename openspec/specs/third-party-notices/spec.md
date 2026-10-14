# third-party-notices Specification

## Purpose

Defines the package's own license, the third-party notices that apps built with the package show in Flutter's license registry on each platform, and how the notices in the package stay equal to the notices of the MapLibre Native FFI build that the package links.

## Requirements

### Requirement: Package license
The package SHALL be licensed under the BSD 3-Clause License. Its `LICENSE` file SHALL contain the BSD 3-Clause license text with the copyright line `Copyright (c) 2026 David Green`, and SHALL NOT contain other license texts. The repository root SHALL contain a `LICENSE` file identical to the package's, which covers the repository's files outside the package.

#### Scenario: License shown for the package
- **WHEN** an application that depends on the package opens `showLicensePage` and selects `flutter_mapigrade`
- **THEN** the page shows the BSD 3-Clause license text with the copyright line `Copyright (c) 2026 David Green`, and no placeholder text

#### Scenario: Repository license
- **WHEN** a reader opens the repository's root `LICENSE`
- **THEN** it has the same content as `packages/flutter_mapigrade/LICENSE`

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

Applications for macOS and iOS SHALL NOT list the two Android entries, and SHALL NOT contain their notice files.

The package SHALL NOT read the notice files before an application reads the license registry.

#### Scenario: License page on Android
- **WHEN** an application that depends on the package and contains no code that refers to licenses opens `showLicensePage` on Android
- **THEN** the page lists the six entries for every platform and the two Android entries, and each entry shows the text of its notice file

#### Scenario: License page on macOS and iOS
- **WHEN** such an application opens `showLicensePage` on macOS or iOS
- **THEN** the page lists the six entries for every platform, and lists neither "MapLibre Native FFI Rust crates" nor "Android NDK C++ runtime"

#### Scenario: Apple app bundle
- **WHEN** an application that depends on the package is built for macOS or iOS
- **THEN** the application bundle contains the six notice files for every platform and doesn't contain `rust.md` or `cxx-runtime.txt`

#### Scenario: Registry not read
- **WHEN** an application starts and never reads the license registry
- **THEN** the package doesn't load any notice file

### Requirement: Notices equal to the FFI build
The notice files of the MapLibre Native FFI build are the files that the build, at the commit in `scripts/maplibre_ffi.lock`, installs as `share/maplibre-native-c/LICENSE` and in `share/maplibre-native-c/licenses/` of each preset. Other files in `share/maplibre-native-c/`, such as `artifact.json`, are not notice files. The notice files in the package SHALL be byte-identical to the notice files of the build, and the package SHALL contain one for every notice file of every preset. Building the FFI with `scripts/build_maplibre_ffi.sh` SHALL update the notice files in the package. A test SHALL fail when a notice file in the package differs from, or is missing for, a file of an installed preset, and SHALL be skipped when no preset is installed.

#### Scenario: FFI update changes a notice
- **WHEN** a developer changes the commit in `scripts/maplibre_ffi.lock` and runs `scripts/build_maplibre_ffi.sh`, and the new commit adds a Rust crate
- **THEN** the package's `rust.md` contains the new crate's notice, and the diff of the change shows it

#### Scenario: Notice files out of date
- **WHEN** a preset installed in `third_party/maplibre-native-ffi/` has a notice file that differs from the package's copy, or that the package doesn't contain
- **THEN** the package's tests fail and name the file

#### Scenario: No FFI build present
- **WHEN** the package's tests run in a checkout where `third_party/maplibre-native-ffi/` doesn't exist
- **THEN** the comparison test is skipped and the other tests run
