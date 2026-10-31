## Why

The demo has two showcases of downtown New York with overlapping content. "Polylines" draws routes in the map along the streets, but the map can't be tilted, so the 3D buildings hide little of the routes below them. "3D view" can be tilted, but its route is a `flutter_map` polyline whose points don't follow the streets. One tiltable showcase shows both features better than the two do separately.

## What Changes

- The "Polylines" showcase is renamed "3D routes". Its gallery sentence is "Tilt downtown New York to see routes drawn below its 3D buildings and labels, with pins that stand upright."
- The 3D routes screen opens at pitch 45. The `flutter_map` tilt gesture is enabled, and the panel has a slider that sets the pitch from 0 to the `flutter_map` pitch limit and shows the current pitch.
- The screen draws `flutter_map` pins that stand upright at the start and the end of each route.
- The screen has an orbit: a play/stop control turns the map a full turn every 30 seconds around downtown at pitch 62, and a touch on the map stops it.
- The recording mode and `tool/record_readme.sh` record either the flyover or the 3D routes orbit. The 3D routes video is 20 s, two thirds of a turn, with its own title card subtitle, and is written to `packages/demo/build/readme_3d_routes.mp4`.
- **BREAKING** (demo only): the "3D view" showcase and its screen are removed. The gallery lists Flyover, Inspect features and 3D routes.
- `packages/demo/README.md` describes 3D routes in one short sentence, in place of Polylines.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `demo-app`: the Gallery requirement lists Flyover, Inspect features and 3D routes. A new requirement "3D routes" replaces the requirement "Polylines": it keeps its routes, placement control, styles and legend, and adds the pitch, the tilt gesture, the slider, the pins and the orbit. The requirements "Recording mode" and "README recording" add the 3D routes showcase. The requirement "3D view" is removed.

## Impact

- `packages/demo/lib/main.dart`: the gallery's entries.
- `packages/demo/lib/src/polylines/`: the screen, its data and its tests move to `src/routes/` and `test/routes/`, and the screen gets the pitch and the pins.
- `packages/demo/lib/src/three_d/`: removed.
- `packages/demo/README.md`, `CONTRIBUTING.md`.
- `packages/demo/lib/src/flyover/recording.dart` moves to `lib/src/common/`; `packages/demo/tool/record_readme.sh`.
- The open change `raise-flutter-map-pitch-limit` modifies the 3D view requirement, so it needs to be archived before this change.
- The `flutter_mapigrade` library doesn't change.
