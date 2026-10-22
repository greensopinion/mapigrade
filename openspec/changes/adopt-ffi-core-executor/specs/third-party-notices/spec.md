## MODIFIED Requirements

### Requirement: Notices equal to the FFI build
The notice files of the MapLibre Native FFI are the files that the release tarballs of the FFI version the package states contain as `share/maplibre-native-c/LICENSE` and in `share/maplibre-native-c/licenses/`, for the presets whose libraries applications built with the package contain. Other files in `share/maplibre-native-c/`, such as `artifact.json`, are not notice files. The notice files in the package SHALL be byte-identical to the notice files of that release, and the package SHALL contain one for every notice file of every such preset. A script SHALL update the notice files in the package from the release. A test SHALL fail when a notice file in the package differs from, or is missing for, a notice file of the release, and SHALL be skipped when the release tarballs aren't available to it. While the package states the FFI snapshot, the notice files in the package SHALL stay those of the last FFI release that the package stated, and the test SHALL be skipped.

#### Scenario: FFI update changes a notice
- **WHEN** a developer changes the FFI version that the package states and runs the script, and the new release adds a Rust crate
- **THEN** the package's `rust.md` contains the new crate's notice, and the diff of the change shows it

#### Scenario: Notice files out of date
- **WHEN** a release tarball of the stated version has a notice file that differs from the package's copy, or that the package doesn't contain
- **THEN** the package's tests fail and name the file

#### Scenario: No FFI build present
- **WHEN** the package's tests run where the release tarballs of the stated version aren't available
- **THEN** the comparison test is skipped and the other tests run

#### Scenario: Local FFI build at another commit
- **WHEN** a developer builds the FFI locally at a commit other than the stated release's
- **THEN** the notice files in the package don't change

#### Scenario: Package states the snapshot
- **WHEN** the package's FFI changes from a release to the snapshot, and the package's tests run
- **THEN** the notice files in the package don't change, and the comparison test is skipped
