## MODIFIED Requirements

### Requirement: Gallery
The demo SHALL open at a gallery that lists its showcases in this order: "Flyover", "Inspect features" and "3D view". Each entry SHALL show the showcase's title and a sentence that states what the developer can try on its screen. Choosing an entry SHALL open the showcase's screen. Each showcase screen SHALL have its own map, which the screen creates when it opens and disposes when it closes. Each showcase screen SHALL have a control that goes back to the gallery, and the platform's back navigation SHALL also go back to the gallery. The gallery SHALL list only showcases of features that a user of an application sees or does; it SHALL NOT list settings such as HTTP headers, the layer's alignment or the tile cache size.

#### Scenario: Launch
- **WHEN** the demo starts without the recording mode
- **THEN** it shows the gallery with "Flyover", "Inspect features" and "3D view", in that order, each with a sentence that states what to try, and no map

#### Scenario: Open and close a showcase
- **WHEN** the developer chooses "Inspect features", and then uses the screen's control to go back
- **THEN** the inspect screen shows its map, and after going back the gallery is shown and the inspect screen's map is disposed

#### Scenario: Platform back navigation
- **WHEN** the developer uses the Android back gesture on the flyover screen
- **THEN** the demo shows the gallery


### Requirement: Flyover
The demo SHALL play a flyover on request. For each stage in the order of the stage data, the flyover SHALL show the start north up and unpitched at zoom 14, then follow the route from start to finish at zoom 16 and pitch 50 like a drone ahead of a rider, then turn the map back to north up and unpitched at zoom 14 at the finish, and then move to the next stage's start by zooming out, panning and zooming in. For a stage whose start and finish share one pin, the flyover SHALL not hold at the finish. While it follows a route, the flyover SHALL show a rider marker on the route, SHALL move like a drone that rounds tight bends rather than turning with every corner of the road, SHALL turn the map so that the direction of travel points up the screen, and SHALL keep the rider near a point below the center of the viewport so that the view shows the road ahead. The pitch SHALL change gradually as the flyover turns to and from the route, and SHALL be 0 while it holds at a start or finish and while it moves between stages. The map SHALL turn no faster than 25° per second, and its turn rate and the camera's speed SHALL change gradually; where the road turns faster, the camera SHALL slow down. The rider marker SHALL be shown only while the flyover follows a route. The camera SHALL be a function of the time since the flyover started and of the viewport size when it started, so that two runs in the same viewport show the same camera at the same time. The developer SHALL be able to choose a warm-up pass, which plays the whole flyover once before the run that starts from the beginning again, so that the run shows tiles that are already loaded. A touch, click or scroll on the map, or the stop control, SHALL stop the flyover and leave the camera where it is.

#### Scenario: Deterministic camera
- **WHEN** the flyover's camera is computed twice for the same viewport size at the same time since the start
- **THEN** both computations give the same center, zoom, rotation and pitch

#### Scenario: Stage order
- **WHEN** the flyover plays to the end
- **THEN** it shows stage 9, then stage 7, then stage 4, and ends north up at the finish of stage 4 in Dijon

#### Scenario: Following a route
- **WHEN** the flyover follows the route of stage 7
- **THEN** the zoom is 16, the pitch is 50, a rider marker moves along the route below the center of the viewport, the rider moves up the screen, and the map turns smoothly with the road on the climb of Mont Ventoux, rounding the hairpins without spinning or jerking

#### Scenario: Rider marker outside the follow
- **WHEN** the flyover holds at a start or moves between stages, or is stopped
- **THEN** no rider marker is shown

#### Scenario: Warm-up pass
- **WHEN** the developer starts the flyover with the warm-up pass chosen
- **THEN** the flyover plays once while the demo states that it is warming up, then starts again from the start of stage 9

#### Scenario: Stop by touch
- **WHEN** the developer touches the map during the flyover
- **THEN** the flyover stops, the camera stays where it was, and the gestures move the map

## ADDED Requirements

### Requirement: 3D view
The 3D view screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, in the Liberty style, which draws buildings in 3D. When the screen opens, the camera SHALL be over Midtown Manhattan at zoom 16 and pitch 45, facing north. The screen SHALL have a slider that sets the pitch from 0 to 60 degrees and shows the current pitch, and the `flutter_map` gestures for panning, zooming and rotating SHALL be enabled. Above the map, the screen SHALL draw a route as a `flutter_map` polyline, which lies on the ground, and markers at points on the route, which face the viewer.

#### Scenario: Open the 3D view
- **WHEN** the developer chooses "3D view" in the gallery
- **THEN** the screen shows Midtown Manhattan pitched at 45 degrees with 3D buildings, the route and the markers, and the slider shows 45

#### Scenario: Change the pitch
- **WHEN** the developer moves the slider to 60 and then to 0
- **THEN** the map and the overlays tilt to 60 degrees and then show the map from straight above, with the route and the markers on the map at each pitch

#### Scenario: Gestures on a pitched map
- **WHEN** the map is pitched at 45 degrees and the developer pans, zooms and rotates it
- **THEN** the route and the markers stay on the map
