# third-party-notices Specification

## Purpose

Defines the package's own license, the third-party notices that apps built with the package show in Flutter's license registry on each platform, and how the notices in the package stay equal to the notices of the MapLibre Native FFI build that the package links.

## Requirements

### Requirement: Package license
Both packages SHALL be licensed under the BSD 3-Clause License. The `LICENSE` file of each SHALL contain the BSD 3-Clause license text with the copyright line `Copyright (c) 2026 David Green`, and SHALL NOT contain other license texts. The repository root SHALL contain a `LICENSE` file identical to the packages', which covers the repository's files outside the packages.

#### Scenario: License shown for the package
- **WHEN** an application that depends on `flutter_mapigrade` opens `showLicensePage` and selects `flutter_mapigrade`, and then `mapigrade`
- **THEN** each page shows the BSD 3-Clause license text with the copyright line `Copyright (c) 2026 David Green`, and no placeholder text

#### Scenario: Repository license
- **WHEN** a reader opens the repository's root `LICENSE`
- **THEN** it has the same content as `packages/mapigrade/LICENSE` and `packages/flutter_mapigrade/LICENSE`

### Requirement: Native notices in the license registry
An application that depends on `mapigrade`, directly or through `flutter_mapigrade`, SHALL list, in Flutter's license registry, one license entry for each notice file of the MapLibre Native FFI that applies to the platform the application runs on, without calling any code of either package. A notice file applies to Android when the release tarball of an Android preset contains it, and to macOS and iOS when the release tarball of an Apple preset contains it. Each entry SHALL contain the notice file's text unchanged, and SHALL name the component that the file covers, or the notice file's name when the package doesn't know the component. `mapigrade` SHALL provide the entries; `flutter_mapigrade` SHALL NOT provide entries of its own for the FFI.

Applications for macOS and iOS SHALL NOT list a notice file that only the tarballs of Android presets contain, and SHALL NOT contain it. A notice file that only the tarballs of Apple presets contain MAY also be listed on Android.

A notice file that a release adds or removes SHALL NOT require a change to the package's code or tests for the entries to follow the release.

The package SHALL NOT read the notice files before an application reads the license registry.

#### Scenario: License page on Android
- **WHEN** an application that depends on `flutter_mapigrade` and contains no code that refers to licenses opens `showLicensePage` on Android
- **THEN** the page lists one entry for each notice file of the release's Android tarballs, once, and each entry shows the text of its notice file

#### Scenario: License page with mapigrade only
- **WHEN** an application that depends on `mapigrade` and not on `flutter_mapigrade` opens `showLicensePage`
- **THEN** the page lists the same entries for the FFI's notice files as for an application that depends on `flutter_mapigrade`

#### Scenario: License page on macOS and iOS
- **WHEN** such an application opens `showLicensePage` on macOS or iOS
- **THEN** the page lists one entry for each notice file of the release's Apple tarballs, and no entry for a notice file that only the Android tarballs contain

#### Scenario: Apple app bundle
- **WHEN** an application that depends on `mapigrade` is built for macOS or iOS
- **THEN** the application bundle contains the notice files of the release's Apple tarballs, and no notice file that only the Android tarballs contain

#### Scenario: Release removes a notice file
- **WHEN** a developer updates `mapigrade` to an FFI release whose Android tarball no longer contains a notice file, and runs the script that copies the notice files
- **THEN** the package no longer contains the file, applications no longer list its entry, and the package's tests pass without other changes

#### Scenario: Release adds a notice file
- **WHEN** a developer updates `mapigrade` to an FFI release whose tarballs contain a notice file that no earlier release contained, and runs the script
- **THEN** the package contains the file, applications on the platforms it applies to list an entry for it, and the package's tests pass without other changes

#### Scenario: Registry not read
- **WHEN** an application starts and never reads the license registry
- **THEN** the package doesn't load any notice file

### Requirement: Notices equal to the FFI build
The notice files of the MapLibre Native FFI are the files that the release tarballs of the FFI version `mapigrade` states contain as `share/maplibre-native-c/LICENSE` and in `share/maplibre-native-c/licenses/`, for the presets whose libraries applications built with the package contain. Other files in `share/maplibre-native-c/`, such as `artifact.json`, are not notice files. The notice files in `mapigrade` SHALL be byte-identical to the notice files of that release, and `mapigrade` SHALL contain one for every notice file of every such preset, and no other. `flutter_mapigrade` SHALL contain no notice file of the FFI. A script SHALL update the notice files in `mapigrade` from the release, without a list of expected notice files. A test SHALL fail when a notice file in `mapigrade` differs from, or is missing for, a notice file of the release, or has no notice file in the release, and SHALL be skipped when the release tarballs aren't available to it.

#### Scenario: FFI update changes a notice
- **WHEN** a developer changes the FFI version that `mapigrade` states and runs the script, and the new release adds a Rust crate
- **THEN** the package's `rust.md` contains the new crate's notice, and the diff of the change shows it

#### Scenario: Notice files out of date
- **WHEN** a release tarball of the stated version has a notice file that differs from the package's copy, or that the package doesn't contain, or the package contains a notice file that no release tarball of the stated version has
- **THEN** the package's tests fail and name the file

#### Scenario: No FFI build present
- **WHEN** the package's tests run where the release tarballs of the stated version aren't available
- **THEN** the comparison test is skipped and the other tests run

#### Scenario: Local FFI build at another commit
- **WHEN** a developer builds the FFI locally at a commit other than the stated release's
- **THEN** the notice files in the package don't change
