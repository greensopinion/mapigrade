# mapigrade_demo

An app for trying `flutter_mapigrade` on your own devices. It shows a MapLibre map as the base layer of a `FlutterMap`, with overlays above it, frame rates, and a flyover over three stages of the Tour de France Femmes avec Zwift 2026. It runs on Android, iOS and macOS, and uses only the public library `package:flutter_mapigrade/flutter_mapigrade.dart`, so its code shows what an application can use.

The demo isn't published, and there are no built apps to download: build it from source.

## What it shows

- The map with the `flutter_map` gestures: drag to pan, pinch or scroll to zoom, and rotate with two fingers (on macOS, with the trackpad, or with Ctrl and drag).
- A choice of four styles that need no API key: OpenFreeMap Liberty (at launch), Bright and Positron, and the MapLibre demo tiles. A style change keeps the camera, the overlays and the metrics.
- The map's center (latitude and longitude) and zoom, updated as the camera moves.
- Frame rates, updated once per second: the map frames displayed and rendered per second, the map's average render time per rendered frame, and the Flutter UI frames per second. The map values come from `LayerMetrics`. At rest the map renders no frames, so its rates are 0 and the render time is shown as "–". The UI rate lags the others by about 2 s, because Flutter reports frame timings in batches.
- Stages 9, 7 and 4, in that order: a magenta route, a green start pin with a bubble (race, stage, start and finish, distance, type, winner), and a red finish pin. Stage 9 starts and finishes in Nice, so one pin, half green and half red, marks both. The pins and bubbles stay upright when the map rotates. The "Stage overlays" switch hides and shows them.
- A flyover (the play button). For each stage it holds at the start, then follows the route at zoom 16 like a drone ahead of a rider: a yellow rider marker moves along the route, and the map turns so that the rider's direction of travel points up. At the finish it turns back to north up, then zooms out and flies to the next stage. It ends at the finish of stage 4 in Dijon, after about 5 min 45 s. The camera depends only on the time since the start and the window size, so two runs in the same window show the same view at the same time.
- "Warm-up pass before the flyover" plays the flyover once to load tiles, then starts again from stage 9, for a recording without tiles loading. The panel states "Warming up" during the first pass.
- A touch, click, scroll or key press on the map, or the stop button, stops the flyover and leaves the camera where it is.

The routes are approximate, and the demo says so. The attribution button at the bottom right of the map lists the style's sources and OpenStreetMap.

## Run it

The demo needs the MapLibre Native FFI built for your platform, as the other apps of the repository do. The prerequisites and pinned versions are in [CONTRIBUTING.md](../../CONTRIBUTING.md).

```sh
# At the repository root: build the FFI (all presets, or only the ones you
# need, for example macos-arm64-metal or android-arm64-egl)
scripts/build_maplibre_ffi.sh
flutter pub get

cd packages/demo
flutter run -d macos
flutter run -d <simulator id>            # iOS simulator (Apple silicon only)
flutter run -d <emulator id>             # Android emulator (arm64 only)
flutter run --release -d <device id>     # a device; `flutter devices` lists the ids
```

Frame rates are only meaningful in a release or profile build on a device. On a device without an arm64 ABI the demo states that the map isn't supported.

The styles and tiles come from OpenFreeMap and demotiles.maplibre.org, so the demo needs a network connection.

## Stage data

`assets/tdff_2026.geojson` holds one `LineString` feature per stage, with the stage's facts as properties. Open it in a GeoJSON viewer, such as [geojson.io](https://geojson.io), to check the routes.

The facts (date, start, finish, distance, type, winner and team) come from the official stage pages of the race on letourfemmes.fr:

- Stage 9, Nice – Nice: <https://www.letourfemmes.fr/en/stage-9>
- Stage 7, La Voulte-sur-Rhône – Mont Ventoux: <https://www.letourfemmes.fr/en/stage-7>
- Stage 4, Gevrey-Chambertin – Dijon: <https://www.letourfemmes.fr/en/stage-4>

Where sources disagree, the demo uses the figure from those pages; for example, other tables give stage 7 as 144 km instead of 146.8 km.

The routes are computed, not the official tracks. We chose waypoints from the official stage maps and stored them in `tool/waypoints.json`; a router on OpenStreetMap data connects them. The router's bicycle profile can avoid roads that the race uses, so a route can leave the race route where we have too few waypoints. For stage 9 the route traces the Col d'Èze circuit once, not three times.

The routes are derived from OpenStreetMap data, © OpenStreetMap contributors, available under the [Open Database License](https://www.openstreetmap.org/copyright).

## Regenerate the routes

After a change to `tool/waypoints.json`, run the script from this directory:

```sh
dart run tool/route_stages.dart
```

It requests one route per stage from the FOSSGIS routing service, removes the out-and-back spurs that the router adds to waypoints off the race route, simplifies each line to a tolerance of 10 m, rounds the coordinates to 5 decimals, and writes `assets/tdff_2026.geojson`. A second run with the same waypoints writes the same file, unless the service's OpenStreetMap data has changed. Commit the waypoints and the asset together. The script isn't part of a build; the app doesn't call the routing service.

### Usage policy of the routing service

The script uses the bicycle profile of [routing.openstreetmap.de](https://routing.openstreetmap.de), which FOSSGIS runs with OSRM. Its [usage policy](https://routing.openstreetmap.de/about.html) allows at most one request per second, requires a user agent that identifies the application, and forbids scraping and heavy use. The script sends a user agent that names this repository, waits 1 s between requests, and makes three requests per run. Run it when the waypoints change, not in a loop or in CI.
