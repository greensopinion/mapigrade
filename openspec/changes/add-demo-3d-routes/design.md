## Context

The polyline showcase is `PolylineScreen` in `lib/src/polylines/polyline_screen.dart`, with its route data in `lib/src/polylines/routes.dart` (D204, D205). Its `MapOptions` set no `maxPitch`, so `flutter_map`'s default of 0 applies and the tilt gesture has no effect. The 3D view is `ThreeDScreen` in `lib/src/three_d/three_d_screen.dart`. It sets `maxPitch: MapOptions.pitchLimit` and keeps a pitch slider in step with the camera through a `MapController` and `onMapEvent`.

In the `flutter_map` fork, `InteractiveFlag.all` includes `InteractiveFlag.pitch`: a two-finger vertical drag, or a vertical drag with the rotate key or button on desktop, tilts the map while `maxPitch` is above 0.

The open change `raise-flutter-map-pitch-limit` modifies the requirement "3D view", which this change removes.

## Goals / Non-Goals

**Goals:**
- Keep the routes, the placement control, the styles and the legend of the polyline showcase as they are, and add tilt and pins.

**Non-Goals:**
- Changing the routes' points or how they are drawn.
- Hit testing on the pins.
- Changing the flyover.

## Decisions

### D208: Files

The screen and its data move to `lib/src/routes/`: `routes_screen.dart` holds `RoutesScreen`, and `routes.dart` keeps its name. The test moves to `test/routes/routes_test.dart`. `lib/src/three_d/` is deleted.

Alternative considered: keep `lib/src/polylines/` and `PolylineScreen`. Rejected because the showcase is no longer only about polylines, and its title would not match its class.

### D209: Pitch

`MapOptions` set `initialPitch: 45` and `maxPitch: MapOptions.pitchLimit`, and leave the rotation at 0, so the camera faces north. The default interaction flags enable the tilt gesture. The panel gets the 3D view's pitch readout and slider below the style picker: the slider calls `MapController.pitch`, and `onMapEvent` updates the shown pitch whenever the camera's pitch changes, so the slider follows the gesture. A style change gives `MapigradeLayer` a new style URL and leaves the `FlutterMap` and its camera as they are, so the pitch is kept, as the center and zoom are today.

### D210: Pins

A `MarkerLayer` with `rotate: true` follows the `MapigradePolylineLayer` in the `MapigradeLayer`'s children, so the pins are drawn at the displayed map frame's camera and stand upright. Each pin is `Icons.location_pin`, 36 px, aligned at its bottom center. `routes.dart` builds the pins once from `demoRoutes`, a pin at the first and at the last point of each route. A pin's color is the route's color, fully opaque so that the translucent Wall Street route gets a visible pin. For the gradient route, the start pin takes the first gradient color and the end pin the last.

The pins are Flutter overlays, so they are drawn above the map with either placement. The scenarios "Routes on top" and "Open the 3D routes screen" state this.

### D211: Gallery entry

The entry is third, titled "3D routes", with the sentence "Tilt downtown New York to see routes drawn below its 3D buildings and labels, with pins that stand upright." The panel's title is "3D routes".

### D212: Orbit

A play/stop `IconButton` in the panel's actions starts and stops the orbit, as on the flyover screen. Starting it calls `MapController.move` and `MapController.pitch` once to put the camera at the opening center, zoom 16 and pitch 62 with its current rotation, and then starts a `Ticker`. On each tick the screen calls `MapController.rotate` with the starting rotation plus 12° per second of the ticker's elapsed time. `rotate` turns the map around the camera's center, which on a pitched map is the point the camera looks at, so the camera circles that point.

The orbit stops as the flyover does (D119): on a pointer down on the map, and on a `MapEvent` whose source is neither `MapEventSource.mapController` nor `MapEventSource.nonRotatedSizeChange`. The slider's `MapController.pitch` calls have the source `mapController`, so they don't stop the orbit. The ticker is disposed with the screen.

A full turn at zoom 16 and pitch 62 puts the camera a few kilometers from downtown, offshore over the harbor on the south side and over Manhattan, Brooklyn and Jersey City on the others.

Alternative considered: an arc that swings back and forth across the harbor, so that the camera stays over water. The user chose the full turn, which shows downtown from every side.

### D213: Recording 3D routes

`recording.dart` moves from `lib/src/flyover/` to `lib/src/common/`, because both screens use it. `Recording` gets a `showcase` field from `MAPIGRADE_DEMO_RECORDING_SHOWCASE`, an enum with `flyover` and `routes3d`, and `main.dart` opens the chosen screen. `RoutesScreen` takes an optional `Recording`, as `FlyoverScreen` does. The macOS window setup in `MainFlutterWindow.swift` depends only on `MAPIGRADE_DEMO_RECORDING_SECONDS`, so it doesn't change.

In the recording mode, `RoutesScreen` starts the orbit when the style has loaded, facing north, as the warm-up pass. After L + 1 s it stops the ticker, puts the camera back at the orbit's start, and calls `Recording.ready` with the screen's `LayerMetrics`. When `go` arrives, it starts the orbit again from rotation 0. A layer failure calls `Recording.fail`, as on the flyover screen. The 3D routes panel has no settings section, so it is shown as it is.

`record_readme.sh` takes the showcase as its first argument and chooses the subtitle and the output file from it. The clip length stays one value, 20 s, for both showcases, so the 3D routes video shows two thirds of a turn. It exports `MAPIGRADE_DEMO_RECORDING_SHOWCASE`. `capture_window` copies its environment to the demo, so the helper doesn't change. A 30 s clip of one full turn was over 10,000,000 bytes at every CRF the script tries, from 18,499,129 bytes at CRF 24 to 13,636,997 bytes at CRF 26, because the whole frame of 3D buildings moves. The user chose a 20 s clip over CRFs from 27 to 30.

Alternative considered: a second script for 3D routes. Rejected because only two values differ between the two videos.

## Risks / Trade-offs

- [At pitch 45 the far part of the view shows the routes small, or the routes leave the screen] → Task 2.3 checks the opening view on macOS and an iPhone-sized window. If the routes don't fit, the opening center moves south within the Financial District. The spec states only that the camera is over the Financial District.
- [Width in meters is hard to judge on a pitched map, because the width on the screen changes with the distance from the camera] → The scenario "Width in meters" is checked at pitch 0.
- [At pitch 62 near the far limit of a wide window, the map shows its background above the horizon] → The opening view and the orbit are checked in a wide window and an iPhone-sized window in task 2.3. If the background is distracting, the orbit's zoom changes, and the spec with it.
- [The panel is taller with the slider and doesn't fit on a phone in landscape] → `DemoPanel` scrolls its children when they don't fit.
- [This change is archived before `raise-flutter-map-pitch-limit`, so that change's delta modifies a requirement that no longer exists] → Archive `raise-flutter-map-pitch-limit` first. Task 4.3 checks it.
