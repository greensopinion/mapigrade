## MODIFIED Requirements

### Requirement: Gallery
The demo SHALL open at a gallery that lists its showcases in this order: "Flyover", "Inspect features" and "3D routes". Each entry SHALL show the showcase's title and a sentence that states what the developer can try on its screen. Choosing an entry SHALL open the showcase's screen. Each showcase screen SHALL have its own map, which the screen creates when it opens and disposes when it closes. Each showcase screen SHALL have a control that goes back to the gallery, and the platform's back navigation SHALL also go back to the gallery. The gallery SHALL list only showcases of features that a user of an application sees or does; it SHALL NOT list settings such as HTTP headers, the layer's alignment or the tile cache size.

#### Scenario: Launch
- **WHEN** the demo starts without the recording mode
- **THEN** it shows the gallery with "Flyover", then "Inspect features", then "3D routes", each with a sentence that states what to try, and no map

#### Scenario: Open and close a showcase
- **WHEN** the developer chooses "Inspect features", and then uses the screen's control to go back
- **THEN** the inspect screen shows its map, and after going back the gallery is shown and the inspect screen's map is disposed

#### Scenario: Platform back navigation
- **WHEN** the developer uses the Android back gesture on the flyover screen
- **THEN** the demo shows the gallery

### Requirement: Recording mode
The demo SHALL have a recording mode on macOS, which the environment variable `MAPIGRADE_DEMO_RECORDING_SECONDS=<L>` turns on when the demo starts, where L is the clip length in whole seconds and is greater than 0. The environment variable `MAPIGRADE_DEMO_RECORDING_SHOWCASE` SHALL choose the recorded showcase: `flyover`, which is the choice when the variable isn't set, or `3d-routes`. Without `MAPIGRADE_DEMO_RECORDING_SECONDS`, the demo SHALL behave as the other requirements state. On iOS and Android the demo SHALL ignore both variables. When `MAPIGRADE_DEMO_RECORDING_SECONDS` is set to a value that isn't a whole number greater than 0, or `MAPIGRADE_DEMO_RECORDING_SHOWCASE` is set to another value than `flyover` and `3d-routes`, the demo SHALL write the reason to standard error and exit with a non-zero status.

In the recording mode the demo SHALL:

- show the chosen showcase's screen at launch, without the gallery and without the control that goes back to the gallery;
- show its window without a title bar and with square corners, with a content size of 1280 × 720 points, at launch;
- for the flyover, show the panel with the settings section collapsed, and keep the flyover status, the camera readout, the metrics and the statement that the routes are approximate;
- when the style has loaded, and for the flyover when the stages have loaded, play a warm-up pass that covers the run from its start to L + 1 s, with the flyover's panel stating that it is warming up;
- after the warm-up pass, move the camera to the run's camera at time 0 and hold it there until the map is at rest, meaning that it renders no frame for 1 s;
- then write the line `ready` to standard output, and start the run from time 0 when it reads the line `go` on standard input.

For the flyover, the run SHALL be the flyover that the other requirements describe, with the same camera at the same time for the same viewport size. For 3D routes, the run SHALL be the orbit of the requirement "3D routes", starting facing north, with the placement "Below buildings and labels" and Liberty. The demo SHALL exit with a non-zero status and write the reason to standard error when the map isn't at rest within 30 s after the warm-up pass, when `go` doesn't arrive within 30 s after `ready`, or when the layer reports a failure.

#### Scenario: Launch in the recording mode
- **WHEN** the macOS demo is started with `MAPIGRADE_DEMO_RECORDING_SECONDS=30`
- **THEN** it shows the flyover screen without the gallery and without the control that goes back, its window's content area is 1280 × 720 points, the settings section is collapsed, and the warm-up pass starts once the style and stages have loaded, without input

#### Scenario: Launch the 3D routes recording
- **WHEN** the macOS demo is started with `MAPIGRADE_DEMO_RECORDING_SECONDS=30` and `MAPIGRADE_DEMO_RECORDING_SHOWCASE=3d-routes`
- **THEN** it shows the 3D routes screen without the gallery and without the control that goes back, its window's content area is 1280 × 720 points, and the orbit's warm-up pass starts once the style has loaded, without input

#### Scenario: Unknown showcase
- **WHEN** the macOS demo is started with `MAPIGRADE_DEMO_RECORDING_SECONDS=30` and `MAPIGRADE_DEMO_RECORDING_SHOWCASE=inspect`
- **THEN** the demo writes the reason to standard error and exits with a non-zero status

#### Scenario: Warm-up length
- **WHEN** the recording mode runs with L = 30
- **THEN** the warm-up pass plays the flyover from 0 s to 31 s and then moves the camera back to the start of stage 9 in Nice

#### Scenario: Ready and go
- **WHEN** the map is at rest at the start after the warm-up pass
- **THEN** the demo writes `ready` to standard output and doesn't move the camera until it reads `go` on standard input, and then it plays the flyover from time 0

#### Scenario: Ready and go for 3D routes
- **WHEN** the 3D routes recording's map is at rest after the warm-up pass
- **THEN** the camera is at the orbit's start facing north, the demo writes `ready` and doesn't move the camera until it reads `go`, and then the orbit plays from its start

#### Scenario: Go doesn't arrive
- **WHEN** 30 s pass after `ready` without `go` on standard input
- **THEN** the demo writes the reason to standard error and exits with a non-zero status

#### Scenario: Normal launch
- **WHEN** the demo is started without the variable
- **THEN** the demo shows the gallery, the flyover screen behaves as before when it is opened, and the demo neither writes `ready` nor reads standard input

### Requirement: README recording
A script in `packages/demo/tool/` SHALL make the videos of the flyover and of 3D routes from the recording mode, with no input from the user while it runs. The script SHALL take the showcase as an optional argument, `flyover`, which is the choice without the argument, or `3d-routes`, and pass it to the recording mode. It SHALL write the flyover's video, which `README.md` shows, to `packages/demo/build/readme_demo.mp4`, and the 3D routes video to `packages/demo/build/readme_3d_routes.mp4`. The script SHALL take the clip length L from one value in the script, 20 s, and pass it to the recording mode. A video SHALL be an H.264 MP4 without sound, 1280 × 720 pixels, 60 frames per second and L seconds long, made from a capture of the demo window's content area at the display's pixel size, and SHALL be at most 10,000,000 bytes, so that GitHub accepts it as an attachment on its free plan. The capture SHALL start before the run, and the run SHALL start when the capture has its first frame, so that the video starts with the still camera at the start and the camera starts to move at the same time in every video. The capture SHALL record the demo's window even when other windows cover it.

A video SHALL start with a title card over the map that shows the Mapigrade logo, the title "Mapigrade demo" and a subtitle, in Helvetica Neue: "Flyover of the Tour de France Femmes avec Zwift 2026, stage 9, Nice" for the flyover, and "Orbit of downtown New York, with routes drawn below its 3D buildings and labels" for 3D routes. The card SHALL be fully shown until about 2.5 s and fade out by about 3.5 s.

Before it builds or starts the demo, the script SHALL check that the tools it needs are installed and that the app running it has Screen Recording permission. When one is missing, it SHALL state what is missing and how to get it, and exit with a non-zero status without changing the video file. The script SHALL replace the video file only when every step succeeded, and SHALL stop the demo when it exits. The script SHALL NOT upload the video. When the argument is another value, the script SHALL state the values it takes and exit with a non-zero status.

#### Scenario: Make the video
- **WHEN** the script runs on a Mac that has the tools and the permission
- **THEN** it writes `packages/demo/build/readme_demo.mp4`, an H.264 MP4 of 1280 × 720 pixels, 20 s at 60 frames per second, at most 10,000,000 bytes, without input from the user

#### Scenario: Make the 3D routes video
- **WHEN** the script runs with the argument `3d-routes` on a Mac that has the tools and the permission
- **THEN** it writes `packages/demo/build/readme_3d_routes.mp4`, an H.264 MP4 of 1280 × 720 pixels, 20 s at 60 frames per second, at most 10,000,000 bytes, showing two thirds of a turn of the orbit, without input from the user, and leaves `readme_demo.mp4` as it was

#### Scenario: Title card
- **WHEN** the first frame of the video is viewed
- **THEN** it shows the logo, "Mapigrade demo" and "Flyover of the Tour de France Femmes avec Zwift 2026, stage 9, Nice" over the map at the start of stage 9, and by 3.5 s the card is gone

#### Scenario: Title card for 3D routes
- **WHEN** the first frame of the 3D routes video is viewed
- **THEN** it shows the logo, "Mapigrade demo" and "Orbit of downtown New York, with routes drawn below its 3D buildings and labels" over downtown New York, and by 3.5 s the card is gone

#### Scenario: Covered window
- **WHEN** another window covers the demo's window during the run
- **THEN** the video shows the demo's window without the other window

#### Scenario: Permission missing
- **WHEN** the app that runs the script doesn't have Screen Recording permission
- **THEN** the script states which app needs it and where to grant it, exits with a non-zero status before it builds the demo, and leaves the video file as it was

#### Scenario: Tool missing
- **WHEN** ffmpeg isn't installed
- **THEN** the script states that ffmpeg is missing and the command to install it, exits with a non-zero status, and leaves the video file as it was

#### Scenario: Video too large
- **WHEN** the encoded video is over 10,000,000 bytes at every quality the script tries
- **THEN** the script states the sizes, exits with a non-zero status, and leaves the video file as it was

## ADDED Requirements

### Requirement: 3D routes
The 3D routes screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming, rotating and tilting enabled. When the screen opens, the map SHALL show downtown New York in Liberty at zoom 16 and pitch 45, facing north, with the camera over the Financial District. The screen SHALL draw these routes with one `MapigradePolylineLayer` in the layer's children, each along the streets or the water it names:

- a solid route along Broadway from Bowling Green to City Hall Park, with a border;
- a dashed route of the Staten Island Ferry from the Whitehall Terminal into the Upper Bay;
- a route along West Street from the Battery to Chambers Street, with a gradient from its start to its end;
- a route along Wall Street with a width in meters, which gets wider on the screen as the map zooms in.

Above the map, the screen SHALL draw a `flutter_map` pin at the start and at the end of each route, in the route's color at that end. The pins SHALL stand upright, facing the viewer, at every pitch and rotation.

The screen SHALL have a slider that sets the pitch from 0 to the `flutter_map` pitch limit and shows the current pitch, including a pitch that the tilt gesture set. The screen SHALL have a control that chooses the routes' placement: "Below buildings and labels", which is `LayerPlacement.belowLabels()` and is chosen when the screen opens, and "On top", which is `LayerPlacement.top()`. The screen SHALL offer the styles of the requirement "Styles", and choosing another style SHALL keep the camera, including its pitch, the routes, the pins and the chosen placement. The screen SHALL show a legend that names each route and how it is drawn.

The screen SHALL have a control that plays and stops an orbit around downtown New York, and the orbit SHALL be stopped when the screen opens. When the orbit starts, the camera SHALL move to the screen's opening center at zoom 16 and pitch 62, keeping its rotation, and the orbit SHALL then turn the map at a constant rate of one full turn every 30 seconds, around the center of the screen, so that the camera circles downtown and downtown stays at the center of the screen. The orbit SHALL continue until it is stopped. A touch, click or scroll on the map, a gesture, or the stop control SHALL stop the orbit and leave the camera where it is. Moving the pitch slider, changing the placement or choosing another style SHALL NOT stop the orbit.

#### Scenario: Open the 3D routes screen
- **WHEN** the developer chooses "3D routes" in the gallery
- **THEN** the map shows the Financial District in Liberty pitched at 45 degrees with its 3D buildings, the four routes and a pin at each end of each route, the slider shows 45, and the placement "Below buildings and labels" is chosen

#### Scenario: Buildings hide the routes
- **WHEN** the placement is "Below buildings and labels" and a tall building stands beside Broadway on the screen
- **THEN** the building hides the part of the route that it stands in front of, and street labels are drawn above the routes

#### Scenario: Routes on top
- **WHEN** the developer chooses "On top"
- **THEN** the routes are drawn above the buildings and the labels, no building or label hides any part of them, and the pins are drawn above the routes

#### Scenario: Change the pitch
- **WHEN** the developer moves the slider to the pitch limit and then to 0
- **THEN** the map tilts to the pitch limit and then shows the map from straight above, and at each pitch the routes follow their streets, the pins are at the ends of the routes, and the pins stand upright

#### Scenario: Tilt gesture
- **WHEN** the developer tilts the map with the `flutter_map` tilt gesture
- **THEN** the map's pitch changes, and the slider shows the new pitch

#### Scenario: Gestures on a pitched map
- **WHEN** the map is pitched at 45 degrees and the developer pans, zooms and rotates it
- **THEN** the routes stay on their streets and the pins stay at the ends of the routes, upright

#### Scenario: Width in meters
- **WHEN** the pitch is 0 and the developer zooms in from zoom 16 to zoom 18
- **THEN** the Wall Street route is about four times as wide on the screen, and the other routes keep their width

#### Scenario: Change style on the 3D routes screen
- **WHEN** the map is pitched at 30 degrees, the placement is "On top" and the developer chooses Positron
- **THEN** the map shows Positron with the camera where it was, at pitch 30, the four routes and the pins are drawn, and the placement is still "On top"

#### Scenario: Play the orbit
- **WHEN** the developer starts the orbit
- **THEN** the camera moves to the opening center at zoom 16 and pitch 62, the map turns a full turn in 30 seconds with downtown at the center of the screen, and the routes stay on their streets and the pins at the ends of the routes, upright, through the turn

#### Scenario: Stop the orbit by touch
- **WHEN** the developer touches the map during the orbit
- **THEN** the orbit stops, the camera stays where it was, and the gestures move the map

#### Scenario: Pitch during the orbit
- **WHEN** the developer moves the pitch slider to 30 during the orbit
- **THEN** the map tilts to 30 degrees and the orbit continues

## REMOVED Requirements

### Requirement: 3D view
**Reason**: The 3D routes showcase shows a tiltable map with 3D buildings, routes that follow the streets, and upright pins. The 3D view's route was a `flutter_map` polyline whose points didn't follow the streets.
**Migration**: Choose "3D routes" in the gallery.

### Requirement: Polylines
**Reason**: The 3D routes showcase replaces it, with the same routes, placement control, styles and legend, and adds tilt and upright pins.
**Migration**: Choose "3D routes" in the gallery.
