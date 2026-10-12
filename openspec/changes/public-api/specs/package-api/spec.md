## Purpose

Defines the Dart API that the package offers to applications: which names the main library exports, the rule for naming them, how applications may use the exported types, and how the package's own tests reach internal code without making it API.

## ADDED Requirements

### Requirement: Exported names
The package SHALL offer one public library, `package:flutter_mapigrade/flutter_mapigrade.dart`, for applications that display the map in a `flutter_map` map. It SHALL export exactly these names: `MapigradeLayer`, `LayerAlignment`, `LayerException`, `LayerLoadException`, `LayerRenderException` and `LayerCreateException`. Every export directive of the library SHALL list the names it exports. The package SHALL NOT contain another library outside `lib/src/`.

#### Scenario: Export namespace
- **WHEN** the package's API test resolves the main library
- **THEN** the names the library exports are exactly the six names above, and each export directive lists the names it exports

#### Scenario: Declaration added to an exported file
- **WHEN** a developer adds a top-level declaration to a source file that the main library exports from, without adding its name to that export's list
- **THEN** the name is not exported, and the API test passes

#### Scenario: No other public library
- **WHEN** the API test lists the Dart files under `lib/` outside `lib/src/`
- **THEN** the only file is `lib/flutter_mapigrade.dart`

### Requirement: Naming rule for exported names
Exported names SHALL NOT start with `Map`, `Camera`, `Tile`, `Marker`, `Polyline` or `Polygon`, except the name of the layer, `MapigradeLayer`. No exported name SHALL equal a name exported by `package:flutter_map/flutter_map.dart`, `package:latlong2/latlong.dart`, `package:flutter/widgets.dart` or `package:flutter/material.dart`, at the versions the package resolves. Names that the package doesn't export MAY equal names in those libraries.

#### Scenario: Exported name breaks the rule
- **WHEN** the main library exports a name that starts with one of the listed words, other than `MapigradeLayer`, or that equals a name exported by one of the listed libraries
- **THEN** the API test fails and states the name and the rule it breaks

#### Scenario: Internal name equals a flutter_map name
- **WHEN** a library under `lib/src/` declares a name that `flutter_map` also exports, and the main library doesn't export it
- **THEN** the API test passes

#### Scenario: Application imports without hiding names
- **WHEN** an application imports the main library, `flutter_map`, `latlong2` and `flutter/material.dart` without a prefix or a `hide` combinator, and uses every name the main library exports
- **THEN** the application compiles without an ambiguous import

### Requirement: Exported types are closed to applications
Applications SHALL NOT be able to extend, implement or mix in a type that the main library exports. The package MAY add members to exported types, and subclasses of `LayerException`, without breaking an application that compiled before.

#### Scenario: Application extends an exported type
- **WHEN** application code declares a class that extends or implements `MapigradeLayer`, `LayerAlignment` or `LayerException`
- **THEN** the code doesn't compile

#### Scenario: A new kind of failure
- **WHEN** a later version of the package adds a subclass of `LayerException`
- **THEN** application code that switches over the type of a `LayerException` must already handle other types, so it compiles and runs unchanged

### Requirement: Internal library for the package's tests
The package SHALL provide the controller, the view, the internal layer widget, the test hooks and the measurement helpers that its test harness and tests need through one library under `lib/src/`. That library SHALL NOT be API: the naming rule doesn't apply to it, and it MAY change in any version. The test harness SHALL import it only through that one library.

#### Scenario: Test harness imports internals
- **WHEN** the test harness needs the map controller, the internal layer widget or a test hook
- **THEN** it imports `package:flutter_mapigrade/src/testing.dart`, and no other library under `package:flutter_mapigrade/src/`

### Requirement: Example uses the public library only
The package SHALL include an example app in `packages/flutter_mapigrade/example/` that displays the map as the base layer of a `flutter_map` map with a marker above it. The example SHALL import only the main library of the package, and SHALL run on each supported platform.

#### Scenario: Example imports
- **WHEN** the example's Dart files are inspected
- **THEN** they import `package:flutter_mapigrade/flutter_mapigrade.dart` and no other library of the package

#### Scenario: Example runs
- **WHEN** the example is built and run on macOS, on an iPhone and on an Android device
- **THEN** on each platform the map appears below the marker, and the marker is at the coordinate it is placed at
