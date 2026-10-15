## Context

See proposal.md for motivation and scope, and specs/demo-app/spec.md for the behavior. The in-flight change `layer-metrics` adds `LayerMetrics`, `LayerMetricsSnapshot` and the `metrics` parameter of `MapigradeLayer`, and uses decisions up to D113; decisions here are numbered from D114. That change is archived before this one.

Current state, as checked on 2026-10-14:

- The example (`packages/flutter_mapigrade/example/`) sets the platform values that the package supports: Android `minSdk = 29` and `abiFilters += "arm64-v8a"`, iOS 15.5, macOS 14.3, and the macOS entitlement `com.apple.security.network.client`. The plugin's own Android manifest declares `INTERNET`, so release builds have it.
- `flutter_map` 8.3.2 provides `MapController.moveAndRotate`, `CameraFit.bounds(...).fit(camera)`, which computes a camera without moving the map, `MapOptions.onPointerDown`, `MapOptions.onMapEvent` with `MapEventSource`, `Marker(rotate: true)`, `PolylineLayer` and `RichAttributionWidget`.
- `LayerMetricsSnapshot` has a private constructor (D110), so the demo's tests can't create snapshots.
- The official stage pages on letourfemmes.fr (read on 2026-10-14) give the facts in the spec's table. Stage 9 is a circuit from Place Masséna in Nice that climbs the Col d'Èze three times, then a final climb by the Chemin des Vinaigriers, and finishes on the Promenade des Anglais. Stage 7 crosses the Col de la Grande Limite, the Col du Colombier and the Col de Suzette and has an intermediate sprint at Beaumes-de-Venise, before it climbs Mont Ventoux from Bédoin. Stage 4 climbs the Lacets de Marsannay.
- The FOSSGIS routing service (`routing.openstreetmap.de`) runs OSRM with a bicycle profile on OpenStreetMap data. Its policy allows at most one request per second, requires a valid user agent, and forbids scraping and heavy use. We found no published policy for the public BRouter server.

## Goals / Non-Goals

**Goals:**
- Keep the flyover's camera computation free of widgets and timers, so that unit tests check it.
- Keep the demo's code readable as an example of the public API: each file does one thing, and the map screen reads like an application's map screen.

**Non-Goals:**
- Tests that drive the native map from the demo; the package's integration tests cover the layer.
- A fallback `TileLayer` where the native library is missing.

## Decisions

### D114. Layout of the package

```
packages/demo/
  lib/main.dart                 app, MaterialApp, unsupported-device screen
  lib/src/map_screen.dart       FlutterMap, layers, controls, state of the settings
  lib/src/styles.dart           the four styles and their attributions
  lib/src/metrics_panel.dart    the once-per-second metrics display
  lib/src/rates.dart            rates from two sets of counts (pure)
  lib/src/stages.dart           stage data model and asset parsing
  lib/src/stage_layers.dart     polylines, pins and bubbles
  lib/src/flyover.dart          keyframes and camera(t) (pure)
  lib/src/flyover_player.dart   Ticker that applies camera(t) to the MapController
  assets/tdff_2026.geojson      stage data (the script's output)
  tool/waypoints.json           waypoints per stage (input of the script)
  tool/route_stages.dart        the routing script
  test/                         unit tests of rates, stages, flyover
```

The app is created with `flutter create --platforms=android,ios,macos --org com.greensopinion --project-name mapigrade_demo`, and its platform values are set to the example's. Bundle identifiers: `com.greensopinion.mapigradeDemo` (iOS, macOS) and `com.greensopinion.mapigrade_demo` (Android). Dependencies: `flutter_mapigrade` (path), `flutter_map` 8.3.2 and `latlong2` as in the example, and `url_launcher` for the attribution links.

### D115. One `LayerMetrics` for the life of the map screen

The map screen creates one `LayerMetrics` in `initState` and gives it to the layer. The demo never changes the layer's key: a style change and an alignment change keep the map (map-layer, requirement "Metrics"). A `Timer.periodic` of 1 s takes a snapshot and computes the rates from the previous one.

`rates.dart` computes from plain values (`int` counts and `Duration`s), not from `LayerMetricsSnapshot`, so that tests can call it. The panel passes the snapshot's fields. The UI rate counts the `FrameTiming`s that `SchedulerBinding.addTimingsCallback` reports in the interval. Flutter delivers timings in batches, so the count is taken per one-second interval of the timing's `rasterFinish` time, not per callback.

*Alternatives:* an interval shorter than 1 s makes the displayed rates vary by a frame or two between updates. A snapshot per Flutter frame is possible (D109's lock covers only a copy) but the display can't be read that fast.

### D116. Stage data as GeoJSON, routes from OSRM

`assets/tdff_2026.geojson` is a FeatureCollection with one `LineString` feature per stage, in the spec's order. The properties hold the facts: `stage`, `date`, `start`, `finish`, `distanceKm`, `type`, `winner`, `team`, `source` (the URL of the official stage page). GeoJSON lets anyone check the routes in a GeoJSON viewer.

`tool/route_stages.dart` is a Dart script that uses only `dart:io` and `dart:convert`. For each stage of `tool/waypoints.json` it calls

```
https://routing.openstreetmap.de/routed-bike/route/v1/driving/<lon,lat;...>?overview=full&geometries=geojson
```

with a user agent that names the repository, waits 1 s between requests, simplifies the line (Douglas–Peucker, tolerance 10 m) and rounds coordinates to 5 decimals (about 1 m), so that the asset stays small and the output is stable. It writes the facts from `waypoints.json` and the routes to the asset. We run it by hand; it is not part of a build. The waypoints are chosen from the official stage maps; each stage has enough of them that the router follows the race route through the named climbs. For stage 9 they trace the Col d'Èze circuit once and then the final climb by the Chemin des Vinaigriers, so the line doesn't repeat the circuit.

*Alternatives:*
- BRouter: its bicycle profiles are closer to how races are routed, but we found no usage policy for its public server, and its HTTP interface is limited to about 50 km per request.
- Hand-drawn lines: no licensing question, but the routes would be visibly off roads at street-level zoom.

### D117. Pins and bubbles are markers with upright rotation

Each pin is a `Marker` with `rotate: true`, whose `alignment` puts the pin's tip on the coordinate. The start pin's bubble is part of the same marker's child, above the pin, so that the two always move together. The marker has a fixed size (the bubble's size plus the pin's), because `Marker` needs `width` and `height`. A start and finish less than 500 m apart are drawn as one pin, half green and half red, with a bubble that says "Start and finish". The routes use one `PolylineLayer` below the `MarkerLayer`, in a colour that contrasts with all four styles.

### D118. The flyover is a list of segments, and camera(t) is a pure function

`flyover.dart` builds the sequence once, when playback starts, from the stages and the `MapCamera` of that moment (for the viewport size). Each segment has a duration and a start and end camera (center, zoom, rotation):

| Segment | Duration | Camera |
|---|---|---|
| hold at start | 3 s | start, zoom 14 |
| start → route | 3 s | to `CameraFit.bounds(route, padding).fit(camera)` |
| route, rotating | 4 s | rotation 0 → 20° → 0 |
| route → finish | 3 s | finish, zoom 14 (skipped for a loop) |
| hold at finish | 2 s | (skipped for a loop) |
| to next start | 6 s | zoom out, pan, zoom in |

That is 21 s per stage and 57 s for the three, without the last transition. `camera(t)` finds the segment of `t` and interpolates with an ease-in-out curve: the center in Web Mercator coordinates, the zoom linearly, the rotation by the shorter angle. A transition between stages adds a dip to the zoom, `z(s) = lerp(z0, z1, s) − d · sin(π s)`, where `d` lowers the zoom at mid-way to the zoom at which both points fit in the viewport. The camera therefore moves at low zoom over most of the distance and doesn't load street-level tiles along the way.

`flyover_player.dart` runs a `Ticker`. On each tick it computes `camera(elapsed)` and calls `MapController.moveAndRotate`. With a warm-up pass it plays the sequence once, then sets `elapsed` back to 0. Because `camera(t)` depends only on `t` and the starting viewport, a dropped frame doesn't change the route.

*Alternatives:* MapLibre's `flyTo` curve (van Wijk and Nuij) looks smoother over long distances, but it adds a parameterised curve for a sequence that has two long transitions.

### D119. What stops the flyover

`MapOptions.onPointerDown` stops it for a touch or click. `MapOptions.onMapEvent` stops it for any event whose `source` isn't `MapEventSource.mapController`, which covers scroll-wheel and trackpad zoom on macOS, keyboard input and gestures that don't start with a pointer down. The player's own moves have that source and don't stop it. A resize during playback doesn't rebuild the sequence; the next playback uses the new size.

### D120. Attribution

`RichAttributionWidget` shows the entries of the chosen style from `styles.dart`, followed by the OpenStreetMap entry for the routes, which opens `https://www.openstreetmap.org/copyright` with `url_launcher`. OpenFreeMap styles have the entries OpenFreeMap, © OpenMapTiles and © OpenStreetMap contributors (the attribution that openfreemap.org states). The MapLibre demo tiles have the entry MapLibre. A note under the panel states that the routes are approximate.

## Risks / Trade-offs

- [The FOSSGIS bicycle profile avoids roads that the race uses, such as main roads closed for the race, so a route leaves the race route.] → More waypoints on the official route for that section; the routes are labelled approximate.
- [The routing service changes or goes away.] → The asset is committed, so the demo doesn't depend on the service; only regenerating does.
- [The OpenFreeMap or demo tile servers are down or slow.] → The demo reports load failures through `onError`; recordings need a warm-up pass.
- [At zoom 14, the flyover loads many tiles at each start and finish on a slow network, and the first run shows tiles loading.] → The warm-up pass.
- [Rotating the map during the route segment shows corners that MapLibre hasn't rendered yet.] → The layer fills the viewport when rotated (map-layer, "Rotated map"); the 20° maximum keeps the change between frames small.
- [The `publish-readiness` change changes the example's Android settings (local FFI property, ABIs).] → The demo's Android settings follow the example's; whichever change is archived second updates the demo too.
