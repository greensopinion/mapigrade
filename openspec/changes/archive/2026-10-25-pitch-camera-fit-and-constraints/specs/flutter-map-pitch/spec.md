## ADDED Requirements

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
