# map-layer Specification

## Purpose

Displays the MapLibre map as the base layer of a `flutter_map` map, at the camera that `flutter_map` controls, so that `flutter_map` overlays drawn above it stay aligned with the map. Also measures how far the map and the overlays are apart during camera changes.

## Requirements

### Requirement: Base layer of a flutter_map map
The system SHALL provide a layer that an application places among the children of a `flutter_map` map. The layer SHALL display the map in the full viewport of the `flutter_map` map. Layers placed after it SHALL be drawn above it. The layer SHALL load the style it is given, create its map when it is inserted into the widget tree, and dispose the map when it is removed.

#### Scenario: Map below overlays
- **WHEN** an application places the layer as the first child of a `flutter_map` map, followed by a marker layer and a polyline layer
- **THEN** the map fills the `flutter_map` viewport, and the markers and polylines are drawn above it

#### Scenario: Layer removed
- **WHEN** the layer is removed from the widget tree
- **THEN** its map is disposed, and repeating insert and remove 50 times doesn't increase thread count or memory use without bound

### Requirement: Map follows the flutter_map camera
The system SHALL set the map camera from the `flutter_map` camera whenever the `flutter_map` camera changes. The MapLibre zoom SHALL be the `flutter_map` zoom minus 1, the MapLibre bearing SHALL be the negated `flutter_map` rotation, and the map viewport SHALL be the size of the `flutter_map` viewport before rotation. Pitch SHALL be 0.

#### Scenario: Camera change
- **WHEN** the `flutter_map` camera changes through a gesture or a camera controller call
- **THEN** a later displayed map frame reports the converted camera

#### Scenario: Rotated map
- **WHEN** the `flutter_map` rotation is 30 degrees
- **THEN** the map is rotated by the same angle in the same direction as the overlays, and fills the viewport without empty corners when the camera is at rest

### Requirement: Alignment at rest
When the camera is at rest and the map has displayed a frame for it, a geographic coordinate SHALL appear at the same screen position in the map and in `flutter_map` overlays, within 1 logical pixel.

#### Scenario: Marker at a known coordinate
- **WHEN** the style draws a marker at a coordinate, a `flutter_map` marker is placed at the same coordinate, and the camera is at rest
- **THEN** the centers of the two markers on screen are at most 1 logical pixel apart

#### Scenario: Zoom, rotation, latitude and longitude
- **WHEN** the static alignment check runs at fractional and integer zoom levels, with rotation, at latitudes up to 80 degrees, and with the camera within 1 degree of the antimeridian
- **THEN** each case meets the 1 logical pixel limit

#### Scenario: After resize
- **WHEN** the `flutter_map` viewport is resized and the camera is then at rest
- **THEN** the markers meet the 1 logical pixel limit at the new size

### Requirement: Compensating transform
While the camera of the displayed map frame differs from the current `flutter_map` camera, the system SHALL draw the map with a transform that moves, scales and rotates the frame so that each coordinate in the frame appears where the current `flutter_map` camera places it. The transform SHALL use the camera of the last displayed frame that Dart has been notified of. If the transform would move the frame entirely outside the viewport, the system SHALL draw the frame without the transform, so that Flutter draws the texture and takes the next map frame.

#### Scenario: Camera ahead of the displayed frame
- **WHEN** the `flutter_map` camera has moved by a known offset since the last displayed frame that Dart has been notified of, and the raster thread displays that frame
- **THEN** the frame is drawn shifted by that offset, and a coordinate in the frame appears at the position the current camera places it

#### Scenario: Camera jump larger than the viewport
- **WHEN** the `flutter_map` camera moves in one step by more than the viewport, so that the transform would move the displayed frame entirely outside the viewport
- **THEN** the frame is drawn without the transform, and a later displayed map frame reports the new camera

#### Scenario: Antimeridian
- **WHEN** the `flutter_map` camera pans across the antimeridian
- **THEN** the transform uses the shorter longitude difference, and the map does not jump by a world width

### Requirement: Alignment measurement
The system SHALL provide a measurement mode that records, for each Flutter frame during camera changes, the map frame whose camera the transform used, the map frame that Flutter displayed, and the `flutter_map` camera. From these it SHALL compute the alignment error in logical pixels, the largest distance at the viewport corners and center between where the displayed map frame draws a coordinate and where the overlays draw it, both with the transform and without it.

#### Scenario: Pan at a stated speed
- **WHEN** the alignment benchmark pans at a constant stated speed in logical pixels per second
- **THEN** the report states the speed, the fraction of Flutter frames whose displayed map frame differs from the frame the transform used, and the p50, p95 and largest alignment error with and without the transform
