## MODIFIED Requirements

### Requirement: Polylines
The polyline screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming and rotating enabled. When the screen opens, the map SHALL show downtown New York in Liberty at zoom 16, with the camera over the Financial District. The screen SHALL draw these routes with one `MapigradePolylineLayer` in the layer's children, each along the streets or the water it names:

- a solid route along Broadway from Bowling Green to City Hall Park, with a border;
- a dashed route of the Staten Island Ferry from the Whitehall Terminal into the Upper Bay;
- a route along West Street from the Battery to Chambers Street, with a gradient from its start to its end;
- a route along Wall Street with a width in meters, which gets wider on the screen as the map zooms in.

The screen SHALL have a control that chooses the routes' placement: "Below buildings and labels", which is `OverlayPlacement.belowLabels()` and is chosen when the screen opens, and "On top", which is `OverlayPlacement.top()`. The screen SHALL offer the styles of the requirement "Styles", and choosing another style SHALL keep the camera, the routes and the chosen placement. The screen SHALL show a legend that names each route and how it is drawn.

#### Scenario: Open the polyline screen
- **WHEN** the developer chooses "Polylines" in the gallery
- **THEN** the map shows the Financial District in Liberty with its 3D buildings and the four routes, and the placement "Below buildings and labels" is chosen

#### Scenario: Buildings hide the routes
- **WHEN** the placement is "Below buildings and labels" and a tall building stands beside Broadway on the screen
- **THEN** the building hides the part of the route that it stands in front of, and street labels are drawn above the routes

#### Scenario: Routes on top
- **WHEN** the developer chooses "On top"
- **THEN** the routes are drawn above the buildings and the labels, and no building or label hides any part of them

#### Scenario: Width in meters
- **WHEN** the developer zooms in from zoom 16 to zoom 18
- **THEN** the Wall Street route is about four times as wide on the screen, and the other routes keep their width

#### Scenario: Change style on the polyline screen
- **WHEN** the placement is "On top" and the developer chooses Positron
- **THEN** the map shows Positron with the camera where it was, the four routes are drawn, and the placement is still "On top"

### Requirement: Metrics display
The demo SHALL display, updated once per second: the map's displayed frames per second, the map's rendered frames per second, the map's average render time per rendered frame in milliseconds, and the Flutter UI frames per second. The map values SHALL come from two consecutive snapshots of one `MapigradeMetrics` given to the layer: each rate is the difference of the count divided by the difference of the time. The average render time SHALL be the difference of the render time divided by the difference of the rendered frames, and SHALL be shown as unavailable when no frame was rendered in the interval. The UI rate SHALL come from the frame timings that Flutter reports. The display SHALL state that the map renders no frames while it is at rest.

#### Scenario: Camera moves
- **WHEN** the developer drags the map continuously for several seconds
- **THEN** the displayed and rendered frame rates and the average render time are shown and change from one second to the next

#### Scenario: Map at rest
- **WHEN** the map has loaded its tiles and the camera hasn't moved for a second
- **THEN** the displayed and rendered frame rates are 0, the average render time is shown as unavailable, and the display states that the map is at rest

### Requirement: Inspect features
The inspect screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming and rotating enabled. A tap on the map SHALL query the features that the style's own layers draw at the tap, with `MapigradeController`'s query at a point and its default radius, and SHALL select a feature of the topmost style layer that draws a feature at the tap; the highlight layers of the requirement "Inspect highlight" SHALL NOT be queried. Among the features of that layer, the demo SHALL select the first that the query returns. The selection SHALL NOT depend on the order in which MapLibre returns the features of several layers, because MapLibre Native doesn't return them in style order (`docs/upstream-fixes/maplibre-query-result-order.md`). The screen SHALL show a panel that states the ID of the style layer that draws the selected feature, and the feature's source ID, source-layer ID, ID, geometry type, number of parts for a multi geometry, its feature state, and properties, with the properties as key and value rows sorted by key. After it sets the feature state of a newly selected feature, the demo SHALL query the selected feature's style layer again at the tap and show the feature state that this query returns, so that the panel shows `selected: true` without a second tap. For a feature of a symbol layer, the panel SHALL state that MapLibre Native doesn't return feature state for labels and icons (`docs/upstream-fixes/maplibre-symbol-query-feature-state.md`) in place of the state. Below the selected feature, the panel SHALL list the other features at the tap, topmost style layer first, each with its style layer ID, source-layer ID and ID. Choosing an entry of the list SHALL select that feature as a tap selects one, and the list SHALL then contain the other features of the same tap, including the feature that was selected before. The demo SHALL deselect the feature that was selected before by setting its feature state `selected: false`, not by removing the state, because MapLibre Native drops one of the changes when a removal and a change in one source layer arrive before the same render (`docs/upstream-fixes/maplibre-feature-state-coalescing.md`). When the newly selected feature has an ID, the demo SHALL then set the feature state `selected: true` on it. When it has no ID, the panel SHALL state that the feature has no ID and so can't be highlighted. A tap where the query returns no feature SHALL deselect the feature that was selected before and clear the panel. A query that fails SHALL show the failure's message and keep the selection. The screen SHALL state that a tap selects the topmost feature.

#### Scenario: Tap a road
- **WHEN** the developer taps a road in Liberty
- **THEN** the road is highlighted, and the panel states the ID of the style layer that draws the road, source `openmaptiles`, source layer `transportation`, the road's ID, and its properties, such as `class`, sorted by key

#### Scenario: Building in a park
- **WHEN** the developer taps a building in Liberty that lies inside a park
- **THEN** the building is selected and highlighted, not the park, because Liberty draws buildings above parks

#### Scenario: Merged buildings
- **WHEN** the developer taps a building in Liberty that the tiles merge with other buildings of the same height into one multi-polygon feature
- **THEN** the panel states geometry type MultiPolygon and the number of polygons, and every polygon of that feature is highlighted

#### Scenario: Choose another feature at the tap
- **WHEN** a building inside a park is selected and the developer chooses the park in the list of the other features at the tap
- **THEN** the park is highlighted and the building isn't, the panel states the park, and the list contains the building

#### Scenario: Feature state read back
- **WHEN** the developer taps a building in Liberty
- **THEN** the building is highlighted and the panel states the feature state `selected: true`, without a second tap

#### Scenario: Feature state of a label
- **WHEN** the developer taps a POI label in Liberty
- **THEN** a circle is highlighted at the label's point, and the panel states that MapLibre Native doesn't return feature state for labels and icons

#### Scenario: Select features of one source layer in turn
- **WHEN** a building is selected and the developer chooses another building of the same tap in the list, and then the first building again
- **THEN** after each choice exactly the chosen building is highlighted

#### Scenario: Tap another feature
- **WHEN** a road is selected and the developer taps a building
- **THEN** the building is highlighted, the road isn't, and the panel states the building's style layer, source, source layer, ID and properties

#### Scenario: Tap where no feature is drawn
- **WHEN** a feature is selected and the developer taps where the query returns no feature
- **THEN** no feature is highlighted and the panel shows no feature

#### Scenario: Feature without an ID
- **WHEN** the topmost feature at the tap has no ID
- **THEN** the panel states its style layer, source, source layer and properties, and that it has no ID and so can't be highlighted, and no feature is highlighted
