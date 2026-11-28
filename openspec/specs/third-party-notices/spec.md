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
An application that depends on the package SHALL list, in Flutter's license registry, one license entry for each notice file of the MapLibre Native FFI that applies to the platform the application runs on, without calling any code of the package. A notice file applies to Android when the FFI build of an Android preset contains it, and to macOS and iOS when the FFI build of an Apple preset contains it. When the Apple and the Android presets each contain a notice file of the same name with different content, each platform's applications list the file of their own presets. Each entry SHALL contain the notice file's text, which for an HTML notice file is its text without markup and for another notice file its content unchanged, and SHALL name the component that the file covers, or the notice file's name when the package doesn't know the component.

Applications for macOS and iOS SHALL NOT list a notice file that only the Android presets contain, nor the Android presets' file of a name whose content differs between the platforms, and SHALL NOT contain them. Applications for Android SHALL NOT list a notice file that only the Apple presets contain, nor the Apple presets' file of a name whose content differs between the platforms.

A notice file that the FFI adds or removes SHALL NOT require a change to the package's code or tests for the entries to follow the FFI.

The package SHALL NOT read the notice files before an application reads the license registry.

#### Scenario: License page on Android
- **WHEN** an application that depends on the package and contains no code that refers to licenses opens `showLicensePage` on Android
- **THEN** the page lists one entry for each notice file of the Android presets, and each entry shows the text of its notice file

#### Scenario: License page on macOS and iOS
- **WHEN** such an application opens `showLicensePage` on macOS or iOS
- **THEN** the page lists one entry for each notice file of the Apple presets, and no entry for a notice file that only the Android presets contain

#### Scenario: Notice that differs between the platforms
- **WHEN** the Apple presets' `rust.md` lists other Rust crates than the Android preset's, and an application opens `showLicensePage`
- **THEN** on macOS and iOS the `rust.md` entry shows the Apple presets' text, and on Android the Android preset's text

#### Scenario: HTML notice
- **WHEN** an application that depends on the package opens `showLicensePage`, and the FFI build's notice files include `rust-std.html`
- **THEN** the entry of the Rust standard library shows the notice's text without HTML tags

#### Scenario: Apple app bundle
- **WHEN** an application that depends on the package is built for macOS or iOS
- **THEN** the application bundle contains the notice files of the Apple presets, and no notice file of the Android presets that differs from or is missing in the Apple presets

#### Scenario: Release removes a notice file
- **WHEN** a developer updates the package to an FFI release whose Android tarball no longer contains a notice file, and runs the script that copies the notice files
- **THEN** the package no longer contains the file, applications no longer list its entry, and the package's tests pass without other changes

#### Scenario: Release adds a notice file
- **WHEN** a developer updates the package to an FFI release whose tarballs contain a notice file that no earlier release contained, and runs the script
- **THEN** the package contains the file, applications on the platforms it applies to list an entry for it, and the package's tests pass without other changes

#### Scenario: Registry not read
- **WHEN** an application starts and never reads the license registry
- **THEN** the package doesn't load any notice file

### Requirement: Notices equal to the FFI build
The notice files of the MapLibre Native FFI are the files that the FFI build of each preset whose library applications built with the package contain has as `share/maplibre-native-c/LICENSE` and in `share/maplibre-native-c/licenses/`. The FFI build is the release tarball of the FFI version the package states, or, while the package states no release, the install of the stated commit that the repository's local build script makes. Other files in `share/maplibre-native-c/`, such as `artifact.json`, are not notice files. The notice files in the package SHALL be byte-identical to the notice files of that FFI build, except that the package SHALL contain an HTML notice file as the text that the script converts it to, in a file with the extension `.txt` and the same base name. The package SHALL contain one notice file for every notice file of every such preset, and no other. A script SHALL update the notice files in the package from the FFI build, without a list of expected notice files. A test SHALL fail when a notice file in the package differs from, or is missing for, a notice file of the FFI build, or has no notice file in the FFI build, and SHALL be skipped when the FFI build isn't available to it.

#### Scenario: FFI update changes a notice
- **WHEN** a developer changes the FFI version that the package states and runs the script, and the new release adds a Rust crate
- **THEN** the package's `rust.md` contains the new crate's notice, and the diff of the change shows it

#### Scenario: HTML notice copied as text
- **WHEN** the FFI build has the notice file `licenses/rust-std.html`, and a developer runs the script
- **THEN** the package contains `rust-std.txt` with the notice's text without markup, and no `rust-std.html`

#### Scenario: Notice files out of date
- **WHEN** a preset's FFI build has a notice file that differs from the package's copy, or that the package doesn't contain, or the package contains a notice file that no preset's FFI build has
- **THEN** the package's tests fail and name the file

#### Scenario: No FFI build present
- **WHEN** the package's tests run where neither the release tarballs of the stated version nor, while the package states no release, a local build of the stated commit is available
- **THEN** the comparison test is skipped and the other tests run

#### Scenario: Commit without a release
- **WHEN** the package states an FFI commit and no release, and a developer builds the FFI locally at that commit and runs the script
- **THEN** the package's notice files equal the notice files of the local build's installs

#### Scenario: Local FFI build at another commit
- **WHEN** a developer builds the FFI locally at a commit other than the stated one
- **THEN** the notice files in the package don't change
