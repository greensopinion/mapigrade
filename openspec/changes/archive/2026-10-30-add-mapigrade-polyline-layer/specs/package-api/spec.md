## MODIFIED Requirements

### Requirement: Exported names
The package SHALL offer one public library, `package:flutter_mapigrade/flutter_mapigrade.dart`, for applications that display the map in a `flutter_map` map. It SHALL export exactly these names: `MapigradeLayer`, `LayerAlignment`, `LayerException`, `LayerLoadException`, `LayerRenderException`, `LayerCreateException`, `LayerQueryException`, `HttpHeaderRule`, `LayerMetrics`, `LayerMetricsSnapshot`, `LayerController`, `QueriedFeature`, `MapigradePolyline`, `MapigradePolylineLayer` and `LayerPlacement`. Every export directive of the library SHALL list the names it exports. The package SHALL NOT contain another library outside `lib/src/`.

#### Scenario: Export namespace
- **WHEN** the package's API test resolves the main library
- **THEN** the names the library exports are exactly the fifteen names above, and each export directive lists the names it exports

#### Scenario: Declaration added to an exported file
- **WHEN** a developer adds a top-level declaration to a source file that the main library exports from, without adding its name to that export's list
- **THEN** the name is not exported, and the API test passes

#### Scenario: No other public library
- **WHEN** the API test lists the Dart files under `lib/` outside `lib/src/`
- **THEN** the only file is `lib/flutter_mapigrade.dart`

### Requirement: Naming rule for exported names
Exported names SHALL NOT start with `Map`, `Camera`, `Tile`, `Marker`, `Polyline` or `Polygon`, except names that start with `Mapigrade`. No exported name SHALL equal a name exported by `package:flutter_map/flutter_map.dart`, `package:latlong2/latlong.dart`, `package:flutter/widgets.dart` or `package:flutter/material.dart`, at the versions the package resolves. Names that the package doesn't export MAY equal names in those libraries.

#### Scenario: Exported name breaks the rule
- **WHEN** the main library exports a name that starts with one of the listed words and not with `Mapigrade`, or that equals a name exported by one of the listed libraries
- **THEN** the API test fails and states the name and the rule it breaks

#### Scenario: Name with the Mapigrade prefix
- **WHEN** the main library exports `MapigradePolyline`
- **THEN** the API test passes

#### Scenario: Internal name equals a flutter_map name
- **WHEN** a library under `lib/src/` declares a name that `flutter_map` also exports, and the main library doesn't export it
- **THEN** the API test passes

#### Scenario: Application imports without hiding names
- **WHEN** an application imports the main library, `flutter_map`, `latlong2` and `flutter/material.dart` without a prefix or a `hide` combinator, and uses every name the main library exports
- **THEN** the application compiles without an ambiguous import
