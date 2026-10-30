# polyline-layer Specification

## Purpose

Lets an application draw polylines, such as routes and tracks, as part of the MapLibre map: between the style's own layers, for example below the labels, and drawn by MapLibre instead of by Flutter in every frame.

## Requirements

### Requirement: Polyline layer in the children of the map layer
The package SHALL provide `MapigradePolylineLayer`, a widget that takes a list of `MapigradePolyline` values and a placement. An application SHALL place it among the `children` of a `MapigradeLayer`, at any depth below a child. The polyline layer SHALL give its polylines to that `MapigradeLayer`'s map, and the map SHALL draw them in the map frames it renders, so that the polylines are drawn exactly where the displayed map frame draws their coordinates, including while the camera moves. The polyline layer SHALL draw nothing in Flutter. A polyline layer that isn't below a `MapigradeLayer` SHALL fail an assertion in debug builds and draw nothing in release builds. When the `MapigradeLayer` has no map, because the map isn't created yet or couldn't be created, the polyline layer SHALL NOT throw; when the map is created, it SHALL draw the polylines that the polyline layer has then.

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
- **THEN** an assertion fails that states that the polyline layer must be below a `MapigradeLayer`

#### Scenario: Polylines given before the map exists
- **WHEN** an application places a `MapigradeLayer` with a polyline layer in its children, and the map is created after the polyline layer was built
- **THEN** the map draws the polylines when the style has loaded

### Requirement: Polyline model
The package SHALL provide `MapigradePolyline`, an immutable value with these properties and defaults: `points`, a list of `LatLng`, required; `color`, default `0xFF00FF00`; `strokeWidth`, default 1.0; `useStrokeWidthInMeter`, default false; `borderStrokeWidth`, default 0.0; `borderColor`, default `0xFFFFFF00`; `strokeCap`, default `StrokeCap.round`; `strokeJoin`, default `StrokeJoin.round`; `dashes`, a list of numbers or null, default null; `gradientColors`, a list of `Color` or null, default null; and `gradientStops`, a list of numbers or null, default null. The names, types and defaults of the properties that `flutter_map`'s `Polyline` also has SHALL equal those of `Polyline`. Two `MapigradePolyline` values with equal properties SHALL be equal. In debug builds the constructor SHALL fail an assertion for a negative `strokeWidth` or `borderStrokeWidth`, for `dashes` with an odd number of entries, a negative entry or only zeros, for `gradientStops` that is given without `gradientColors`, whose length differs from that of `gradientColors`, or whose entries aren't in non-decreasing order from 0 to 1, and for `gradientColors` given together with `dashes`, because MapLibre can't draw a gradient on a dashed line.

#### Scenario: Defaults
- **WHEN** an application creates a `MapigradePolyline` with only `points`
- **THEN** its other properties have the defaults that `flutter_map`'s `Polyline` has for the same names, and `dashes`, `gradientColors` and `gradientStops` are null

#### Scenario: Equal polylines
- **WHEN** an application creates two `MapigradePolyline` values from equal lists of points and equal properties
- **THEN** the two values are equal and have the same hash code

#### Scenario: Invalid dashes
- **WHEN** an application creates a `MapigradePolyline` with `dashes` of three entries in a debug build
- **THEN** an assertion fails that names `dashes`

### Requirement: How a polyline is drawn
The map SHALL draw each polyline with at least two points as a line through its points in list order. A polyline with fewer than two points SHALL draw nothing. Between consecutive points the line SHALL take the shorter way around the world, so that a line from longitude 179 to longitude -179 crosses the antimeridian. The map SHALL draw each property as follows:
- `color`: the color of the line, including its alpha.
- `strokeWidth`: the width of the line in logical pixels. With `useStrokeWidthInMeter`, the width in meters at the latitude of the first point, at every zoom level, within 1 percent.
- `borderStrokeWidth` and `borderColor`: a border on each side of the line, each `borderStrokeWidth` / 2 logical pixels wide, in `borderColor`. The border SHALL NOT be drawn under the line, so a line with a translucent `color` shows the map, not the border, through it.
- `strokeCap` and `strokeJoin`: the caps at the line's ends and the joins between its segments, as `StrokeCap` and `StrokeJoin` define them.
- `dashes`: alternating dash and gap lengths, in multiples of the line's width, starting with a dash. A dash of length 0 with a round cap SHALL draw a dot. When `dashes` is null, the line SHALL be solid.
- `gradientColors` and `gradientStops`: a color gradient along the length of the line, where a stop of 0 is the first point and 1 is the last, measured along the line; the gradient SHALL replace `color`. When `gradientStops` is null, the stops SHALL be spaced evenly from 0 to 1. Two equal consecutive stops SHALL give a hard edge between their colors.
- The border of a dashed line SHALL be solid.

#### Scenario: Translucent line with a border
- **WHEN** the map draws a polyline 10 logical pixels wide with a `color` of alpha 0.5 and a red border 4 logical pixels wide, over a white background
- **THEN** the pixels at the center of the line are a mix of white and the line's color with no red, and the 2 logical pixels on each side of the line are red

#### Scenario: Width in meters
- **WHEN** the map draws a polyline with a `strokeWidth` of 100 and `useStrokeWidthInMeter` at latitude 45, at two zoom levels that differ by 2
- **THEN** the drawn width at the higher zoom level is 4 times the drawn width at the lower one, and at each zoom level it is the width in logical pixels of 100 meters at latitude 45, within 1 percent

#### Scenario: Dashes scale with the width
- **WHEN** the map draws a polyline 4 logical pixels wide with `dashes` of `[2, 1]`
- **THEN** the line has dashes 8 logical pixels long, separated by gaps 4 logical pixels long

#### Scenario: Gradient along a curved line
- **WHEN** the map draws a polyline that runs east and then back west to near its first point, with `gradientColors` red and blue
- **THEN** the line is red at its first point, blue at its last point, and the color changes along the line, not along the straight line between the first and the last point

#### Scenario: Line across the antimeridian
- **WHEN** the map draws a polyline from longitude 179 to longitude -179 at the equator
- **THEN** the line is about 2 degrees long and crosses the antimeridian

### Requirement: Draw order of polylines
Within one polyline layer, a polyline later in the list SHALL be drawn above the polylines before it, with one exception: in a run of consecutive polylines that have the same `strokeCap`, the same `dashes` and no gradient, the borders of all polylines in the run SHALL be drawn below the lines of all polylines in the run, as `flutter_map` draws the borders of a batch.

#### Scenario: Later polyline above
- **WHEN** a polyline layer has a red polyline followed by a blue polyline that crosses it, both solid
- **THEN** the crossing is blue

#### Scenario: Borders in a run
- **WHEN** a polyline layer has two solid polylines with borders that cross each other
- **THEN** at the crossing, the line of each polyline is drawn above the border of the other

### Requirement: Placement among the style's layers
The polyline layer SHALL take a placement, `LayerPlacement`, with three values:
- `LayerPlacement.belowLabels()`, the default: the polylines SHALL be drawn directly above the last style layer whose type isn't `symbol`, so that every style layer after it is drawn above the polylines, except that when a style layer whose type is `fill-extrusion` comes before that place, the polylines SHALL be drawn directly below the first such layer, so that 3D buildings are drawn above the polylines. When the style has no layer other than `symbol` layers, the polylines SHALL be drawn below all style layers.
- `LayerPlacement.belowLayer(id)`: the polylines SHALL be drawn directly below the style layer with the ID `id`.
- `LayerPlacement.top()`: the polylines SHALL be drawn above all style layers.

The style's layers SHALL NOT include the layers that polyline layers add. When the style has no layer with the ID of a `belowLayer` placement, the polylines SHALL be drawn above all style layers, and the `MapigradeLayer` SHALL report a load failure that names the ID, once for each style load. When the application gives a polyline layer a different placement, the map SHALL draw its polylines at the new placement.

#### Scenario: Route below labels
- **WHEN** a polyline layer with the default placement draws a polyline 12 logical pixels wide through the position of a road name in the style
- **THEN** the road name is drawn above the polyline

#### Scenario: Style with symbol layers between other layers
- **WHEN** a style has a `symbol` layer of one-way arrows followed by bridge `line` layers and then label `symbol` layers, and a polyline layer has the default placement
- **THEN** the polylines are drawn above the bridges and below the labels

#### Scenario: Style with 3D buildings
- **WHEN** a style has a `fill-extrusion` layer of buildings before its last layer whose type isn't `symbol`, and a polyline layer has the default placement
- **THEN** the polylines are drawn below the buildings, and with the placement `LayerPlacement.top()` above them

#### Scenario: Below a named layer
- **WHEN** a polyline layer has the placement `LayerPlacement.belowLayer('water')` and the style has a layer `water`
- **THEN** the `water` layer is drawn above the polylines

#### Scenario: Named layer missing
- **WHEN** a polyline layer has the placement `LayerPlacement.belowLayer('road-label')` and the style that loads has no layer with that ID
- **THEN** the polylines are drawn above all style layers, and the application's failure handler receives one `LayerLoadException` whose message names `road-label`

#### Scenario: Above everything
- **WHEN** a polyline layer has the placement `LayerPlacement.top()`
- **THEN** the polylines are drawn above all style layers, including the labels

### Requirement: Order of several polyline layers
When several polyline layers draw at the same placement in one map, the polylines of a polyline layer whose `MapigradeLayer` child is later in `children` SHALL be drawn above those of a polyline layer whose child is earlier. Polyline layers below the same child SHALL be drawn in the order in which they were inserted into the widget tree, the latest above. The order SHALL follow `children` when the application reorders the children or inserts a child.

#### Scenario: Two polyline layers
- **WHEN** a `MapigradeLayer` has two polyline layers in its children at the default placement, the first with a red polyline and the second with a blue polyline that crosses it
- **THEN** the crossing is blue

#### Scenario: Child inserted before an existing polyline layer
- **WHEN** an application inserts a polyline layer with a red polyline into `children` before an existing polyline layer with a crossing blue polyline
- **THEN** the crossing is blue

### Requirement: Polylines across style loads
When the map loads a style, including a different style given to a `MapigradeLayer` in the tree, the map SHALL draw the polylines of every polyline layer with the new style, at the placement resolved against the new style's layers.

#### Scenario: Light and dark style
- **WHEN** a `MapigradeLayer` with a polyline layer in its children is rebuilt with a different style URL, as it is when the platform switches between light and dark mode
- **THEN** after the new style has loaded, the map draws the polylines below the new style's labels

### Requirement: Polyline updates
When the application rebuilds a polyline layer with a list of polylines that isn't equal to the list it had, the map SHALL draw the new polylines, and SHALL stop drawing polylines that are no longer in the list. When the application rebuilds a polyline layer with an equal list, the polyline layer SHALL NOT send the polylines to the map again. When a polyline layer is removed from the tree, the map SHALL stop drawing its polylines.

#### Scenario: Polyline points changed
- **WHEN** the application rebuilds a polyline layer with a polyline that has one more point at its end
- **THEN** the map draws the longer polyline

#### Scenario: Rebuild with an equal list
- **WHEN** the application rebuilds a polyline layer with a new list of new `MapigradePolyline` values that are equal to the values it had
- **THEN** the polyline layer sends nothing to the map

#### Scenario: Polyline layer removed
- **WHEN** the application removes a polyline layer from the children
- **THEN** the map no longer draws its polylines
