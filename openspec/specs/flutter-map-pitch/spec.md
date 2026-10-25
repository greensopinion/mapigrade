# flutter-map-pitch Specification

## Purpose

Pitch in our `flutter_map` fork: a camera that looks at the ground at an angle, a projection that matches MapLibre Native's, and the way layers draw and respond to input when the map is pitched.

## Requirements

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

At pitch 0, the camera's projections, visible bounds and the positions at which layers draw SHALL be the same as without pitch support. While the maximum pitch is 0, gesture behavior SHALL be the same as without pitch support.

#### Scenario: Existing tests

- **WHEN** the pitch is 0
- **THEN** the fork's existing tests pass without changes

#### Scenario: Gestures at the default maximum pitch

- **WHEN** the maximum pitch is 0 and the user drags vertically with two fingers, pinches, twists two fingers, or drags with Ctrl held
- **THEN** the map moves, zooms and rotates as in the release the fork starts from, and the pitch stays 0

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

### Requirement: Pitch gestures enabled

The interactive flags SHALL include a flag for pitch gestures, and the flag SHALL be part of the set of all interactive flags. The two-finger pitch gesture and Ctrl-drag pitch SHALL be enabled only while the pitch flag is set and the maximum pitch is above 0. While they are not enabled, two-finger gestures and Ctrl-drag SHALL behave as in the release the fork starts from.

#### Scenario: Pitch flag removed

- **WHEN** the maximum pitch is 60, the interactive flags are all flags except the pitch flag, and the user drags two fingers upward side by side
- **THEN** the map moves with the fingers and the pitch doesn't change

#### Scenario: All flags at the default maximum pitch

- **WHEN** the interactive flags are all flags, the maximum pitch is 0, and the user drags two fingers upward side by side
- **THEN** the map moves with the fingers and the pitch stays 0

### Requirement: Two-finger pitch gesture

While pitch gestures are enabled, the map SHALL recognize a pitch gesture when exactly two fingers touch the map, the line between them is within 45° of horizontal when the gesture starts, and both fingers move vertically in the same direction, each more vertically than horizontally, by at least the pitch threshold. The map SHALL rule the pitch gesture out when the line between the fingers is more than 45° from horizontal when the gesture starts, when a finger moves more horizontally than vertically, when the fingers move vertically in opposite directions, or when one finger moves by the pitch threshold and the other finger doesn't move within 100 ms. Once recognized, the pitch SHALL be the pitch at the start of the gesture minus 0.5° for each px that the midpoint between the fingers has moved down since the start, limited to the range from 0 to the maximum pitch. The pitch gesture SHALL keep the center coordinate at the center of the viewport and SHALL NOT change the zoom or the rotation. When the user lifts the fingers after a pitch gesture, the map SHALL NOT fling. The application SHALL be able to set the pitch threshold in px in the interaction options.

#### Scenario: Pitch up

- **WHEN** the pitch is 10, the maximum pitch is 60, and the user places two fingers side by side and moves both 40 px up
- **THEN** the pitch is 30, the zoom and rotation are unchanged, and the center coordinate is at the center of the viewport

#### Scenario: Pitch limited to the maximum

- **WHEN** the pitch is 40, the maximum pitch is 45, and the user moves two fingers side by side 100 px up
- **THEN** the pitch is 45

#### Scenario: Pitch down to 0

- **WHEN** the pitch is 20 and the user moves two fingers side by side 100 px down
- **THEN** the pitch is 0

#### Scenario: Fingers one above the other

- **WHEN** the user places two fingers so that the line between them is 60° from horizontal and moves both 40 px up
- **THEN** the pitch doesn't change and the map moves with the fingers

#### Scenario: Three fingers

- **WHEN** the user moves three fingers side by side 40 px up
- **THEN** the pitch doesn't change

#### Scenario: Pitch threshold

- **WHEN** the pitch threshold is 20 and the user moves two fingers side by side 10 px up and lifts them
- **THEN** the pitch, center, zoom and rotation don't change

#### Scenario: No fling after a pitch gesture

- **WHEN** the user pitches the map with two fingers and lifts them while they still move
- **THEN** the center doesn't change after the fingers are lifted

### Requirement: Other two-finger gestures while pitch is enabled

While pitch gestures are enabled and a two-finger gesture can still become a pitch gesture, the map SHALL NOT zoom, rotate or move for that gesture. When the pitch gesture is ruled out, the map SHALL zoom, rotate and move for the whole gesture so far, as it would have without pitch gestures, and continue as without pitch gestures. When the pitch gesture is recognized, the map SHALL NOT zoom, rotate or move for the rest of the gesture.

#### Scenario: Pinch while pitch is enabled

- **WHEN** the maximum pitch is 60 and the user pinches two fingers apart
- **THEN** after the pinch, the zoom and the coordinate under the focal point are the same as for the same pinch with the maximum pitch at 0

#### Scenario: Spread after a recognized pitch gesture

- **WHEN** the user pitches the map with two fingers and then spreads them apart without lifting them
- **THEN** the zoom, center and rotation don't change

#### Scenario: Gesture ends before a decision

- **WHEN** the user places two fingers side by side and lifts them without moving them
- **THEN** the pitch, center, zoom and rotation don't change

### Requirement: Ctrl-drag pitch

While pitch gestures are enabled, a drag with the cursor/keyboard rotation trigger key held SHALL pitch and rotate the map as MapLibre GL JS does by default. Vertical movement SHALL change the pitch by 0.5° per px, increasing it when the cursor moves up, and SHALL NOT rotate the map. Horizontal movement SHALL rotate the map about the viewport center and SHALL NOT change the pitch: when the cursor is more than 100 px above or below the viewport center, by the angle about the viewport center through which the horizontal movement turns the cursor; otherwise by 0.8° per px. Either way the map SHALL turn in the direction that the cursor moves around the viewport center. The pitch and the rotation SHALL keep the center coordinate at the center of the viewport and SHALL NOT change the zoom. The cursor rotation behaviour option and the option to set north on click SHALL have no effect while pitch gestures are enabled.

#### Scenario: Ctrl-drag up

- **WHEN** the pitch is 10, the maximum pitch is 60, and the user drags the cursor 40 px straight up with Ctrl held
- **THEN** the pitch is 30 and the rotation is unchanged

#### Scenario: Ctrl-drag sideways below the center

- **WHEN** the maximum pitch is 60 and the user drags the cursor horizontally with Ctrl held, 200 px below the viewport center
- **THEN** the map rotates by the angle that the cursor's movement subtends at the viewport center, in the direction that the cursor moves around the center, and the pitch is unchanged

#### Scenario: Ctrl-drag near the center

- **WHEN** the maximum pitch is 60 and the user drags the cursor 10 px to the right with Ctrl held, 50 px below the viewport center
- **THEN** the map rotates by 8° in the direction that the cursor moves around the center

#### Scenario: Set north on click while pitch is enabled

- **WHEN** the maximum pitch is 60, set north on click is enabled, and the user clicks without dragging with Ctrl held
- **THEN** the rotation doesn't change

### Requirement: Pitch gesture events

A pitch gesture SHALL emit a pitch start event when it starts, a pitch event for each change of the pitch, and a pitch end event when it ends. A two-finger pitch gesture starts when it is recognized and ends when the fingers are lifted, and its events SHALL have the existing event sources of multi-finger gestures: the multi-finger start source for the start event, the multi-finger update source for pitch events, and the multi-finger end source for the end event. A two-finger pitch gesture SHALL emit no move start, move, or move end events. A Ctrl-drag while pitch gestures are enabled starts when the button is pressed and ends when it is released; it SHALL emit a rotate start event and a pitch start event when it starts and a rotate end event and a pitch end event when it ends, and all of its events SHALL have the existing cursor/keyboard rotation source.

#### Scenario: Two-finger pitch events

- **WHEN** the user pitches the map with two fingers from 10 to 30 and lifts them
- **THEN** one pitch start event, one or more pitch events whose last has pitch 30, and one pitch end event are emitted, in that order, with the multi-finger sources

#### Scenario: Ctrl-drag pitch events

- **WHEN** the maximum pitch is 60 and the user presses the button with Ctrl held, drags the cursor up, and releases the button
- **THEN** a rotate start and a pitch start event, one or more pitch events, and a rotate end and a pitch end event are emitted, in that order, all with the cursor/keyboard rotation source

### Requirement: Camera fit when pitched

When the map is pitched, a camera fit SHALL keep the camera's pitch and rotation and choose its center and zoom as follows:

- Fitting bounds SHALL choose a center and zoom at which the four corners of the bounds, converted to screen positions, lie inside the viewport reduced by the padding.
- Fitting coordinates SHALL choose a center and zoom at which every coordinate, converted to a screen position, lies inside the viewport reduced by the padding.
- Fitting inside bounds SHALL choose a center and zoom at which the coordinates under the four corners of the viewport reduced by the padding lie inside the bounds.

Each fit SHALL choose the largest such zoom, within 0.01, unless the minimum zoom, the maximum zoom or rounding to an integer zoom limits it. At pitch 0, each fit SHALL return the same camera as the release the fork starts from.

#### Scenario: Fit bounds

- **WHEN** the map is at pitch 60 and rotation 30 and the application fits bounds with no padding
- **THEN** the pitch is 60, the rotation is 30, each corner of the bounds is within the viewport, and at least one corner is within 1 px of the edge of the viewport

#### Scenario: Fit coordinates with padding

- **WHEN** the map is at pitch 45 and the application fits five coordinates with a padding of 20 px on each side
- **THEN** each coordinate is at least 20 px inside each edge of the viewport, and at least one coordinate is within 1 px of 20 px from an edge

#### Scenario: Fit inside bounds

- **WHEN** the map is at pitch 60 and rotation 30 and the application fits inside bounds with no padding
- **THEN** the coordinate under each corner of the viewport is inside the bounds

#### Scenario: Fit at pitch 0

- **WHEN** the map is at pitch 0 and the application fits bounds, coordinates, or inside bounds
- **THEN** the camera is the same as in the release the fork starts from

### Requirement: Contain constraints when pitched

The constraint that contains the camera in bounds SHALL keep, at every pitch, the same rectangle inside its bounds as at pitch 0: the rectangle, in projected pixels at the camera's zoom, that is centered on the center coordinate and contains the viewport rotated by the camera's rotation. The constraint that contains the camera between two latitudes SHALL keep the same rectangle between them. Neither constraint SHALL refuse a camera because of its pitch, so ground beyond the bounds can be visible toward the far edge of a pitched map.

#### Scenario: Pitch change inside the bounds

- **WHEN** the map has a contain constraint whose bounds contain the rotated viewport at the current zoom, and the application sets the pitch to 60
- **THEN** the pitch is 60 and the center is unchanged

#### Scenario: Constrained center independent of pitch

- **WHEN** the map has a contain constraint and the application moves the center beyond the bounds at pitch 60
- **THEN** the constrained center is the same as for the same move at pitch 0
