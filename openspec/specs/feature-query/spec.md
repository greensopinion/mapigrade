# feature-query Specification

## Purpose

Lets an application find the features that the map renders at a screen position or in a screen rectangle, such as the POI, trail or road the user tapped, and set per-feature state that the style reads, for example to highlight the feature the user tapped.

## Requirements

### Requirement: Layer controller
The package SHALL provide `LayerController`, which an application creates and gives to `MapigradeLayer` through its `controller` parameter. A controller SHALL be attached to at most one layer at a time: it is attached while a layer that was given it is in the tree, and detached when that layer is removed from the tree or rebuilt with another controller or none. Giving one controller to a second layer while it is attached SHALL fail an assertion in debug builds. A query or feature-state call on a controller that is detached, or whose layer has no map because the map is not created yet or couldn't be created, SHALL fail with a `StateError`; a query SHALL fail by completing its `Future` with the error, and a feature-state call SHALL throw it. A controller that is detached SHALL be attachable to a layer again.

#### Scenario: Query through the controller
- **WHEN** an application gives a controller to a `MapigradeLayer` whose map has displayed a frame, and calls a query on the controller
- **THEN** the query completes with the features of that layer's map

#### Scenario: Controller not attached
- **WHEN** an application calls a query on a controller that it hasn't given to a layer in the tree
- **THEN** the returned `Future` completes with a `StateError`

#### Scenario: Layer removed
- **WHEN** the layer that a controller is attached to is removed from the tree, and the application then calls a feature-state method on the controller
- **THEN** the call throws a `StateError`

#### Scenario: Controller moved to a new layer
- **WHEN** the application removes a layer and places a new layer with the same controller
- **THEN** queries on the controller return the features of the new layer's map

### Requirement: Query at a point
The controller SHALL provide a query at a point that returns the features that the displayed map frame draws within a radius of the point. The point SHALL be a logical position relative to the top-left corner of the `flutter_map` map widget, the coordinate space of `flutter_map`'s `TapPosition.relative`. The radius SHALL be in logical pixels, SHALL default to 8, and SHALL NOT be negative; a negative radius SHALL throw an `ArgumentError`. A feature SHALL be returned when its rendered shape intersects the square of side twice the radius, centered on the point and aligned with the screen axes.

#### Scenario: Tap on a road
- **WHEN** the camera is at rest and the application queries at the screen position of a road that the map draws, with the default radius
- **THEN** the result contains the road's feature

#### Scenario: Thin line within the radius
- **WHEN** the camera is at rest and the application queries at a point 6 logical pixels from a line that the style draws 1 logical pixel wide, with the default radius
- **THEN** the result contains the line's feature

#### Scenario: Line outside the radius
- **WHEN** the camera is at rest and the application queries at a point 6 logical pixels from a line that the style draws 1 logical pixel wide, with a radius of 2
- **THEN** the result doesn't contain the line's feature

### Requirement: Query in a screen rectangle
The controller SHALL provide a query in a rectangle that returns the features that the displayed map frame draws in the rectangle. The rectangle SHALL be given in the coordinate space of the requirement "Query at a point", with its edges aligned with the screen axes. A rectangle that extends past the viewport SHALL be clipped to the viewport. A rectangle that lies entirely outside the viewport SHALL return no features.

#### Scenario: Whole viewport
- **WHEN** the camera is at rest and the application queries a rectangle that covers the viewport
- **THEN** the result contains a feature of each style layer that draws something in the viewport and that the query doesn't exclude

#### Scenario: Rectangle outside the viewport
- **WHEN** the application queries a rectangle that lies entirely outside the viewport
- **THEN** the result is empty

### Requirement: Queries aligned with the displayed map frame
The system SHALL run each query against the features at the positions where the displayed map frame draws them, including while the camera moves, the map renders ahead of the displayed frame, camera prediction is on, or the map is pitched. The displayed map frame SHALL be the frame that the layer displayed in the last Flutter frame it built before the query was called. Before the map has displayed a frame, the system SHALL use the live `flutter_map` camera. For features that the style draws as lines, fills, circles or other non-symbol layers, the alignment SHALL be within 1 logical pixel. Symbol features (labels and icons) SHALL be matched where MapLibre placed them last, which can be behind the displayed frame while the camera moves.

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

#### Scenario: Pitched map
- **WHEN** the `flutter_map` pitch is 60 degrees, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line near the top of the viewport
- **THEN** the result contains the line's feature

### Requirement: Query options
Each query SHALL accept an optional list of style layer IDs and an optional filter. With a list, the query SHALL return only features drawn by those style layers; IDs that the style doesn't contain SHALL be ignored. The filter SHALL be a MapLibre style-spec filter expression given as a JSON value (lists, maps, strings, numbers, booleans and null), and the query SHALL return only features that match it. A filter that MapLibre rejects SHALL complete the query with a `LayerQueryException` whose message describes the cause.

#### Scenario: Layer IDs
- **WHEN** the application queries a rectangle that covers roads and POIs, with the style layer IDs of the POI layers only
- **THEN** the result contains POI features and no road features

#### Scenario: Filter
- **WHEN** the application queries with the filter `["==", ["get", "class"], "primary"]`
- **THEN** each returned feature has the property `class` with the value `primary`

#### Scenario: Invalid filter
- **WHEN** the application queries with the filter `["no-such-operator"]`
- **THEN** the query completes with a `LayerQueryException`

### Requirement: Query results
A query SHALL complete with a list of `QueriedFeature`, ordered as MapLibre returns them, with features of the topmost style layer first. Each `QueriedFeature` SHALL provide:

- `id`: the feature's ID as an `int`, a `double` or a `String`, or null when the feature has none;
- `properties`: the feature's properties, with values as `jsonDecode` returns them;
- `geometry`: the feature's geometry as a decoded GeoJSON geometry object;
- `sourceId`: the ID of the style source that contains the feature;
- `sourceLayerId`: the source layer that contains the feature, or null for a source without layers, such as a GeoJSON source;
- `state`: the feature's feature state, empty when none is set.

A query SHALL complete with an empty list when the map renders no feature at the position, including before the map has rendered a frame. Queries on one controller SHALL complete in the order the application called them. A query SHALL NOT block the Flutter UI thread while the map thread runs it, and decoding a large result SHALL NOT block the Flutter UI thread for longer than decoding a small one.

#### Scenario: Feature of a vector source
- **WHEN** the application queries at a POI of a vector tile source
- **THEN** the result's feature has the POI's properties, a GeoJSON `Point` geometry, the source's ID as `sourceId`, and the tile's layer name as `sourceLayerId`

#### Scenario: Feature of a GeoJSON source
- **WHEN** the application queries at a line of a GeoJSON source
- **THEN** the result's feature has the line's properties and ID, a GeoJSON `LineString` or `MultiLineString` geometry, and a null `sourceLayerId`

#### Scenario: Nothing rendered there
- **WHEN** the application queries at a position where the map draws only the background
- **THEN** the result is empty, unless the query includes a style layer that draws there

#### Scenario: Order of completion
- **WHEN** the application calls a rectangle query that covers the viewport and then a point query, without waiting
- **THEN** the rectangle query completes first

### Requirement: Feature state
The controller SHALL provide a method that sets feature state on one feature, and a method that removes feature state. The feature SHALL be selected by its source ID, its source-layer ID for a source with layers, and its ID. Setting state SHALL merge the given keys into the feature's state. The application SHALL be able to remove one key of a feature, all state of a feature, or all state of a source or source layer. An ID SHALL be an `int`, a `double` with an integral value, or a `String`, and an integral value SHALL select the same feature whether it is given as an `int` or a `double`. A null ID, a `double` ID that isn't integral, an empty source ID, or a state that isn't a JSON object SHALL throw an `ArgumentError`, and the message for a null ID SHALL state that the source's `promoteId` can give features IDs. State SHALL be a JSON object: a map with string keys and JSON values. The methods SHALL return without waiting for the map. A later displayed map frame SHALL show the effect of the change on the style's `feature-state` expressions, and a later query SHALL return the changed state. Feature state SHALL belong to the layer's map, not to its style: when the application gives the layer a different style, the state SHALL be kept, and SHALL apply to the features of the new style that have the same source ID, source-layer ID and ID. The documentation of the feature-state methods SHALL state this.

#### Scenario: Highlight a tapped feature
- **WHEN** the style draws a road layer with a color that depends on `["feature-state", "selected"]`, the application queries at a road, and sets `{"selected": true}` on the returned feature with its `sourceId`, `sourceLayerId` and `id`
- **THEN** a later displayed map frame draws that road in the selected color, and other roads in the default color

#### Scenario: Remove the highlight
- **WHEN** the application removes the key `selected` from the feature of the previous scenario
- **THEN** a later displayed map frame draws the road in the default color

#### Scenario: Query returns state
- **WHEN** the application has set `{"selected": true}` on a feature, and then queries at that feature
- **THEN** the returned feature's `state` contains `selected` with the value `true`

#### Scenario: Integral ID as a double
- **WHEN** a query returns a feature whose `id` is `42`, and the application sets state with the ID `42.0`
- **THEN** the state applies to that feature

#### Scenario: Feature without an ID
- **WHEN** the application sets state with a null ID
- **THEN** the call throws an `ArgumentError` whose message mentions `promoteId`

#### Scenario: State kept when switching from a dark to a light style
- **WHEN** the application has set `{"selected": true}` on a road in a dark style, and then, as it does when the platform switches from dark to light mode, gives the layer a light variant of the style with the same sources and a road layer whose color depends on `["feature-state", "selected"]`
- **THEN** after the new style has loaded, a displayed map frame draws that road in the selected color, and a query at the road returns `selected` with the value `true` in its `state`

#### Scenario: Remove all state of a source layer
- **WHEN** the application has set state on several features of a source layer, and removes state with only the source ID and the source-layer ID
- **THEN** a later query returns those features with empty `state`
