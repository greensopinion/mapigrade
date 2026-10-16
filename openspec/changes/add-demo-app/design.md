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
  lib/src/map_screen.dart       FlutterMap, layers, controls, camera readout, settings
  lib/src/styles.dart           the four styles and their attributions
  lib/src/metrics_panel.dart    the once-per-second metrics display
  lib/src/rates.dart            rates from two sets of counts (pure)
  lib/src/stages.dart           stage data model and asset parsing
  lib/src/stage_layers.dart     polylines, pins, bubbles and the rider marker
  lib/src/flyover.dart          segments, camera(t) and rider(t) (pure)
  lib/src/flyover_player.dart   Ticker that applies camera(t) to the MapController
  assets/tdff_2026.geojson      stage data (the script's output)
  tool/waypoints.json           waypoints per stage (input of the script)
  tool/route_stages.dart        the routing script
  test/                         unit tests of rates, stages, flyover
```

The app is created with `flutter create --platforms=android,ios,macos --org com.greensopinion --project-name mapigrade_demo`, and its platform values are set to the example's. Bundle identifiers: `com.greensopinion.mapigradeDemo` (iOS, macOS) and `com.greensopinion.mapigrade_demo` (Android). Dependencies: `flutter_mapigrade` (path), `flutter_map` 8.3.2 and `latlong2` as in the example, and `url_launcher` for the attribution links.

### D115. One `LayerMetrics` for the life of the map screen

The map screen creates one `LayerMetrics` in `initState` and gives it to the layer. The demo never changes the layer's key, and uses the layer's default alignment: a style change keeps the map (map-layer, requirement "Metrics"). A `Timer.periodic` of 1 s takes a snapshot and computes the rates from the previous one.

`rates.dart` computes from plain values (`int` counts and `Duration`s), not from `LayerMetricsSnapshot`, so that tests can call it. The panel passes the snapshot's fields. The UI rate counts the `FrameTiming`s that `SchedulerBinding.addTimingsCallback` reports in the interval. Flutter delivers timings in batches, so the count is taken per one-second interval of the timing's `rasterFinish` time, not per callback. The panel doesn't assume that the timings' clock is its own: it maps its `Stopwatch` to the timings' clock by the smallest difference it has seen between a batch's arrival and a timing's `rasterFinish`. Because a batch can arrive up to a second after its frames, the panel shows the count of the second that ended 2 s before the update, which is complete. The UI rate therefore lags the map rates by about 2 s, and is 0 at rest, when Flutter draws no frames.

*Alternatives:* an interval shorter than 1 s makes the displayed rates vary by a frame or two between updates. A snapshot per Flutter frame is possible (D109's lock covers only a copy) but the display can't be read that fast.

### D116. Stage data as GeoJSON, routes from OSRM

`assets/tdff_2026.geojson` is a FeatureCollection with one `LineString` feature per stage, in the spec's order. The properties hold the facts: `stage`, `date`, `start`, `finish`, `distanceKm`, `type`, `winner`, `team`, `source` (the URL of the official stage page), and `startPoint` and `finishPoint` (the first and last waypoints, as `[lon, lat]`), so that a test can check the route's ends against them. GeoJSON lets anyone check the routes in a GeoJSON viewer.

`tool/route_stages.dart` is a Dart script that uses only `dart:io` and `dart:convert`. For each stage of `tool/waypoints.json` it calls

```
https://routing.openstreetmap.de/routed-bike/route/v1/driving/<lon,lat;...>?overview=full&geometries=geojson
```

with a user agent that names the repository, and waits 1 s between requests. Where a waypoint lies off the race route, for example on a side road at a col, the router goes to it and back along the same road; the script removes such spurs, by dropping each point whose next point returns to the point before it. Without this the line has 180° turns that the race doesn't ride, and the flyover's camera, which turns with the route (D118), would spin on them. The script then simplifies the line (Douglas–Peucker, tolerance 10 m) and rounds coordinates to 5 decimals (about 1 m), so that the asset stays small and the output is stable. It writes the facts from `waypoints.json` and the routes to the asset. We run it by hand; it is not part of a build. The waypoints are chosen from the official stage maps; each stage has enough of them that the router follows the race route through the named climbs. For stage 9 they trace the Col d'Èze circuit once and then the final climb by the Chemin des Vinaigriers, so the line doesn't repeat the circuit.

*Alternatives:*
- BRouter: its bicycle profiles are closer to how races are routed, but we found no usage policy for its public server, and its HTTP interface is limited to about 50 km per request.
- Hand-drawn lines: no licensing question, but the routes would be visibly off roads at street-level zoom.

### D117. Pins and bubbles are markers with upright rotation

Each pin is a `Marker` with `rotate: true`, whose `alignment` puts the pin's tip on the coordinate. The start pin's bubble is part of the same marker's child, above the pin, so that the two always move together. The marker has a fixed size, because `Marker` needs `width` and `height`: 260 px wide and 150 px of room above the pin. The bubble sizes to its text within that room, and the pin sits at the bottom of the marker, so the pin's tip stays on the coordinate whatever the font. The bubble names the race, "Tour de France Femmes avec Zwift 2026" as the official site writes it, above "Stage n", so that the stage number means something on its own; then the start and finish, the distance and type, and the winner. A start and finish less than 500 m apart are drawn as one pin, half green and half red, with a bubble that says "Starts and finishes in Nice". The routes use one `PolylineLayer` below the `MarkerLayer`, in a colour that contrasts with all four styles.

During the flyover's follow (D118), a rider marker sits on the route: a yellow disc with a black border and a bicycle icon, the leader's colour, which stands out on the magenta route and on all four styles. It is a `Marker` with `rotate: true` in its own `MarkerLayer` above the stage markers. The flyover turns the map so that the rider's direction points up, so an upright marker always faces the direction of travel. The player publishes the rider's position in a `ValueNotifier` that only this layer listens to, so the rider moving on each frame rebuilds only that layer.

### D118. The flyover is a list of segments, and camera(t) is a pure function

`flyover.dart` builds the sequence once, when playback starts, from the stages and the `MapCamera` of that moment (for the viewport size). Each segment has a duration and a start and end camera (center, zoom, rotation):

| Segment | Duration | Camera |
|---|---|---|
| hold at start | 3 s | start, zoom 14, north up |
| turn to the route | 3 s | to the follow's first camera: zoom 16, turned to the direction of travel |
| follow the route | from the route's length and bends (below) | like a drone ahead of the rider, zoom 16 |
| turn to north | 3 s | finish (for a loop, the route's last point), zoom 14, north up |
| hold at finish | 2 s | (skipped for a loop) |
| to next start | 6 s | zoom out, pan, zoom in |

The follow is a chase camera. A rider moves along the route, keeping strictly to it. The camera is a drone that flies a smoothed version of the rider's track: it turns the map so that its course points up, and puts its center ahead of the rider by 20% of the viewport height, so that the rider is in the lower part of the screen and the view shows the road ahead. On tight bends the drone cuts the corner and turns gradually instead of turning with the road, so the rider drifts a little around its place below the center, by at most 20% of the viewport's shorter side. Zoom 16 (about 1.7 m per logical pixel at the latitude of the stages) shows the road and the buildings beside it.

The follow is precomputed when the flyover is built:

- Course: at samples 16 px apart at zoom 16 (about 28 m), the direction from 80 px behind the sample to 320 px ahead of it, unwrapped so that it doesn't jump at ±180°, then smoothed with a Gaussian of 480 px. A raw road direction would flip by 180° on every hairpin.
- Rider's speed: 500 px/s at zoom 16 (about 0.86 km/s on the ground), lower where the course turns faster than 25° per second at that speed, 15% of it at both ends, and changing by no more than 100 px/s², so that the rider speeds up and slows down gradually rather than stepping between speeds.
- Drone: the rider's position and course at 60 frames per second of follow time, each smoothed over time with a Gaussian (1.2 s for the position, 1.5 s for the heading). A symmetric smoothing of a straight track at a steady speed is the track itself, so the drone doesn't lag the rider; it only rounds corners, and its turn rate changes gradually. Where the drone would drift further than the limit from the rider, the rider slows down on that bend and the flight is planned again (at most 8 times); a final clamp keeps the rider on screen.
- `camera(t)` during the follow interpolates between the two drone frames around `t`. `rider(t)` finds the rider's sample by time and interpolates its position, and returns null outside a follow, so that the marker is shown only then (D117).

With the committed routes the follows take 72.5 s (stage 9, which traces the circuit once), 251.0 s (stage 7) and 37.5 s (stage 4), and the flyover 404.0 s. The speed is a constant in `flyover.dart`, `followSpeed`, and sets most of that length; the parts where the turn rate or the drift limits the speed don't change with it. In the unit test the drone's turn rate changes by under 15°/s² and its speed on screen by under 200 px/s²; a camera locked to the smoothed road heading, as first built, reached 6,000–9,000 px/s² on tight bends, which showed as jerks.

Other segments interpolate with an ease-in-out curve: the center in Web Mercator coordinates, the zoom linearly, the rotation by the shorter angle. A transition between stages adds a dip to the zoom, `z(s) = lerp(z0, z1, s) − d · sin(π s)`, where `d` lowers the zoom at mid-way to the zoom at which both points fit in the viewport. The camera therefore moves at low zoom over most of the distance and doesn't load street-level tiles along the way.

`flyover_player.dart` runs a `Ticker`. On each tick it computes `camera(elapsed)` and calls `MapController.moveAndRotate`, and sets its rider notifier to `rider(elapsed)`. With a warm-up pass it plays the sequence once, then sets `elapsed` back to 0. Because `camera(t)` depends only on `t` and the starting viewport, a dropped frame doesn't change the route.

*Alternatives:*
- MapLibre's `flyTo` curve (van Wijk and Nuij) looks smoother over long distances, but it adds a parameterised curve for a sequence that has two long transitions.
- Showing each whole route north up, with a fixed 20° rotation and back, or following it north up at zoom 12: both were tried, and neither looks like a flight along the course.
- Locking the camera to the rider with a heading smoothed along the route, and a 45° per second limit: it jerked on tight bends, where the heading's turn rate and the camera's speed changed abruptly, and the map turned too quickly.
- Aiming the camera at a point 400 px further along the route instead of using a smoothed heading: it turns earlier into bends, but it missed the direction of travel more often on the circuit of stage 9 in the unit test that checks that the rider moves up the screen.
- Pitch, which a drone view would also have: the package supports center, zoom and bearing only (proposal, non-goals).

### D119. What stops the flyover

`MapOptions.onPointerDown` stops it for a touch or click. `MapOptions.onMapEvent` stops it for any event whose `source` isn't `MapEventSource.mapController`, which covers scroll-wheel and trackpad zoom on macOS, keyboard input and gestures that don't start with a pointer down. The player's own moves have that source and don't stop it. A resize (`MapEventSource.nonRotatedSizeChange`) doesn't stop it either, and doesn't rebuild the sequence; the next playback uses the new size.

### D121. Camera readout

The panel shows the center to 5 decimals (about 1 m) and the zoom to 2 decimals. `MapOptions.onPositionChanged`, which `flutter_map` calls on every camera change from gestures and from the controller, sets a `ValueNotifier`; a `ValueListenableBuilder` in the panel rebuilds only the readout, so that the map screen doesn't rebuild on every frame of a gesture or of the flyover.

The map screen builds its `MapOptions` in `build` with method tear-offs as callbacks. Tear-offs of the same method on the same object are equal, so the options are equal from one build to the next and `FlutterMap` keeps them. Options kept in a field from `initState` would keep the callbacks of the first build after a hot reload, which doesn't run `initState` again.

### D120. Attribution

`RichAttributionWidget` shows the entries of the chosen style from `styles.dart`, followed by the OpenStreetMap entry for the routes, which opens `https://www.openstreetmap.org/copyright` with `url_launcher`. OpenFreeMap styles have the entries OpenFreeMap, © OpenMapTiles and © OpenStreetMap contributors (the attribution that openfreemap.org states). The MapLibre demo tiles have the entry MapLibre. A note under the panel states that the routes are approximate.

## Risks / Trade-offs

- [The FOSSGIS bicycle profile avoids roads that the race uses, such as main roads closed for the race, so a route leaves the race route.] → More waypoints on the official route for that section; the routes are labelled approximate.
- [The routing service changes or goes away.] → The asset is committed, so the demo doesn't depend on the service; only regenerating does.
- [The OpenFreeMap or demo tile servers are down or slow.] → The demo reports load failures through `onError`; recordings need a warm-up pass.
- [At zoom 16 the follow crosses new tiles all the time, about 0.86 km/s on the ground, and on a slow network the first run shows tiles loading.] → The warm-up pass. The warm-up doubles the playback to about 13 min 28 s.
- [Turning the map during the follow shows corners that MapLibre hasn't rendered yet.] → The layer fills the viewport when rotated (map-layer, "Rotated map"); the 25° per second limit keeps the change between frames under 0.25° at 120 Hz.
- [The flyover, at about 6 min 44 s, is long for a recording.] → `followSpeed` sets most of the length; a later change can make it a setting.
- [The drone rounds tight bends, so the rider briefly moves diagonally on screen and drifts from its place below the center.] → The drift is limited by slowing the rider; the unit test requires that the rider moves within 60° of straight up in more than 90% of the follow's samples on each stage, and stays within the drift limit.
- [The `publish-readiness` change changes the example's Android settings (local FFI property, ABIs).] → The demo's Android settings follow the example's; whichever change is archived second updates the demo too.
