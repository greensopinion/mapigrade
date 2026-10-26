## Context

See proposal.md for motivation, and `specs/demo-app/spec.md` for the required behavior.

`FlyoverScreen` (`packages/demo/lib/src/flyover/flyover_screen.dart`) puts `MapigradeLayer` first among the `FlutterMap` children, with the stage layers and the rider among the layer's own `children`, and the attribution after it. MapLibre renders on its own thread, so the displayed map frame was rendered at a camera that trails the live `flutter_map` camera by about one frame, even with `LayerAlignment.prediction`. `MapTextureLayer` draws the layer's `children` in a viewport-sized `Stack` above the map texture, with a `MapCamera` that is the camera of the displayed frame, on macOS, iOS and, since 96a4ad7, Android. Widgets after the layer among the `FlutterMap` children get the live camera.

The flyover pitches the map to 50°, and the screen allows pitch up to `MapOptions.pitchLimit` (85°). The `flutter_map` fork draws `TileLayer` at any pitch and chooses tile zooms for the visible ground.

## Goals / Non-Goals

**Goals:**
- The two halves line up in every displayed frame, not only at rest.
- No change to the package: the demo uses only `MapigradeLayer`'s public API and `flutter_map`'s `TileLayer`.

**Non-Goals:**
- Equal frame rates for the two halves. The raster half is drawn by Flutter on the UI and raster threads, at the camera of the map frame, so it updates at the map's displayed frame rate.

## Decisions

### D195: Raster layer among the `MapigradeLayer` children

While the split view is on, the screen puts a `TileLayer`, clipped to the right half, first among the `MapigradeLayer` children, before the stage layers and the rider:

```
FlutterMap                               camera
 +-- MapigradeLayer                      live -> sets the map's camera
 |    texture: map frame N               C_N
 |    children:                          C_N
 |      [split] right-half clip
 |                 TileLayer (OSM)
 |      stage layers
 |      rider
 +-- [split] seam line and labels        screen
 +-- attribution                         screen
```

Every layer that draws ground positions in the split view uses camera C_N, so a road continues across the seam while the camera moves. The overlays come after the raster layer, so they are drawn above both halves.

Alternatives considered:
- A `TileLayer` after `MapigradeLayer` among the `FlutterMap` children. It is drawn at the live camera, so during a pan or the flyover the right half leads the left half by about one frame, and the halves visibly move apart at the seam.
- Two `FlutterMap` widgets side by side with one controller. Each has its own viewport, so the halves would have two centers and wouldn't form one map, and the left map would still need its own `MapigradeLayer`.

### D196: Clip at the viewport's horizontal center

The right-half clip is a `ClipRect` with a custom clipper that returns the rectangle from x = width / 2 to the right edge of its box, for the full height. The children's `Stack` has the viewport's size, so width / 2 is the viewport's center. The clip doesn't move with the camera: rotation and pitch change what each half shows, not where the seam is.

At a fractional device-pixel position the clip edge can blend with the map texture across one device pixel. The seam line (D197) covers that pixel.

### D197: Seam line and labels as screen UI among the `FlutterMap` children

While the split view is on, a widget after `MapigradeLayer` and before the attribution among the `FlutterMap` children draws the seam: a 1-logical-pixel line centered on x = width / 2 over the full height, and two labels next to the line near the bottom. The `FlutterMap` children's `Stack` has the same size as the layer's children's `Stack`, so the line and the clip share one x position. The widget draws in screen coordinates, so the line and the labels don't move with the camera, and it is wrapped in `IgnorePointer`, so a gesture that starts on it reaches the map.

```
+-----------------------+----------------------+
| +-panel--------+      |                      |
| |              |      |                      |
| +--------------+      |                      |
|                       |                      |
|      chosen style     |    OSM raster        |
|                       |                      |
|          [Mapigrade] | [Raster (OSM)]   (i) |
+-----------------------+----------------------+
```

The panel sits at the top left and is up to 300 logical pixels wide, which covers most of the left half on a phone in portrait, so the labels go at the bottom. They sit inside the bottom safe-area inset and above the height of the attribution button in the bottom-right corner, so on a narrow screen the right label doesn't overlap the button. The labels use the panel's surface color at the panel's opacity, so they read on both the light and the dark parts of the map.

Alternative considered: labels at the top of each half. The panel covers the left one on phones.

### D198: Raster tile source

The `TileLayer` uses `https://tile.openstreetmap.org/{z}/{x}/{y}.png` with `userAgentPackageName: 'com.greensopinion.mapigrade_demo'`, the Android application ID, and `maxNativeZoom: 19`, the highest zoom the server provides. The screen builds the `TileLayer` only while the split view is on, so with the split view off no tile is requested; turning it off disposes the layer and its tile cache. The screen's existing OpenStreetMap attribution covers the tiles.

Alternatives considered (in exploration): CARTO raster basemaps, close to Positron but with usage limits and a CARTO attribution; a MapTiler raster of a matching style, which needs an API key. No keyless vector style reproduces OSM Carto, so the left half can't match the raster cartography either.

## Risks / Trade-offs

- [The flyover requests many tiles from a server with a usage policy against heavy use] → The split view is off by default, and the recording mode never turns it on. The user agent identifies the demo.
- [Raster tiles that are still loading leave gaps in the right half during the flyover, where the map texture shows through] → Accepted: the gaps show how raster tiles load, which is part of the comparison.
- [Above the horizon at high pitch the tile layer draws nothing] → The map texture under the right half then shows the style's sky, which continues the left half's sky. Task 2.3 verifies it at pitch 85.
- [The metrics show only the map's frame rate and render time; MapLibre still renders the whole viewport, and the raster half adds UI-thread work] → Accepted: the map metrics stay comparable with the split view off. The Flutter UI frame rate in the metrics shows the added cost.
