## MODIFIED Requirements

### Requirement: Base layer of a flutter_map map
The system SHALL provide a layer that an application places among the children of a `flutter_map` map. The layer SHALL display the map in the full viewport of the `flutter_map` map. Layers placed after it SHALL be drawn above it. The layer SHALL accept an optional list of child widgets, typically `flutter_map` layers, and SHALL draw them above the map, in list order, in the full viewport, as the requirement "Children aligned with the displayed map frame" describes. The layer SHALL load the style it is given, create its map when it is inserted into the widget tree, and dispose the map when it is removed. When the application gives a layer that is in the tree a different style, the layer SHALL load the new style into the map it has, without creating another map. The layer SHALL report to the application each time a style has loaded.

#### Scenario: Map below overlays
- **WHEN** an application places the layer as the first child of a `flutter_map` map, followed by a marker layer and a polyline layer
- **THEN** the map fills the `flutter_map` viewport, and the markers and polylines are drawn above it

#### Scenario: Map below its children
- **WHEN** an application places the layer with a polyline layer and a marker layer as its children
- **THEN** the map fills the `flutter_map` viewport, the polylines are drawn above the map, and the markers above the polylines

#### Scenario: Layer removed
- **WHEN** the layer is removed from the widget tree
- **THEN** its map is disposed, and repeating insert and remove 50 times doesn't increase thread count or memory use without bound

#### Scenario: Style loaded
- **WHEN** an application places the layer with a reachable style URL and a handler for loaded styles
- **THEN** the handler is called once after the style has loaded

#### Scenario: Style changed on a layer in the tree
- **WHEN** the style of a layer in the tree has loaded, and the application rebuilds the layer with a different style URL, as it does when the platform switches between light and dark mode
- **THEN** the map renders using the new style, the handler for loaded styles is called again, and the layer creates no other map

### Requirement: Alignment measurement
The system SHALL provide a measurement mode that records, for each Flutter frame during camera changes, the map frame that Flutter displayed and the `flutter_map` camera. From these it SHALL compute the alignment error in logical pixels: the largest distance at the viewport corners and center between where the displayed map frame, as the layer draws it, draws a coordinate and where the overlays draw it. The measurement mode SHALL run with the layer configured with camera prediction at a stated lead or with no alignment, and with the overlays placed after the layer or as its children, and SHALL report the configuration. With the overlays as children, the overlays SHALL be drawn at the camera the layer gives its children, and the measurement mode SHALL also report the lag: the distance at the viewport center between where the displayed map frame draws a coordinate and where the live `flutter_map` camera places it. The measurement mode SHALL include phases in which the pan stops abruptly, decelerates as a `flutter_map` fling does, and reverses direction, and for these SHALL report the overshoot: the largest alignment error from the moment the camera's motion changes (an abrupt stop, the start of a deceleration, or a reversal) until half a second after the camera is at rest or moves at constant speed again, and the overshoot ahead: over the same time, the largest distance at the viewport center by which the drawn map is ahead of the overlays in the direction of motion before the change, or 0 if it isn't ahead. With the overlays as children, the overshoot ahead SHALL be measured against the live `flutter_map` camera instead of the overlays.

#### Scenario: Pan at a stated speed
- **WHEN** the alignment benchmark pans at a constant stated speed in logical pixels per second
- **THEN** the report states the speed, the layer configuration, and the p50, p95 and largest alignment error

#### Scenario: Pan at a stated speed with children
- **WHEN** the alignment benchmark pans at a constant stated speed with the overlays as children of the layer
- **THEN** the report states the speed, the layer configuration, the p50, p95 and largest alignment error, and the p50, p95 and largest lag

#### Scenario: Pan that stops
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and stops abruptly, or decelerates to rest as a `flutter_map` fling does
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead of each stop, as p50 and largest over the stops in the phase

#### Scenario: Pan that reverses
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and reverses direction abruptly
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead after each reversal, as p50 and largest over the reversals in the phase

## ADDED Requirements

### Requirement: Children aligned with the displayed map frame
On macOS and iOS, the layer SHALL draw its children at the `flutter_map` camera that the displayed map frame was rendered for: the camera from which the layer converted, or with camera prediction predicted, the map camera of that frame. In each Flutter frame, during camera changes and at rest, a geographic coordinate SHALL appear at the same screen position in the map and in the children, within 1 logical pixel. Until the map has displayed a frame, and on Android, the layer SHALL draw its children at the live `flutter_map` camera. The children SHALL get the same `flutter_map` map controller and map options as the layers placed after the layer. The children SHALL receive pointer input, and a child that hit-tests its content SHALL hit-test it at the position where it draws it. The layer SHALL NOT change the camera that the layers placed after it, and `flutter_map`'s gesture handling, use.

#### Scenario: Pan with children
- **WHEN** on macOS or iOS a polyline layer is a child of the layer, and the `flutter_map` camera pans at 1,000 logical px/s
- **THEN** in each Flutter frame the polyline and the same line drawn by the style are at most 1 logical pixel apart

#### Scenario: Fling, stop and reversal with children
- **WHEN** on macOS or iOS a marker layer is a child of the layer, and the `flutter_map` camera decelerates as a fling does, stops abruptly, or reverses
- **THEN** in each Flutter frame the markers and the map meet the 1 logical pixel limit

#### Scenario: Children with camera prediction
- **WHEN** on macOS or iOS the layer has camera prediction on with a lead of 1, and its children include a marker layer
- **THEN** the markers are drawn at the predicted camera of the displayed map frame, and meet the 1 logical pixel limit

#### Scenario: Tap on a child
- **WHEN** during a pan the user taps a polyline that is a child of the layer, at a point where the screen shows it
- **THEN** the polyline layer's hit test reports the polyline

#### Scenario: Siblings keep the live camera
- **WHEN** a marker layer is a child of the layer and a scale bar is placed after the layer
- **THEN** the scale bar is drawn at the live `flutter_map` camera

#### Scenario: Before the first displayed frame
- **WHEN** the layer has children and its map hasn't displayed a frame yet
- **THEN** the children are drawn at the live `flutter_map` camera

#### Scenario: Android
- **WHEN** on Android the layer has children
- **THEN** the children are drawn at the live `flutter_map` camera, as the layers placed after the layer are
