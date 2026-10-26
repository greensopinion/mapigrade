## ADDED Requirements

### Requirement: Split view
The flyover screen SHALL have a setting "Split view", which is off when the screen opens. While it is on, the map SHALL be divided at the vertical line through the center of the viewport: the left half SHALL show the chosen style as the package draws it, and the right half SHALL show the OpenStreetMap standard raster tiles from `tile.openstreetmap.org`, requested with the demo's application ID as the user agent, which the OpenStreetMap tile usage policy requires. Choosing a style SHALL change only the left half. The two halves SHALL show the map at the same camera in every displayed frame, at rest and while the camera moves by a gesture or by the flyover, so that a road or a stage route that crosses the seam continues across it within 1 logical pixel. The stage overlays and the rider SHALL be drawn above both halves.

While the split view is on, the screen SHALL draw a vertical line 1 logical pixel wide at the seam, a label "Mapigrade" to the left of the line and a label "Raster (OSM)" to the right of it, near the bottom of the map and clear of the attribution. The line and the labels SHALL stay in place while the camera moves, and a gesture that starts on them SHALL move the map as it does elsewhere on the map. While the split view is off, the screen SHALL load no raster tiles and SHALL draw neither the line nor the labels.

#### Scenario: Split view off at opening
- **WHEN** the developer opens the flyover screen
- **THEN** the split view setting is off, the whole map shows Liberty, and there is no seam

#### Scenario: Turn on the split view
- **WHEN** the developer turns on the split view over Nice
- **THEN** the left half of the map shows Liberty and the right half shows the OpenStreetMap raster tiles of the same area, with the line at the seam and the labels "Mapigrade" and "Raster (OSM)" on either side of it

#### Scenario: Seam while the camera moves
- **WHEN** the split view is on and the flyover follows a route at pitch 50, or the developer pans, zooms or rotates the map
- **THEN** in every displayed frame the roads and the stage route that cross the seam continue across it, and the route and the rider are drawn above both halves

#### Scenario: Change style in the split view
- **WHEN** the split view is on and the developer chooses Positron
- **THEN** the left half shows Positron, the right half still shows the OpenStreetMap raster tiles, and the camera and the split view stay as they were

#### Scenario: Gesture on the seam
- **WHEN** the split view is on and the developer drags the map from a point on the line or on a label
- **THEN** the map moves as it does for a drag that starts anywhere else

#### Scenario: Turn off the split view
- **WHEN** the developer turns off the split view
- **THEN** the whole map shows the chosen style, and the line and the labels are gone

## MODIFIED Requirements

### Requirement: Flyover screen
The flyover screen SHALL be the screen that the requirements "Styles", "Metrics display", "Stage overlays", "Stage data", "Flyover", "Camera readout", "Attribution" and "Split view" describe. When the flyover screen opens, its camera SHALL be over Nice at the start of stage 9, the flyover SHALL be stopped, and its settings SHALL be the settings at launch that those requirements state. Going back to the gallery SHALL stop the flyover.

#### Scenario: Open the flyover screen
- **WHEN** the developer chooses "Flyover" in the gallery
- **THEN** the map shows Nice in Liberty with the stage overlays, the camera readout and the metrics, and the flyover isn't playing

#### Scenario: Go back during the flyover
- **WHEN** the developer goes back to the gallery while the flyover plays, and then chooses "Flyover" again
- **THEN** the flyover stops when the gallery is shown, and the screen opens again over Nice with the flyover stopped
