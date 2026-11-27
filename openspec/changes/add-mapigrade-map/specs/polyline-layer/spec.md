## MODIFIED Requirements

### Requirement: Polyline layer in the children of the map layer
The package SHALL provide `MapigradePolylineLayer`, a widget that takes a list of `MapigradePolyline` values and a placement. An application SHALL place it among the `children` of a `MapigradeLayer` or of a `MapigradeMap`, at any depth below a child. The polyline layer SHALL give its polylines to that widget's map, and the map SHALL draw them in the map frames it renders, so that the polylines are drawn exactly where the displayed map frame draws their coordinates, including while the camera moves. The polyline layer SHALL draw nothing in Flutter. A polyline layer that isn't below a `MapigradeLayer` or a `MapigradeMap` SHALL fail an assertion in debug builds and draw nothing in release builds. When that widget has no map, because the map isn't created yet or couldn't be created, the polyline layer SHALL NOT throw; when the map is created, it SHALL draw the polylines that the polyline layer has then.

#### Scenario: Route drawn by the map
- **WHEN** an application places a polyline layer with one polyline in the children of a `MapigradeLayer`, and the camera is at rest
- **THEN** the displayed map frame draws the polyline at the screen positions of its points, within 1 logical pixel

#### Scenario: Pan with polylines
- **WHEN** the `flutter_map` camera pans at 1,000 logical px/s
- **THEN** in each displayed map frame the polyline is drawn at the screen positions of its points in that frame, within 1 logical pixel

#### Scenario: Polyline layer inside another widget
- **WHEN** an application places a polyline layer inside a `ValueListenableBuilder` that is a child of a `MapigradeLayer`
- **THEN** the map draws the polylines of the polyline layer

#### Scenario: Polyline layer outside a map layer
- **WHEN** an application places a polyline layer directly among the children of a `flutter_map` map in a debug build
- **THEN** an assertion fails that states that the polyline layer must be below a `MapigradeLayer` or a `MapigradeMap`

#### Scenario: Polylines given before the map exists
- **WHEN** an application places a `MapigradeLayer` with a polyline layer in its children, and the map is created after the polyline layer was built
- **THEN** the map draws the polylines when the style has loaded

#### Scenario: Route in a MapigradeMap
- **WHEN** an application places a polyline layer with one polyline in the children of a `MapigradeMap` with pitch 45, and the camera is at rest
- **THEN** the displayed map frame draws the polyline at the screen positions of its points, within 1 logical pixel

## ADDED Requirements

### Requirement: Polylines in MapigradeMap
The requirements of this capability that name `MapigradeLayer`, its `children`, its style or its failure handler SHALL apply in the same way to `MapigradeMap`, its `children`, its style and its failure handler.

#### Scenario: Order in a MapigradeMap
- **WHEN** a `MapigradeMap` has two polyline layers in its children at the default placement, the first with a red polyline and the second with a blue polyline that crosses it
- **THEN** the crossing is blue

#### Scenario: Missing placement layer in a MapigradeMap
- **WHEN** a polyline layer in a `MapigradeMap` has the placement `OverlayPlacement.belowLayer('road-label')` and the style has no layer with that ID
- **THEN** the polylines are drawn above all style layers, and the map's failure callback receives one `MapigradeLoadException` that names `road-label`
