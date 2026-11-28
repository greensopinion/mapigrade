# map-markers Specification

## Purpose

Defines how Flutter widgets are drawn over a `MapigradeMap` at coordinates: the projection of each displayed frame, `MapigradeFrame`, and the markers that `MapigradeMarkers` places, aligns, scales, orders and hides.

## Requirements

### Requirement: Frame projection
`mapigrade` SHALL provide `MapigradeFrame`, which a descendant of a `MapigradeMap` reads with `MapigradeFrame.of(context)`. It SHALL describe the frame that the map displays in the current Flutter frame: its camera, its logical size, a conversion of a coordinate, with an optional altitude in meters, to a logical position relative to the widget's top-left corner, and a conversion of a position to the coordinate where the position's line of sight meets the ground plane at altitude 0. The conversions SHALL use the projection that the frame was drawn with, so that they agree with the displayed frame including its pitch, and SHALL NOT wait for the map. The conversion of a coordinate SHALL give no position for a coordinate behind the camera, and the conversion of a position SHALL give no coordinate for a position above the horizon. A widget that reads `MapigradeFrame.of(context)` SHALL be rebuilt when the displayed frame changes.

#### Scenario: Coordinate to position under pitch
- **WHEN** the camera is at rest with pitch 60 and bearing 30, and a descendant converts the coordinate of a road junction
- **THEN** the position is where the displayed frame draws the junction, within 1 logical pixel

#### Scenario: Round trip
- **WHEN** a descendant converts a position below the horizon to a coordinate and back
- **THEN** the result is within 0.5 logical pixels of the position

#### Scenario: Behind the camera
- **WHEN** the pitch is 80 and a descendant converts a coordinate behind the camera
- **THEN** the conversion gives no position

### Requirement: Markers
`mapigrade` SHALL provide `MapigradeMarkers`, a widget that a `MapigradeMap` takes among its children, with a list of `MapigradeMarker` values, each with a coordinate, an alignment, a pitch alignment, a rotation alignment, a setting to scale with perspective, and a child widget. Each marker SHALL place the point of its child that its alignment names at the position of its coordinate in the displayed frame, in every displayed frame, including while the camera moves. The child SHALL choose its own size. Moving the markers to a new frame SHALL NOT rebuild the markers' children. A marker's child SHALL receive hit tests where it is drawn.

#### Scenario: Pin at a coordinate during a pan
- **WHEN** a marker with the alignment `bottomCenter` marks a coordinate and the camera pans at 1,000 logical px/s
- **THEN** in each displayed frame, the bottom center of the marker's child is where that frame draws the coordinate, within 1 logical pixel

#### Scenario: No rebuild per frame
- **WHEN** the camera pans for 2 seconds
- **THEN** the build method of a marker's child isn't called

#### Scenario: Tap on a marker
- **WHEN** a marker's child has a `GestureDetector` and the user taps the child where it is drawn
- **THEN** the child's tap callback is called

### Requirement: Marker alignment with the map
A marker's pitch alignment and rotation alignment SHALL each be a `MarkerAlignment`, `viewport` or `map`, as MapLibre's `icon-pitch-alignment` and `icon-rotation-alignment` define them, with `viewport` as the default of both. With the pitch alignment `viewport`, the child SHALL be drawn upright, facing the screen. With the pitch alignment `map`, the child SHALL be drawn on the ground plane at its coordinate, so that the frame's perspective shortens and shrinks it as it does the map. With the rotation alignment `viewport`, the child's top SHALL point to the top of the screen. With the rotation alignment `map`, the child's top SHALL point to the map's north. A marker drawn on the ground plane SHALL receive hit tests where it is drawn.

#### Scenario: Pin upright under pitch
- **WHEN** a marker has the default alignments and the pitch is 60
- **THEN** the marker's child is drawn upright and unrotated

#### Scenario: Wind arrow on the ground
- **WHEN** a marker with the pitch alignment `map` and the rotation alignment `map` draws an arrow that points up, the bearing is 90 and the pitch is 60
- **THEN** the arrow is drawn on the ground pointing to the map's north, and shorter on the screen than it is wide

### Requirement: Marker size
An upright marker SHALL be drawn at its child's size by default. With the setting to scale with perspective on, an upright marker SHALL be scaled by the frame's perspective at its coordinate, by 1 at the camera's center. A marker drawn on the ground plane SHALL be scaled by the frame's perspective whatever the setting.

#### Scenario: Constant size
- **WHEN** two upright markers with the default setting are near the horizon and near the bottom edge with pitch 60
- **THEN** both are drawn at their children's size

#### Scenario: Perspective scaling
- **WHEN** the same markers have the setting to scale with perspective on
- **THEN** the marker near the horizon is drawn smaller than the marker near the bottom edge

### Requirement: Marker order and copies of the world
Markers SHALL be drawn with markers farther from the camera behind nearer ones, and markers at the same distance in list order, later above. Each marker SHALL be drawn once, in the copy of the world nearest the camera's center.

#### Scenario: Far behind near
- **WHEN** two markers overlap on the screen with pitch 60, and the farther one is later in the list
- **THEN** the nearer marker is drawn above the farther one

#### Scenario: One copy
- **WHEN** the map is zoomed out so that two copies of the world are visible
- **THEN** each marker is drawn once, in the copy nearest the camera's center

### Requirement: Hidden markers
A marker whose coordinate is behind the camera, beyond the ground that the frame draws, or whose drawn area doesn't overlap the widget, SHALL NOT be drawn and SHALL NOT receive hit tests. Hidden markers SHALL stay mounted, so that their children keep their `State`. Markers SHALL NOT be hidden behind terrain.

#### Scenario: Marker leaves and returns
- **WHEN** a marker's child runs an animation, the camera pans until the marker is off screen and pans back
- **THEN** the animation continued while the marker was hidden, and the child's `State` is the same object

#### Scenario: Beyond the visible ground
- **WHEN** the pitch is 85 and a marker's coordinate is farther than the ground that the frame draws
- **THEN** the marker isn't drawn
