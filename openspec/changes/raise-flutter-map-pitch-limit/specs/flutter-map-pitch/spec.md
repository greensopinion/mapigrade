## ADDED Requirements

### Requirement: Far limit of the visible ground

The visible ground SHALL end at the far limit: the ground points whose view ray is 89.25° from straight down. On the screen, the far limit is a horizontal line, which is in the viewport only when the pitch is above 89.25° minus half the vertical field of view. Above the far limit, layers that move with the map SHALL draw nothing, and the map's background color SHALL show. Below the pitch at which the far limit enters the viewport, the map SHALL behave as before this requirement.

#### Scenario: Far limit in the viewport

- **WHEN** the map is at pitch 85
- **THEN** the far limit is a horizontal line in the viewport, the tile layer draws below it, and the area above it shows the map's background color

#### Scenario: Far limit outside the viewport

- **WHEN** the map is at pitch 60
- **THEN** the far limit is above the viewport, and the tile layer covers the whole viewport

#### Scenario: Nothing drawn beyond the far limit

- **WHEN** the map is at pitch 85 and shows a polygon whose vertices lie beyond the far limit and behind the camera
- **THEN** the polygon is drawn only below the far limit, at the positions that the pitched projection gives

## MODIFIED Requirements

### Requirement: Pitch and its limits

The map SHALL have a pitch in degrees, the angle between the camera's view direction and straight down. The application SHALL be able to give an initial pitch and a maximum pitch in the map options. The maximum pitch SHALL default to 0 and SHALL be at most 85. The map SHALL limit the pitch to the range from 0 to the maximum pitch. The zoom SHALL describe the map scale at the center point, so that a pitch change doesn't change the zoom.

#### Scenario: Default maximum pitch

- **WHEN** the application gives no maximum pitch and an initial pitch of 30
- **THEN** the map's pitch is 0

#### Scenario: Pitch above the maximum

- **WHEN** the maximum pitch is 45 and the application sets a pitch of 50
- **THEN** the map's pitch is 45

#### Scenario: Maximum pitch above 60

- **WHEN** the application gives a maximum pitch of 75 and sets a pitch of 75
- **THEN** the map's pitch is 75

#### Scenario: Maximum pitch above 85

- **WHEN** the application gives a maximum pitch of 90 and sets a pitch of 90
- **THEN** the map's pitch is 85

#### Scenario: Zoom unchanged by pitch

- **WHEN** the map is at zoom 12 and the application changes the pitch from 0 to 85
- **THEN** the map's zoom is 12 and the center coordinate is at the center of the viewport

### Requirement: Pitched projection

When pitched, the camera SHALL convert coordinates to screen positions with MapLibre Native's camera model: a vertical field of view of 0.6435011087932844 radians and a camera distance from the center point of half the viewport height divided by the tangent of half the field of view. A coordinate SHALL appear within 0.01 px of the position that this model gives for the same center, zoom, rotation, pitch and viewport size. Converting a screen position below the far limit to a coordinate SHALL return the coordinate of the ground point on the view ray through that position. The camera SHALL provide a conversion that returns no coordinate for a position above the far limit; the conversion that always returns a coordinate SHALL return the coordinate on the far limit directly below such a position.

#### Scenario: Center point

- **WHEN** the map is pitched at any pitch up to 85 and any rotation
- **THEN** the center coordinate appears at the center of the viewport

#### Scenario: Matches the camera model

- **WHEN** the map is at pitch 60 or 85 and rotation 30, and a coordinate below the far limit is converted to a screen position
- **THEN** the screen position is within 0.01 px of the position given by MapLibre Native's camera model for the same camera and viewport size

#### Scenario: Round trip

- **WHEN** the map is pitched and a screen position in the viewport below the far limit is converted to a coordinate and that coordinate back to a screen position
- **THEN** the result is within 0.01 px of the original position

#### Scenario: Above the horizon

- **WHEN** the map is at pitch 60 and a screen position above the horizon is converted to a coordinate with the conversion that can return no coordinate
- **THEN** no coordinate is returned

#### Scenario: Above the far limit

- **WHEN** the map is at pitch 85 and a screen position above the far limit is converted to a coordinate
- **THEN** the conversion that can return no coordinate returns none, and the other conversion returns the coordinate on the far limit directly below the position

### Requirement: Ground layers in perspective

Layers that move with the map, among them the tile, polygon, polyline, circle and overlay image layers, SHALL draw each coordinate at the screen position that the pitched projection gives for it, and only below the far limit. At every pitch up to 85 and every rotation, the layers SHALL cover the whole viewport below the far limit with no area left undrawn that the unpitched layer would have drawn.

#### Scenario: Polyline vertex position

- **WHEN** the map is at pitch 50 and rotation 20 and shows a polyline
- **THEN** each vertex of the polyline is drawn at the screen position that the camera gives for its coordinate

#### Scenario: Viewport covered

- **WHEN** the map shows a tile layer at pitch 60 and rotation 45 with all tiles loaded
- **THEN** every pixel of the viewport shows a tile

#### Scenario: Viewport below the far limit covered

- **WHEN** the map shows a tile layer at pitch 85 and rotation 45 with all tiles loaded
- **THEN** every pixel of the viewport below the far limit shows a tile

### Requirement: Visible bounds and tiles of the visible ground

When pitched, the camera's visible bounds SHALL contain every coordinate visible in the viewport below the far limit, and SHALL NOT be enlarged by ground beyond it, except that, as for an unpitched map, they SHALL be limited to longitudes from -180 to 180. The tile layer SHALL load tiles that cover the visible ground, each at the zoom that the requirement "Tile zoom from size on screen" gives, including on both sides of the antimeridian.

#### Scenario: Far edge in visible bounds

- **WHEN** the map is at pitch 60
- **THEN** the coordinates at the four corners of the viewport are within the visible bounds

#### Scenario: Visible bounds at pitch 85

- **WHEN** the map is at pitch 85
- **THEN** the coordinates at the bottom corners of the viewport and at the ends of the far limit are within the visible bounds, and the visible bounds are finite

#### Scenario: Tiles across the antimeridian

- **WHEN** the map is at pitch 60, in a CRS that repeats the world horizontally, with the far edge of the view across the antimeridian
- **THEN** the tile layer loads the tiles on both sides, and every position in the viewport shows a tile

#### Scenario: Far tiles loaded

- **WHEN** the map is at pitch 60 and a coordinate is at the top edge of the viewport
- **THEN** the tile layer loads a tile that contains the coordinate, at a zoom coarser than the tile zoom at the center of the viewport

### Requirement: Existing gestures when pitched

The existing gestures SHALL keep the ground under the pointer on a pitched map:

- pinch-zoom, scroll-wheel zoom and double-tap zoom SHALL keep the coordinate under the focal point at the focal point;
- the two-finger rotate gesture SHALL rotate the map about the coordinate under the focal point;
- a drag SHALL keep the coordinate under the pointer at the drag's start under the pointer;
- a fling SHALL continue in the direction of the drag's ground movement, starting at the drag's ground speed at its end.

When the pointer or the focal point is above the far limit, the gestures SHALL use the position on the far limit directly below it, so that the ground moves by no more than it does for a pointer on the far limit.

#### Scenario: Scroll-wheel zoom

- **WHEN** the map is at pitch 50 and the user zooms in with the scroll wheel with the cursor near the top of the viewport
- **THEN** the coordinate under the cursor before the zoom is within 0.5 px of the cursor after the zoom

#### Scenario: Rotate gesture

- **WHEN** the map is at pitch 50 and the user rotates the map with two fingers whose focal point is near the bottom of the viewport, at 0.75 and at 3 degrees per frame
- **THEN** the distance, in projected pixels at the camera zoom, between the coordinate under the focal point before the gesture and the ground point under the focal point after it is within 0.05 px of the same distance for the same gesture on an unpitched map

#### Scenario: Drag near the top of the viewport

- **WHEN** the map is at pitch 60 and the user drags from a position near the top of the viewport to a position near the bottom
- **THEN** the coordinate under the pointer at the start of the drag is within 0.5 px of the pointer at the end of the drag

#### Scenario: Drag above the far limit

- **WHEN** the map is at pitch 85 and the user drags from a position above the far limit to a position near the bottom of the viewport
- **THEN** the map moves as for a drag that starts on the far limit directly below the start position

#### Scenario: Fling

- **WHEN** the map is at pitch 50 and the user releases a drag with a velocity
- **THEN** the map continues to move in the direction that the ground moved during the drag, starting at the ground speed that the drag had at its end

### Requirement: Map controller screen offsets when pitched

The map controller methods that take a screen offset SHALL use the pitched projection: moving with an offset SHALL show the given center coordinate at the viewport center plus the offset, and rotating around a point SHALL rotate the map about the coordinate at that screen position. When the screen position is above the far limit, the methods SHALL behave as without an offset.

#### Scenario: Move with offset

- **WHEN** the map is at pitch 60 and rotation 30, and the application moves to a coordinate with an offset of 0, 200 px
- **THEN** the coordinate appears within 0.5 px of 200 px below the viewport center

#### Scenario: Rotate around a point

- **WHEN** the map is at pitch 45 and the application rotates by 90 degrees around a screen position near the bottom of the viewport
- **THEN** the coordinate at that screen position before the rotation is within 0.5 px of it after the rotation

### Requirement: Camera fit when pitched

When the map is pitched, a camera fit SHALL keep the camera's pitch and rotation and choose its center and zoom as follows, where the fit area is the viewport reduced by the padding, and further reduced to the part below the far limit:

- Fitting bounds SHALL choose a center and zoom at which the four corners of the bounds, converted to screen positions, lie inside the fit area.
- Fitting coordinates SHALL choose a center and zoom at which every coordinate, converted to a screen position, lies inside the fit area.
- Fitting inside bounds SHALL choose a center and zoom at which the coordinates under the four corners of the fit area lie inside the bounds.

Each fit SHALL choose the largest such zoom, within 0.01, unless the minimum zoom, the maximum zoom or rounding to an integer zoom limits it. At pitch 0, each fit SHALL return the same camera as the release the fork starts from.

#### Scenario: Fit bounds

- **WHEN** the map is at pitch 60 and rotation 30 and the application fits bounds with no padding
- **THEN** the pitch is 60, the rotation is 30, each corner of the bounds is within the viewport, and at least one corner is within 1 px of the edge of the viewport

#### Scenario: Fit bounds at pitch 85

- **WHEN** the map is at pitch 85 and the application fits bounds with no padding
- **THEN** the pitch is 85, each corner of the bounds is within the viewport below the far limit, and at least one corner is within 1 px of the edge of that area

#### Scenario: Fit coordinates with padding

- **WHEN** the map is at pitch 45 and the application fits five coordinates with a padding of 20 px on each side
- **THEN** each coordinate is at least 20 px inside each edge of the viewport, and at least one coordinate is within 1 px of 20 px from an edge

#### Scenario: Fit inside bounds

- **WHEN** the map is at pitch 60 and rotation 30 and the application fits inside bounds with no padding
- **THEN** the coordinate under each corner of the viewport is inside the bounds

#### Scenario: Fit at pitch 0

- **WHEN** the map is at pitch 0 and the application fits bounds, coordinates, or inside bounds
- **THEN** the camera is the same as in the release the fork starts from
