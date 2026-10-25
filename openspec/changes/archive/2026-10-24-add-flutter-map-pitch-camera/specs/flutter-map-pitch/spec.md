## Purpose

Pitch in our `flutter_map` fork: a camera that looks at the ground at an angle, a projection that matches MapLibre Native's, and the way layers draw and respond to input when the map is pitched.

## ADDED Requirements

### Requirement: Pitch and its limits

The map SHALL have a pitch in degrees, the angle between the camera's view direction and straight down. The application SHALL be able to give an initial pitch and a maximum pitch in the map options. The maximum pitch SHALL default to 0 and SHALL be at most 60. The map SHALL limit the pitch to the range from 0 to the maximum pitch. The zoom SHALL describe the map scale at the center point, so that a pitch change doesn't change the zoom.

#### Scenario: Default maximum pitch

- **WHEN** the application gives no maximum pitch and an initial pitch of 30
- **THEN** the map's pitch is 0

#### Scenario: Pitch above the maximum

- **WHEN** the maximum pitch is 45 and the application sets a pitch of 50
- **THEN** the map's pitch is 45

#### Scenario: Maximum pitch above 60

- **WHEN** the application gives a maximum pitch of 75 and sets a pitch of 75
- **THEN** the map's pitch is 60

#### Scenario: Zoom unchanged by pitch

- **WHEN** the map is at zoom 12 and the application changes the pitch from 0 to 60
- **THEN** the map's zoom is 12 and the center coordinate is at the center of the viewport

### Requirement: Setting the pitch from the map controller

The application SHALL be able to set the pitch through the map controller. Each change of the pitch SHALL emit a pitch event that contains the camera before and after the change and has the existing map controller event source. Setting the current pitch SHALL emit no event and SHALL report that the camera didn't change.

#### Scenario: Pitch change

- **WHEN** the pitch is 0, the maximum pitch is 60 and the application sets a pitch of 40 through the map controller
- **THEN** the map's pitch is 40, the controller reports that the camera changed, and one pitch event with pitch 0 before and 40 after is emitted

#### Scenario: Unchanged pitch

- **WHEN** the pitch is 40 and the application sets a pitch of 40 through the map controller
- **THEN** the controller reports that the camera didn't change and no event is emitted

### Requirement: Pitched projection

When pitched, the camera SHALL convert coordinates to screen positions with MapLibre Native's camera model: a vertical field of view of 0.6435011087932844 radians and a camera distance from the center point of half the viewport height divided by the tangent of half the field of view. A coordinate SHALL appear within 0.01 px of the position that this model gives for the same center, zoom, rotation, pitch and viewport size. Converting a screen position to a coordinate SHALL return the coordinate of the ground point on the view ray through that position. The camera SHALL provide a conversion that returns no coordinate for a position above the horizon.

#### Scenario: Center point

- **WHEN** the map is pitched at any pitch up to 60 and any rotation
- **THEN** the center coordinate appears at the center of the viewport

#### Scenario: Matches the camera model

- **WHEN** the map is at pitch 60 and rotation 30, and a coordinate is converted to a screen position
- **THEN** the screen position is within 0.01 px of the position given by MapLibre Native's camera model for the same camera and viewport size

#### Scenario: Round trip

- **WHEN** the map is pitched and a screen position in the viewport is converted to a coordinate and that coordinate back to a screen position
- **THEN** the result is within 0.01 px of the original position

#### Scenario: Above the horizon

- **WHEN** the map is at pitch 60 and a screen position above the horizon is converted to a coordinate with the conversion that can return no coordinate
- **THEN** no coordinate is returned

### Requirement: Unchanged behavior at pitch 0

At pitch 0, the camera's projections, visible bounds, the positions at which layers draw, and gesture behavior SHALL be the same as without pitch support.

#### Scenario: Existing tests

- **WHEN** the pitch is 0
- **THEN** the fork's existing tests pass without changes

### Requirement: Additive API

Application code written for the release that the fork branch starts from SHALL compile against the fork without changes, except a class that implements the map controller interface itself. The fork SHALL add no values to the map event source enumeration and no abstract members to the camera fit and camera constraint classes.

#### Scenario: Exhaustive switch on the event source

- **WHEN** an application has a `switch` with a case for each map event source value and no default
- **THEN** it compiles against the fork without changes

#### Scenario: Custom camera constraint

- **WHEN** an application has its own camera constraint subclass written for the release the fork starts from
- **THEN** it compiles against the fork without changes

#### Scenario: Markers and labels at pitch 0

- **WHEN** the pitch is 0 and the map shows markers, rotated markers, and polygons with labels drawn first and last
- **THEN** the drawn pixels are the same as in the release the fork starts from

### Requirement: Ground layers in perspective

Layers that move with the map, among them the tile, polygon, polyline, circle and overlay image layers, SHALL draw each coordinate at the screen position that the pitched projection gives for it. At every pitch up to 60 and every rotation, the layers SHALL cover the whole viewport with no area left undrawn that the unpitched layer would have drawn.

#### Scenario: Polyline vertex position

- **WHEN** the map is at pitch 50 and rotation 20 and shows a polyline
- **THEN** each vertex of the polyline is drawn at the screen position that the camera gives for its coordinate

#### Scenario: Viewport covered

- **WHEN** the map shows a tile layer at pitch 60 and rotation 45 with all tiles loaded
- **THEN** every pixel of the viewport shows a tile

### Requirement: Visible bounds and tiles of the visible ground

When pitched, the camera's visible bounds SHALL contain every coordinate visible in the viewport, except that, as for an unpitched map, they SHALL be limited to longitudes from -180 to 180. The tile layer SHALL load the tiles that cover the visible ground, at the tile zoom that it chooses from the camera zoom, including on both sides of the antimeridian.

#### Scenario: Far edge in visible bounds

- **WHEN** the map is at pitch 60
- **THEN** the coordinates at the four corners of the viewport are within the visible bounds

#### Scenario: Tiles across the antimeridian

- **WHEN** the map is at pitch 60, in a CRS that repeats the world horizontally, with the far edge of the view across the antimeridian
- **THEN** the tile layer loads the tiles on both sides, and every position in the viewport shows a tile

#### Scenario: Far tiles loaded

- **WHEN** the map is at pitch 60 and a coordinate at the top edge of the viewport lies in tile T at the tile zoom
- **THEN** the tile layer loads tile T

### Requirement: Billboard layers

Markers and polygon labels SHALL be drawn at the screen position that the pitched projection gives for their point, upright and at their unpitched size. A marker that rotates with the map SHALL rotate with the map's rotation and SHALL NOT be tilted by the pitch.

#### Scenario: Marker position and size

- **WHEN** the map is at pitch 60 and shows a marker of 48 × 48 px whose point is near the top of the viewport
- **THEN** the marker is drawn 48 × 48 px, upright, at the screen position of its point with its alignment applied

#### Scenario: Polygon label

- **WHEN** the map is at pitch 45 and shows a polygon with a label
- **THEN** the label is drawn upright and unscaled at the screen position of its label point

### Requirement: Hit testing when pitched

A tap on a pitched map SHALL report the coordinate under the tap, and the hit-detectable layers SHALL report the features under the tap.

#### Scenario: Tap coordinate

- **WHEN** the map is at pitch 60 and the user taps a screen position
- **THEN** the tap event's coordinate is the coordinate that the camera gives for that screen position

#### Scenario: Polygon hit

- **WHEN** the map is at pitch 60 and the user taps inside a hit-detectable polygon near the top of the viewport
- **THEN** the polygon layer reports that polygon as hit

### Requirement: Existing gestures when pitched

The existing gestures SHALL keep the ground under the pointer on a pitched map:

- pinch-zoom, scroll-wheel zoom and double-tap zoom SHALL keep the coordinate under the focal point at the focal point;
- the two-finger rotate gesture SHALL rotate the map about the coordinate under the focal point;
- a drag SHALL keep the coordinate under the pointer at the drag's start under the pointer;
- a fling SHALL continue in the direction of the drag's ground movement, starting at the drag's ground speed at its end.

When the focal point is above the horizon, zoom and rotation SHALL keep the center coordinate at the center of the viewport.

#### Scenario: Scroll-wheel zoom

- **WHEN** the map is at pitch 50 and the user zooms in with the scroll wheel with the cursor near the top of the viewport
- **THEN** the coordinate under the cursor before the zoom is within 0.5 px of the cursor after the zoom

#### Scenario: Rotate gesture

- **WHEN** the map is at pitch 50 and the user rotates the map with two fingers whose focal point is near the bottom of the viewport, at 0.75 and at 3 degrees per frame
- **THEN** the distance, in projected pixels at the camera zoom, between the coordinate under the focal point before the gesture and the ground point under the focal point after it is within 0.05 px of the same distance for the same gesture on an unpitched map

#### Scenario: Drag near the top of the viewport

- **WHEN** the map is at pitch 60 and the user drags from a position near the top of the viewport to a position near the bottom
- **THEN** the coordinate under the pointer at the start of the drag is within 0.5 px of the pointer at the end of the drag

#### Scenario: Fling

- **WHEN** the map is at pitch 50 and the user releases a drag with a velocity
- **THEN** the map continues to move in the direction that the ground moved during the drag, starting at the ground speed that the drag had at its end

### Requirement: Map controller screen offsets when pitched

The map controller methods that take a screen offset SHALL use the pitched projection: moving with an offset SHALL show the given center coordinate at the viewport center plus the offset, and rotating around a point SHALL rotate the map about the coordinate at that screen position. When the screen position is above the horizon, the methods SHALL behave as without an offset.

#### Scenario: Move with offset

- **WHEN** the map is at pitch 60 and rotation 30, and the application moves to a coordinate with an offset of 0, 200 px
- **THEN** the coordinate appears within 0.5 px of 200 px below the viewport center

#### Scenario: Rotate around a point

- **WHEN** the map is at pitch 45 and the application rotates by 90 degrees around a screen position near the bottom of the viewport
- **THEN** the coordinate at that screen position before the rotation is within 0.5 px of it after the rotation
