## MODIFIED Requirements

### Requirement: Base layer of a flutter_map map
The system SHALL provide a layer that an application places among the children of a `flutter_map` map. The layer SHALL display the map in the full viewport of the `flutter_map` map. Layers placed after it SHALL be drawn above it. The layer SHALL load the style it is given, create its map when it is inserted into the widget tree, and dispose the map when it is removed. When the application gives a layer that is in the tree a different style, the layer SHALL load the new style into the map it has, without creating another map. The layer SHALL report to the application each time a style has loaded.

#### Scenario: Map below overlays
- **WHEN** an application places the layer as the first child of a `flutter_map` map, followed by a marker layer and a polyline layer
- **THEN** the map fills the `flutter_map` viewport, and the markers and polylines are drawn above it

#### Scenario: Layer removed
- **WHEN** the layer is removed from the widget tree
- **THEN** its map is disposed, and repeating insert and remove 50 times doesn't increase thread count or memory use without bound

#### Scenario: Style loaded
- **WHEN** an application places the layer with a reachable style URL and a handler for loaded styles
- **THEN** the handler is called once after the style has loaded

#### Scenario: Style changed on a layer in the tree
- **WHEN** the style of a layer in the tree has loaded, and the application rebuilds the layer with a different style URL, as it does when the platform switches between light and dark mode
- **THEN** the map renders using the new style, the handler for loaded styles is called again, and the layer creates no other map

## ADDED Requirements

### Requirement: Failure reporting
The layer SHALL report each failure of its map to the application's failure handler, with a type that states the kind of failure and a message that describes the cause. The kinds SHALL be: loading the style or a resource it needs failed, rendering failed, and the map couldn't be created. When the map reports the same load failure again while it retries, the layer SHALL report it only once until the application gives a different style. When the application gives no failure handler, the layer SHALL report the failure through Flutter's error reporting, naming the package as the source. A failure SHALL NOT be thrown into the application's code, and the application SHALL continue to run.

#### Scenario: Style fails to load
- **WHEN** an application places the layer with an unreachable style URL and a failure handler
- **THEN** the handler receives a load failure with a message that describes the cause, and the application continues to run

#### Scenario: No failure handler
- **WHEN** an application places the layer with an unreachable style URL and no failure handler
- **THEN** Flutter's error reporting receives the load failure once, with the package named as the source, and the application continues to run

#### Scenario: Map can't be created
- **WHEN** creating the layer's map fails
- **THEN** the handler receives a creation failure, the layer occupies the viewport without drawing anything, and the overlays after it are still drawn
