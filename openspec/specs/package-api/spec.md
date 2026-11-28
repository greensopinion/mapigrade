# package-api Specification

## Purpose

Defines the Dart API that the package offers to applications: which names the main library exports, the rule for naming them, how applications may use the exported types, and how the package's own tests reach internal code without making it API.

## Requirements

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

### Requirement: Naming rule for exported names
Names that `flutter_mapigrade`'s main library exports, including the names it re-exports from `mapigrade`, SHALL NOT start with `Map`, `Camera`, `Tile`, `Marker`, `Polyline` or `Polygon`, except names that start with `Mapigrade`, and SHALL NOT equal a name exported by `package:flutter_map/flutter_map.dart`. Names that either main library exports SHALL NOT equal a name exported by `package:latlong2/latlong.dart`, `package:flutter/widgets.dart` or `package:flutter/material.dart`. The libraries are checked at the versions each package resolves. Names that a package doesn't export MAY equal names in those libraries.

#### Scenario: Exported name breaks the rule
- **WHEN** `flutter_mapigrade`'s main library exports a name that starts with one of the listed words and not with `Mapigrade`, or that equals a name exported by one of the listed libraries
- **THEN** the API test of `flutter_mapigrade` fails and states the name and the rule it breaks

#### Scenario: mapigrade export equals a widgets name
- **WHEN** `mapigrade`'s main library exports a name that equals a name exported by `latlong2`, `flutter/widgets` or `flutter/material`
- **THEN** the API test of `mapigrade` fails and states the name and the library

#### Scenario: mapigrade-only name with a listed prefix
- **WHEN** `mapigrade`'s main library exports a name that starts with `Camera`, that `flutter_mapigrade` doesn't re-export, and that equals no name of `latlong2`, `flutter/widgets` or `flutter/material`
- **THEN** the API tests of both packages pass

#### Scenario: Name with the Mapigrade prefix
- **WHEN** a main library exports `MapigradePolyline`
- **THEN** the API test passes

#### Scenario: Internal name equals a flutter_map name
- **WHEN** a library under `lib/src/` declares a name that `flutter_map` also exports, and no main library exports it
- **THEN** the API tests pass

#### Scenario: Application imports without hiding names
- **WHEN** an application imports `flutter_mapigrade`'s main library, `flutter_map`, `latlong2` and `flutter/material.dart` without a prefix or a `hide` combinator, and uses every name the main library exports
- **THEN** the application compiles without an ambiguous import

### Requirement: Exported types are closed to applications
Applications SHALL NOT be able to extend, implement or mix in a type that either main library exports. The packages MAY add members to exported types, and subclasses of `MapigradeException`, without breaking an application that compiled before. Neither package SHALL extend, implement or mix in a type that the other package declares.

#### Scenario: Application extends an exported type
- **WHEN** application code declares a class that extends or implements `MapigradeLayer`, `LayerAlignment`, `MapigradeController` or `MapigradeException`
- **THEN** the code doesn't compile

#### Scenario: A new kind of failure
- **WHEN** a later version of `mapigrade` adds a subclass of `MapigradeException`
- **THEN** application code that switches over the type of a `MapigradeException` must already handle other types, so it compiles and runs unchanged

### Requirement: Internal library for the package's tests
Each package SHALL provide what its test harness and tests need, and the main library doesn't export, through one library under `lib/src/`: `mapigrade` the map controller, the view and the test hooks, and `flutter_mapigrade` the internal layer widget and the measurement helpers of the layer. These libraries SHALL NOT be API: the naming rule doesn't apply to them, and they MAY change in any version. The test harness SHALL import each package's internals only through that package's one library.

#### Scenario: Test harness imports internals
- **WHEN** the test harness needs the map controller, the internal layer widget, a test hook or a measurement helper
- **THEN** it imports `package:mapigrade/src/testing.dart` or `package:flutter_mapigrade/src/testing.dart`, and no other library under `src/` of either package

### Requirement: Example uses the public library only
Each package SHALL include an example app that imports only the package's main library and runs on each supported platform. `packages/flutter_mapigrade/example/` SHALL display the map as the base layer of a `flutter_map` map with a marker above it. `packages/mapigrade/example/` SHALL display a `MapigradeMap` with a pitched initial camera and a `MapigradeMarker`, and SHALL NOT depend on `flutter_map`.

#### Scenario: Example imports
- **WHEN** the examples' Dart files are inspected
- **THEN** the `flutter_mapigrade` example imports `package:flutter_mapigrade/flutter_mapigrade.dart` and no other library of either package, and the `mapigrade` example imports `package:mapigrade/mapigrade.dart` and no other library of `mapigrade`

#### Scenario: Example runs
- **WHEN** each example is built and run on macOS, on the iOS simulator and on the Android emulator
- **THEN** on each platform the map appears below the marker, and the marker is at the coordinate it is placed at

### Requirement: Integration library for flutter_mapigrade
`mapigrade` SHALL provide what `flutter_mapigrade` needs and `mapigrade`'s main library doesn't export, such as the map controller that the internal layer widget drives and attaching a `MapigradeController` to a map, through one library under `lib/src/`. That library SHALL NOT be API: the naming rule doesn't apply to it, it MAY change in any version, and `mapigrade`'s README SHALL state that applications must not import it. `flutter_mapigrade` SHALL import `mapigrade`'s internals only through that library, and SHALL depend on `mapigrade` with the range from its own version to the next patch version, such as `>=0.2.0 <0.2.1`, which allows no other release of `mapigrade`. Both packages SHALL always have the same version.

#### Scenario: flutter_mapigrade imports mapigrade internals
- **WHEN** the Dart files of `flutter_mapigrade` under `lib/` are inspected
- **THEN** they import `package:mapigrade/mapigrade.dart` and `package:mapigrade/src/integration.dart`, and no other library of `mapigrade`

#### Scenario: Version constraint
- **WHEN** `flutter_mapigrade`'s `pubspec.yaml` is read
- **THEN** its constraint on `mapigrade` is the range from the version of `flutter_mapigrade` to the next patch version, and the version of `mapigrade` equals the version of `flutter_mapigrade`

#### Scenario: Versions disagree
- **WHEN** the version of either package, or `flutter_mapigrade`'s constraint on `mapigrade`, differs from the others
- **THEN** a unit test fails and names the value that differs
