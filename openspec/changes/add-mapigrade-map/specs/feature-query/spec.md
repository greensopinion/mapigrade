## MODIFIED Requirements

### Requirement: Map controller
`mapigrade` SHALL provide `MapigradeController`, which controls everything about a map except its camera: in this version, the feature queries and the feature state. An application creates it and gives it to `MapigradeLayer` or to `MapigradeMap` through its `controller` parameter. A `MapigradeMap` SHALL take it alongside a `MapigradeCameraController`, without either controller extending the other. A controller SHALL be attached to at most one map widget at a time: it is attached while a widget that was given it is in the tree, and detached when that widget is removed from the tree or rebuilt with another controller or none. Giving one controller to a second widget while it is attached SHALL fail an assertion in debug builds. A query or feature-state call on a controller that is detached, or whose widget has no map because the map is not created yet or couldn't be created, SHALL fail with a `StateError`; a query SHALL fail by completing its `Future` with the error, and a feature-state call SHALL throw it. A controller that is detached SHALL be attachable to a widget again.

#### Scenario: Query through the controller
- **WHEN** an application gives a controller to a `MapigradeLayer` whose map has displayed a frame, and calls a query on the controller
- **THEN** the query completes with the features of that layer's map

#### Scenario: Controller not attached
- **WHEN** an application calls a query on a controller that it hasn't given to a widget in the tree
- **THEN** the returned `Future` completes with a `StateError`

#### Scenario: Layer removed
- **WHEN** the layer that a controller is attached to is removed from the tree, and the application then calls a feature-state method on the controller
- **THEN** the call throws a `StateError`

#### Scenario: Controller moved to a new layer
- **WHEN** the application removes a layer and places a new layer with the same controller
- **THEN** queries on the controller return the features of the new layer's map

#### Scenario: Query through the controller of a MapigradeMap
- **WHEN** an application gives a controller to a `MapigradeMap` whose map has displayed a frame, and calls a query on the controller
- **THEN** the query completes with the features of that map

### Requirement: Query at a point
The controller SHALL provide a query at a point that returns the features that the displayed map frame draws within a radius of the point. The point SHALL be a logical position relative to the top-left corner of the widget that displays the map: for `MapigradeLayer` the `flutter_map` map widget, the coordinate space of `flutter_map`'s `TapPosition.relative`, and for `MapigradeMap` the `MapigradeMap` widget, the coordinate space of `MapigradeTap.position`. The radius SHALL be in logical pixels, SHALL default to 8, and SHALL NOT be negative; a negative radius SHALL throw an `ArgumentError`. A feature SHALL be returned when its rendered shape intersects the square of side twice the radius, centered on the point and aligned with the screen axes.

#### Scenario: Tap on a road
- **WHEN** the camera is at rest and the application queries at the screen position of a road that the map draws, with the default radius
- **THEN** the result contains the road's feature

#### Scenario: Thin line within the radius
- **WHEN** the camera is at rest and the application queries at a point 6 logical pixels from a line that the style draws 1 logical pixel wide, with the default radius
- **THEN** the result contains the line's feature

#### Scenario: Line outside the radius
- **WHEN** the camera is at rest and the application queries at a point 6 logical pixels from a line that the style draws 1 logical pixel wide, with a radius of 2
- **THEN** the result doesn't contain the line's feature

#### Scenario: Query at a tap on a MapigradeMap
- **WHEN** the camera of a `MapigradeMap` is at rest with pitch 45, the user taps a road, and the application queries at the tap's position with the default radius
- **THEN** the result contains the road's feature

### Requirement: Queries aligned with the displayed map frame
The system SHALL run each query against the features at the positions where the displayed map frame draws them, including while the camera moves, the map renders ahead of the displayed frame, or camera prediction is on. The displayed map frame SHALL be the frame that the widget displayed in the last Flutter frame it built before the query was called. Before the map has displayed a frame, the system SHALL use the live `flutter_map` camera for `MapigradeLayer`, and the initial camera for `MapigradeMap`. For features that the style draws as lines, fills, circles or other non-symbol layers, the alignment SHALL be within 1 logical pixel. Symbol features (labels and icons) SHALL be matched where MapLibre placed them last, which can be behind the displayed frame while the camera moves.

#### Scenario: Query during a pan
- **WHEN** the `flutter_map` camera pans at 1,000 logical px/s, and in a Flutter frame the application queries with a radius of 2 at the screen position where the displayed map frame draws a line that the style draws 1 logical pixel wide
- **THEN** the result contains the line's feature

#### Scenario: Query beside a line during a pan
- **WHEN** the `flutter_map` camera pans at 1,000 logical px/s, and in a Flutter frame the application queries with a radius of 2 at a point 6 logical pixels from where the displayed map frame draws a line that the style draws 1 logical pixel wide
- **THEN** the result doesn't contain the line's feature

#### Scenario: Query with camera prediction
- **WHEN** the layer has camera prediction on with a lead of 1, the camera pans at 1,000 logical px/s, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line
- **THEN** the result contains the line's feature

#### Scenario: Rotated and zooming camera
- **WHEN** the `flutter_map` rotation is 30 degrees, the camera zooms in continuously, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line
- **THEN** the result contains the line's feature

#### Scenario: Antimeridian
- **WHEN** the camera pans across the antimeridian, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line
- **THEN** the result contains the line's feature

#### Scenario: Query during a pan of a MapigradeMap
- **WHEN** the user pans a `MapigradeMap` with pitch 45, and in a Flutter frame the application queries with a radius of 2 at the screen position where the displayed map frame draws a line that the style draws 1 logical pixel wide
- **THEN** the result contains the line's feature
