## MODIFIED Requirements

### Requirement: Queries aligned with the displayed map frame
The system SHALL run each query against the features at the positions where the displayed map frame draws them, including while the camera moves, the map renders ahead of the displayed frame, camera prediction is on, or the map is pitched. The displayed map frame SHALL be the frame that the layer displayed in the last Flutter frame it built before the query was called. Before the map has displayed a frame, the system SHALL use the live `flutter_map` camera. For features that the style draws as lines, fills, circles or other non-symbol layers, the alignment SHALL be within 1 logical pixel. Symbol features (labels and icons) SHALL be matched where MapLibre placed them last, which can be behind the displayed frame while the camera moves.

#### Scenario: Query during a pan
- **WHEN** the `flutter_map` camera pans at 1,000 logical px/s, and in a Flutter frame the application queries with a radius of 2 at the screen position where the displayed map frame draws a line that the style draws 1 logical pixel wide
- **THEN** the result contains the line's feature

#### Scenario: Query beside a line during a pan
- **WHEN** the `flutter_map` camera pans at 1,000 logical px/s, and in a Flutter frame the application queries with a radius of 2 at a point 6 logical pixels from where the displayed map frame draws a line that the style draws 1 logical pixel wide
- **THEN** the result doesn't contain the line's feature

#### Scenario: Query with camera prediction
- **WHEN** the layer has camera prediction on with a lead of 1, the camera pans at 1,000 logical px/s, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line
- **THEN** the result contains the line's feature

#### Scenario: Rotated and zooming camera
- **WHEN** the `flutter_map` rotation is 30 degrees, the camera zooms in continuously, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line
- **THEN** the result contains the line's feature

#### Scenario: Antimeridian
- **WHEN** the camera pans across the antimeridian, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line
- **THEN** the result contains the line's feature

#### Scenario: Pitched map
- **WHEN** the `flutter_map` pitch is 60 degrees, and the application queries with a radius of 2 at the screen position where the displayed map frame draws a line near the top of the viewport
- **THEN** the result contains the line's feature
