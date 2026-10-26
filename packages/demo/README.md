# mapigrade_demo

An app for trying `flutter_mapigrade` on your devices. It opens at a gallery of showcases, each a screen with its own map. It runs on Android, iOS and macOS, and uses only the public library `package:flutter_mapigrade/flutter_mapigrade.dart`, so its code shows what an application can use.

The demo isn't published, and there are no built apps to download: build it from source.

## What it shows

- **Flyover**: a drone's-eye flight along three stages of the Tour de France Femmes avec Zwift 2026, with route and pin overlays that stay on the map while it moves, and the map's and Flutter's frame rates. The video in the repository's README is a recording of it. A split view compares the map with OpenStreetMap raster tiles.
- **Inspect features**: tap the map to highlight the feature on top with feature state, and see its style layer, source, ID and properties, and the other features at the tap.

Each screen offers four styles that need no API key: OpenFreeMap Liberty, Bright and Positron, and the MapLibre demo tiles. The routes are approximate.

Some of what the inspect screen shows comes from the data, not from the demo: OpenFreeMap's tiles merge buildings of the same height into one feature, so one tap can highlight many buildings. The screen also works around three MapLibre Native defects, described in [docs/upstream-fixes/maplibre-query-result-order.md](../../docs/upstream-fixes/maplibre-query-result-order.md), [docs/upstream-fixes/maplibre-feature-state-coalescing.md](../../docs/upstream-fixes/maplibre-feature-state-coalescing.md) and [docs/upstream-fixes/maplibre-symbol-query-feature-state.md](../../docs/upstream-fixes/maplibre-symbol-query-feature-state.md).

## Run it

The first build downloads the pinned MapLibre Native FFI release, as for the other apps of the repository. The prerequisites and pinned versions are in [CONTRIBUTING.md](../../CONTRIBUTING.md).

```sh
# At the repository root
flutter pub get

cd packages/demo
flutter run -d macos
flutter run -d <simulator id>            # iOS simulator (Apple silicon Macs only)
flutter run -d <emulator id>             # Android emulator
flutter run --release -d <device id>     # a device; `flutter devices` lists the ids
```

Frame rates are only meaningful in a release or profile build on a device. On a device with none of the ABIs `arm64-v8a`, `armeabi-v7a` and `x86_64` the demo states that the map isn't supported.

The styles and tiles come from OpenFreeMap and demotiles.maplibre.org, so the demo needs a network connection.

## Recording mode

On macOS, the environment variable `MAPIGRADE_DEMO_RECORDING_SECONDS=<L>` starts the demo in the recording mode that `tool/record_readme.sh` uses for the video in the repository's README. In this mode the demo opens the flyover without the gallery, the window has no title bar and a content area of 1280 × 720 points, the settings are collapsed, and when the style and the stages have loaded, the demo plays the first L + 1 s of the flyover as a warm-up pass and moves the camera back to the start. When the map is at rest there, the demo writes `ready` to standard output, and it starts the flyover when it reads `go` on standard input. It exits with an error when the map isn't at rest within 30 s, when `go` doesn't arrive within 30 s, or when the map reports a failure.

To try it, start the binary in the app bundle from a shell, and type `go` after `ready`:

```sh
flutter build macos --release
MAPIGRADE_DEMO_RECORDING_SECONDS=20 build/macos/Build/Products/Release/mapigrade_demo.app/Contents/MacOS/mapigrade_demo
```

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
