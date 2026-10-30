## MODIFIED Requirements

### Requirement: Base layer of a flutter_map map
The system SHALL provide a layer that an application places among the children of a `flutter_map` map. The layer SHALL display the map in the full viewport of the `flutter_map` map. Layers placed after it SHALL be drawn above it. The layer SHALL accept an optional list of child widgets, typically `flutter_map` layers, and SHALL draw them above the map, in list order, in the full viewport, as the requirement "Children aligned with the displayed map frame" describes. A `MapigradePolylineLayer` in the children SHALL instead have its polylines drawn in the map, among the style's layers, as the `polyline-layer` capability describes, and so below every child that Flutter draws, whatever its position in the list. The layer SHALL load the style it is given, create its map when it is inserted into the widget tree, and dispose the map when it is removed. When the application gives a layer that is in the tree a different style, the layer SHALL load the new style into the map it has, without creating another map. The layer SHALL report to the application each time a style has loaded.

#### Scenario: Map below overlays
- **WHEN** an application places the layer as the first child of a `flutter_map` map, followed by a marker layer and a polyline layer
- **THEN** the map fills the `flutter_map` viewport, and the markers and polylines are drawn above it

#### Scenario: Map below its children
- **WHEN** an application places the layer with a polyline layer and a marker layer as its children
- **THEN** the map fills the `flutter_map` viewport, the polylines are drawn above the map, and the markers above the polylines

#### Scenario: Map polylines below Flutter children
- **WHEN** an application places the layer with a marker layer followed by a `MapigradePolylineLayer` as its children, and a polyline passes under a marker
- **THEN** the marker is drawn above the polyline

#### Scenario: Layer removed
- **WHEN** the layer is removed from the widget tree
- **THEN** its map is disposed, and repeating insert and remove 50 times doesn't increase thread count or memory use without bound

#### Scenario: Style loaded
- **WHEN** an application places the layer with a reachable style URL and a handler for loaded styles
- **THEN** the handler is called once after the style has loaded

#### Scenario: Style changed on a layer in the tree
- **WHEN** the style of a layer in the tree has loaded, and the application rebuilds the layer with a different style URL, as it does when the platform switches between light and dark mode
- **THEN** the map renders using the new style, the handler for loaded styles is called again, and the layer creates no other map
