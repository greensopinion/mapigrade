## MODIFIED Requirements

### Requirement: Exported names
The package SHALL offer one public library, `package:flutter_mapigrade/flutter_mapigrade.dart`, for applications that display the map in a `flutter_map` map. It SHALL export exactly these names: `MapigradeLayer`, `LayerAlignment`, `LayerException`, `LayerLoadException`, `LayerRenderException`, `LayerCreateException`, `LayerQueryException`, `HttpHeaderRule`, `LayerMetrics`, `LayerMetricsSnapshot`, `LayerController` and `QueriedFeature`. Every export directive of the library SHALL list the names it exports. The package SHALL NOT contain another library outside `lib/src/`.

#### Scenario: Export namespace
- **WHEN** the package's API test resolves the main library
- **THEN** the names the library exports are exactly the twelve names above, and each export directive lists the names it exports

#### Scenario: Declaration added to an exported file
- **WHEN** a developer adds a top-level declaration to a source file that the main library exports from, without adding its name to that export's list
- **THEN** the name is not exported, and the API test passes

#### Scenario: No other public library
- **WHEN** the API test lists the Dart files under `lib/` outside `lib/src/`
- **THEN** the only file is `lib/flutter_mapigrade.dart`
