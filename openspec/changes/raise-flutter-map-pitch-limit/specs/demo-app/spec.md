## MODIFIED Requirements

### Requirement: 3D view
The 3D view screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, in the Liberty style, which draws buildings in 3D. When the screen opens, the camera SHALL be over Midtown Manhattan at zoom 16 and pitch 45, facing north. The screen SHALL have a slider that sets the pitch from 0 to the `flutter_map` pitch limit, 85 degrees, and shows the current pitch, and the `flutter_map` gestures for panning, zooming and rotating SHALL be enabled. Above the map, the screen SHALL draw a route as a `flutter_map` polyline, which lies on the ground, and markers at points on the route, which face the viewer.

#### Scenario: Open the 3D view
- **WHEN** the developer chooses "3D view" in the gallery
- **THEN** the screen shows Midtown Manhattan pitched at 45 degrees with 3D buildings, the route and the markers, and the slider shows 45

#### Scenario: Change the pitch
- **WHEN** the developer moves the slider to 85 and then to 0
- **THEN** the map and the overlays tilt to 85 degrees, with the area above the far limit showing the map's background, and then show the map from straight above, with the route and the markers on the map at each pitch

#### Scenario: Gestures on a pitched map
- **WHEN** the map is pitched at 45 degrees and the developer pans, zooms and rotates it
- **THEN** the route and the markers stay on the map
