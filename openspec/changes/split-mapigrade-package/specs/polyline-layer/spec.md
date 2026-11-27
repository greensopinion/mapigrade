## MODIFIED Requirements

### Requirement: Placement among the style's layers
The polyline layer SHALL take a placement, `OverlayPlacement`, with three values:
- `OverlayPlacement.belowLabels()`, the default: the polylines SHALL be drawn directly above the last style layer whose type isn't `symbol`, so that every style layer after it is drawn above the polylines, except that when a style layer whose type is `fill-extrusion` comes before that place, the polylines SHALL be drawn directly below the first such layer, so that 3D buildings are drawn above the polylines. When the style has no layer other than `symbol` layers, the polylines SHALL be drawn below all style layers.
- `OverlayPlacement.belowLayer(id)`: the polylines SHALL be drawn directly below the style layer with the ID `id`.
- `OverlayPlacement.top()`: the polylines SHALL be drawn above all style layers.

The style's layers SHALL NOT include the layers that polyline layers add. When the style has no layer with the ID of a `belowLayer` placement, the polylines SHALL be drawn above all style layers, and the `MapigradeLayer` SHALL report a load failure that names the ID, once for each style load. When the application gives a polyline layer a different placement, the map SHALL draw its polylines at the new placement.

#### Scenario: Route below labels
- **WHEN** a polyline layer with the default placement draws a polyline 12 logical pixels wide through the position of a road name in the style
- **THEN** the road name is drawn above the polyline

#### Scenario: Style with symbol layers between other layers
- **WHEN** a style has a `symbol` layer of one-way arrows followed by bridge `line` layers and then label `symbol` layers, and a polyline layer has the default placement
- **THEN** the polylines are drawn above the bridges and below the labels

#### Scenario: Style with 3D buildings
- **WHEN** a style has a `fill-extrusion` layer of buildings before its last layer whose type isn't `symbol`, and a polyline layer has the default placement
- **THEN** the polylines are drawn below the buildings, and with the placement `OverlayPlacement.top()` above them

#### Scenario: Below a named layer
- **WHEN** a polyline layer has the placement `OverlayPlacement.belowLayer('water')` and the style has a layer `water`
- **THEN** the `water` layer is drawn above the polylines

#### Scenario: Named layer missing
- **WHEN** a polyline layer has the placement `OverlayPlacement.belowLayer('road-label')` and the style that loads has no layer with that ID
- **THEN** the polylines are drawn above all style layers, and the application's failure handler receives one `MapigradeLoadException` whose message names `road-label`

#### Scenario: Above everything
- **WHEN** a polyline layer has the placement `OverlayPlacement.top()`
- **THEN** the polylines are drawn above all style layers, including the labels
