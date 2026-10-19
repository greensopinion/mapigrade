# demo-app Specification

## Purpose

Defines the demo app that developers build from source to try `flutter_mapigrade` on their own devices: styles, gestures, overlays, frame rates, a camera readout, and a fixed flyover over stages of the Tour de France Femmes avec Zwift 2026.

## Requirements

### Requirement: Demo app
The repository SHALL contain a demo app in `packages/demo/` that is a member of the pub workspace and is not published. The demo SHALL run on Android, iOS and macOS, on the versions and architectures the package supports. Its Dart code SHALL import only the main library of the package, `package:flutter_mapigrade/flutter_mapigrade.dart`, and no library under `package:flutter_mapigrade/src/`. The demo SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming and rotating enabled.

#### Scenario: Demo imports
- **WHEN** the demo's Dart files are inspected
- **THEN** they import `package:flutter_mapigrade/flutter_mapigrade.dart` and no other library of the package

#### Scenario: Demo runs on each platform
- **WHEN** the demo is built and run on macOS, on the iOS simulator and on the Android emulator
- **THEN** on each platform the map appears, and dragging, pinching and rotating with two fingers (or the equivalent mouse and trackpad input on macOS) move, zoom and rotate the map

#### Scenario: Device without the native library
- **WHEN** the demo runs where `MapigradeLayer.isSupported` is false
- **THEN** the demo states that the map isn't supported on this device instead of the map, and continues to run

#### Scenario: Map failure
- **WHEN** the layer reports a failure, for example because a style can't be loaded
- **THEN** the demo shows the failure's message and continues to run

### Requirement: Styles
The demo SHALL let the developer choose one of these styles, none of which needs an API key: OpenFreeMap Liberty (`https://tiles.openfreemap.org/styles/liberty`), OpenFreeMap Bright (`https://tiles.openfreemap.org/styles/bright`), OpenFreeMap Positron (`https://tiles.openfreemap.org/styles/positron`) and MapLibre demo tiles (`https://demotiles.maplibre.org/style.json`). Liberty SHALL be the style at launch. Choosing a style SHALL keep the camera, the overlays and the metrics.

#### Scenario: Change style
- **WHEN** the developer chooses Positron while the camera is over Nice
- **THEN** the map shows Positron, the camera stays over Nice, and the overlays and the metrics display continue

### Requirement: Metrics display
The demo SHALL display, updated once per second: the map's displayed frames per second, the map's rendered frames per second, the map's average render time per rendered frame in milliseconds, and the Flutter UI frames per second. The map values SHALL come from two consecutive snapshots of one `LayerMetrics` given to the layer: each rate is the difference of the count divided by the difference of the time. The average render time SHALL be the difference of the render time divided by the difference of the rendered frames, and SHALL be shown as unavailable when no frame was rendered in the interval. The UI rate SHALL come from the frame timings that Flutter reports. The display SHALL state that the map renders no frames while it is at rest.

#### Scenario: Camera moves
- **WHEN** the developer drags the map continuously for several seconds
- **THEN** the displayed and rendered frame rates and the average render time are shown and change from one second to the next

#### Scenario: Map at rest
- **WHEN** the map has loaded its tiles and the camera hasn't moved for a second
- **THEN** the displayed and rendered frame rates are 0, the average render time is shown as unavailable, and the display states that the map is at rest

### Requirement: Stage overlays
The demo SHALL draw, for each stage in the stage data, a polyline along the route, a green pin at the start and a red pin at the finish. The start pin SHALL have a bubble that states the race, the stage number, the start and finish, the distance in kilometres and the stage winner. When a stage's start and finish are less than 500 m apart, the demo SHALL draw one pin for both, whose bubble states that the stage starts and finishes there. Pins and bubbles SHALL stay upright when the map rotates. The developer SHALL be able to hide and show the overlays.

#### Scenario: Stage 7 overlays
- **WHEN** the camera shows stage 7
- **THEN** a polyline runs from a green pin at La Voulte-sur-Rhône to a red pin at Mont Ventoux, and the green pin's bubble states "Tour de France Femmes avec Zwift 2026", "Stage 7", "La Voulte-sur-Rhône – Mont Ventoux", "146.8 km" and "Katarzyna Niewiadoma-Phinney"

#### Scenario: Loop stage
- **WHEN** the camera shows stage 9, Nice to Nice
- **THEN** one pin marks the start and the finish, and its bubble states that the stage starts and finishes in Nice

#### Scenario: Rotated map
- **WHEN** the developer rotates the map by 90 degrees
- **THEN** the polylines rotate with the map, and the pins and bubbles stay upright at their coordinates

### Requirement: Stage data
The demo SHALL read the stages from an asset file that contains, for each stage, its number, date, start, finish, distance, type, winner, the winner's team, and the route coordinates. The file SHALL contain these stages of the Tour de France Femmes avec Zwift 2026, in this order, with the facts that the race's official site, letourfemmes.fr, states:

| Stage | Date | Start | Finish | Distance | Type | Winner | Team |
|---|---|---|---|---|---|---|---|
| 9 | 9 August 2026 | Nice | Nice | 99.2 km | Mountain | Demi Vollering | FDJ United–Suez |
| 7 | 7 August 2026 | La Voulte-sur-Rhône | Mont Ventoux | 146.8 km | Mountain | Katarzyna Niewiadoma-Phinney | Canyon//SRAM |
| 4 | 4 August 2026 | Gevrey-Chambertin | Dijon | 21 km | Individual time trial | Marlen Reusser | Movistar Team |

The route coordinates SHALL be approximate: a script in `packages/demo/tool/` SHALL compute them from waypoints stored in the repository, with a router that uses OpenStreetMap data, and the repository SHALL contain the script's output. Where the router goes to a waypoint and back along the same road, the script SHALL remove that spur, because the race doesn't ride it. Running the script again with the same waypoints SHALL write the same file, unless the router's data has changed. The demo SHALL state that the routes are approximate.

#### Scenario: Data file contents
- **WHEN** the demo's tests read the asset file
- **THEN** it contains stages 9, 7 and 4 in that order, with the facts in the table above, and each route starts within 1 km of its stage's start and ends within 1 km of its stage's finish

#### Scenario: Routes are labelled approximate
- **WHEN** the overlays are shown
- **THEN** the demo states that the routes are approximate

### Requirement: Flyover
The demo SHALL play a flyover on request. For each stage in the order of the stage data, the flyover SHALL show the start north up at zoom 14, then follow the route from start to finish at zoom 16 like a drone ahead of a rider, then turn the map back to north up at zoom 14 at the finish, and then move to the next stage's start by zooming out, panning and zooming in. For a stage whose start and finish share one pin, the flyover SHALL not hold at the finish. While it follows a route, the flyover SHALL show a rider marker on the route, SHALL move like a drone that rounds tight bends rather than turning with every corner of the road, SHALL turn the map so that the direction of travel points up the screen, and SHALL keep the rider near a point below the center of the viewport so that the view shows the road ahead. The map SHALL turn no faster than 25° per second, and its turn rate and the camera's speed SHALL change gradually; where the road turns faster, the camera SHALL slow down. The rider marker SHALL be shown only while the flyover follows a route. The camera SHALL be a function of the time since the flyover started and of the viewport size when it started, so that two runs in the same viewport show the same camera at the same time. The developer SHALL be able to choose a warm-up pass, which plays the whole flyover once before the run that starts from the beginning again, so that the run shows tiles that are already loaded. A touch, click or scroll on the map, or the stop control, SHALL stop the flyover and leave the camera where it is.

#### Scenario: Deterministic camera
- **WHEN** the flyover's camera is computed twice for the same viewport size at the same time since the start
- **THEN** both computations give the same center, zoom and rotation

#### Scenario: Stage order
- **WHEN** the flyover plays to the end
- **THEN** it shows stage 9, then stage 7, then stage 4, and ends north up at the finish of stage 4 in Dijon

#### Scenario: Following a route
- **WHEN** the flyover follows the route of stage 7
- **THEN** the zoom is 16, a rider marker moves along the route below the center of the viewport, the rider moves up the screen, and the map turns smoothly with the road on the climb of Mont Ventoux, rounding the hairpins without spinning or jerking

#### Scenario: Rider marker outside the follow
- **WHEN** the flyover holds at a start or moves between stages, or is stopped
- **THEN** no rider marker is shown

#### Scenario: Warm-up pass
- **WHEN** the developer starts the flyover with the warm-up pass chosen
- **THEN** the flyover plays once while the demo states that it is warming up, then starts again from the start of stage 9

#### Scenario: Stop by touch
- **WHEN** the developer touches the map during the flyover
- **THEN** the flyover stops, the camera stays where it was, and the gestures move the map

### Requirement: Camera readout
The demo SHALL display the latitude and longitude of the map's center, in degrees to 5 decimal places, and the map's zoom, to 2 decimal places. The display SHALL update with every camera change, whether a gesture or the flyover moves the camera.

#### Scenario: Readout during a pan
- **WHEN** the developer drags the map
- **THEN** the displayed center changes with the map while the drag continues, and the zoom stays the same

#### Scenario: Readout during the flyover
- **WHEN** the flyover follows a route
- **THEN** the displayed center changes on every frame and the displayed zoom is 16.00

### Requirement: Attribution
The demo SHALL show on the map the attribution that the chosen style requires, and an OpenStreetMap attribution with a link to its copyright page for the routes. For the OpenFreeMap styles the attribution SHALL name OpenFreeMap, OpenMapTiles and OpenStreetMap.

#### Scenario: OpenFreeMap style
- **WHEN** the style is Liberty
- **THEN** the map shows an attribution that names OpenFreeMap, OpenMapTiles and OpenStreetMap, and opening the OpenStreetMap entry leads to its copyright page
