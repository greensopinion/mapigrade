## MODIFIED Requirements

### Requirement: Exported names
The repository SHALL publish two packages, each with one public library:

- `package:mapigrade/mapigrade.dart`, for applications that display a MapLibre map without depending on `flutter_map`. It SHALL export exactly these names:
  - shared with `flutter_mapigrade`: `MapigradeController`, `MapigradeException`, `MapigradeLoadException`, `MapigradeRenderException`, `MapigradeCreateException`, `MapigradeQueryException`, `HttpHeaderRule`, `MapigradeMetrics`, `MapigradeMetricsSnapshot`, `QueriedFeature`, `MapigradePolyline`, `MapigradePolylineLayer` and `OverlayPlacement`;
  - for `MapigradeMap`: `MapigradeMap`, `Mapigrade`, `MapigradeCameraController`, `MapigradeCamera`, `CameraChange`, `CameraChangeSource`, `CameraTransitionOutcome`, `CameraLimits`, `GeoBounds`, `MapigradeGestures`, `MapigradeTap`, `MapigradeFrame`, `MapigradeMarkers`, `MapigradeMarker` and `MarkerAlignment`.
- `package:flutter_mapigrade/flutter_mapigrade.dart`, for applications that display the map in a `flutter_map` map. It SHALL export exactly `MapigradeLayer` and `LayerAlignment`, and the thirteen names that `mapigrade` shares with it, which it re-exports from `mapigrade`.

Every export directive of either library SHALL list the names it exports. Neither package SHALL contain another library outside `lib/src/`.

#### Scenario: Export namespace
- **WHEN** the API test of `mapigrade` resolves its main library
- **THEN** the names the library exports are exactly the twenty-eight names above, and each export directive lists the names it exports

#### Scenario: Export namespace of flutter_mapigrade
- **WHEN** the API test of `flutter_mapigrade` resolves its main library
- **THEN** the names the library exports are exactly the fifteen names above, and each of the thirteen shared names is the declaration that `mapigrade` exports

#### Scenario: Declaration added to an exported file
- **WHEN** a developer adds a top-level declaration to a source file that a main library exports from, without adding its name to that export's list
- **THEN** the name is not exported, and the API test passes

#### Scenario: No other public library
- **WHEN** the API test of each package lists the Dart files under `lib/` outside `lib/src/`
- **THEN** the only file is `lib/mapigrade.dart` in `mapigrade` and `lib/flutter_mapigrade.dart` in `flutter_mapigrade`

#### Scenario: Both packages imported
- **WHEN** an application imports both main libraries without a prefix or a `hide` combinator, and uses every shared name
- **THEN** the application compiles without an ambiguous import

### Requirement: Example uses the public library only
Each package SHALL include an example app that imports only the package's main library and runs on each supported platform. `packages/flutter_mapigrade/example/` SHALL display the map as the base layer of a `flutter_map` map with a marker above it. `packages/mapigrade/example/` SHALL display a `MapigradeMap` with a pitched initial camera and a `MapigradeMarker`, and SHALL NOT depend on `flutter_map`.

#### Scenario: Example imports
- **WHEN** the examples' Dart files are inspected
- **THEN** the `flutter_mapigrade` example imports `package:flutter_mapigrade/flutter_mapigrade.dart` and no other library of either package, and the `mapigrade` example imports `package:mapigrade/mapigrade.dart` and no other library of `mapigrade`

#### Scenario: Example runs
- **WHEN** each example is built and run on macOS, on the iOS simulator and on the Android emulator
- **THEN** on each platform the map appears below the marker, and the marker is at the coordinate it is placed at
