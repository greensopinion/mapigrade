## RENAMED Requirements

- FROM: `### Requirement: Layer controller`
- TO: `### Requirement: Map controller`

## MODIFIED Requirements

### Requirement: Map controller
`mapigrade` SHALL provide `MapigradeController`, which controls everything about a map except its camera: in this version, the feature queries and the feature state. An application creates it and gives it to `MapigradeLayer` through its `controller` parameter. A controller SHALL be attached to at most one map widget at a time: it is attached while a widget that was given it is in the tree, and detached when that widget is removed from the tree or rebuilt with another controller or none. Giving one controller to a second widget while it is attached SHALL fail an assertion in debug builds. A query or feature-state call on a controller that is detached, or whose widget has no map because the map is not created yet or couldn't be created, SHALL fail with a `StateError`; a query SHALL fail by completing its `Future` with the error, and a feature-state call SHALL throw it. A controller that is detached SHALL be attachable to a widget again.

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

### Requirement: Query options
Each query SHALL accept an optional list of style layer IDs and an optional filter. With a list, the query SHALL return only features drawn by those style layers; IDs that the style doesn't contain SHALL be ignored. The filter SHALL be a MapLibre style-spec filter expression given as a JSON value (lists, maps, strings, numbers, booleans and null), and the query SHALL return only features that match it. A filter that MapLibre rejects SHALL complete the query with a `MapigradeQueryException` whose message describes the cause.

#### Scenario: Layer IDs
- **WHEN** the application queries a rectangle that covers roads and POIs, with the style layer IDs of the POI layers only
- **THEN** the result contains POI features and no road features

#### Scenario: Filter
- **WHEN** the application queries with the filter `["==", ["get", "class"], "primary"]`
- **THEN** each returned feature has the property `class` with the value `primary`

#### Scenario: Invalid filter
- **WHEN** the application queries with the filter `["no-such-operator"]`
- **THEN** the query completes with a `MapigradeQueryException`
