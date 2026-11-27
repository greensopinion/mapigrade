## Purpose

Defines `MapigradeMap`, a widget that displays a MapLibre map without `flutter_map`, whose camera MapLibre owns: the widget, its camera controller, the camera model and limits, camera commands and the camera streams.

## ADDED Requirements

### Requirement: Map widget
`mapigrade` SHALL provide `MapigradeMap`, a widget that displays a map style in its full size through a Flutter `Texture`, as the `map-texture` capability describes. It SHALL take exactly one of a style URL and a style JSON string, an initial camera, camera limits, gesture options, an optional `MapigradeController`, an optional `MapigradeCameraController`, header rules, an optional `MapigradeMetrics`, callbacks for a loaded style and for failures, the tap callbacks of the `map-gestures` capability, and children drawn above the map. It SHALL NOT depend on `flutter_map`. Header rules, `asset://` URLs and the Android network security configuration SHALL behave as the `map-layer` requirements "HTTP headers", "Flutter assets" and "Android network security configuration" describe for `MapigradeLayer`. Failures SHALL be reported as the `map-layer` requirement "Failure reporting" describes, with the types `MapigradeLoadException`, `MapigradeRenderException` and `MapigradeCreateException`. The metrics object SHALL behave as the `map-layer` requirement "Metrics" describes for the layer.

#### Scenario: Map displayed
- **WHEN** an application places a `MapigradeMap` with a style URL and an initial camera
- **THEN** the widget shows the style at that camera once the style has loaded, and `onStyleLoaded` is called once

#### Scenario: Style changed
- **WHEN** the application rebuilds the widget with a different style URL
- **THEN** the map keeps its camera and shows the new style, and `onStyleLoaded` is called again

#### Scenario: Style fails to load
- **WHEN** the style URL can't be loaded
- **THEN** the failure callback receives one `MapigradeLoadException`, and the application keeps running

#### Scenario: No flutter_map
- **WHEN** an application that depends only on `mapigrade` places a `MapigradeMap`
- **THEN** `flutter_map` isn't in the application's dependency graph

### Requirement: Process-wide settings
`mapigrade` SHALL provide `Mapigrade`, a class with only static members: `isSupported`, which states whether a map can be created in this process, and `maximumCacheSizeBytes`, the maximum size of the tile cache as the `map-texture` requirement "Maximum tile cache size" describes. `MapigradeLayer.isSupported` and `MapigradeLayer.maximumCacheSizeBytes` SHALL read and write the same values. Where `Mapigrade.isSupported` is false, a `MapigradeMap` SHALL report one `MapigradeCreateException`, draw nothing, and still build its children.

#### Scenario: Unsupported platform
- **WHEN** an application runs on web and places a `MapigradeMap`
- **THEN** `Mapigrade.isSupported` is false, the failure callback receives one `MapigradeCreateException`, and the children are built

#### Scenario: Shared cache setting
- **WHEN** an application sets `Mapigrade.maximumCacheSizeBytes` to 10 MiB
- **THEN** `MapigradeLayer.maximumCacheSizeBytes` is 10 MiB

### Requirement: Camera model
A camera SHALL be a `MapigradeCamera` value with every field of MapLibre's camera, in MapLibre's conventions: a center as a `LatLng`, the center's altitude in meters above sea level, the zoom of 512-pixel tiles, the bearing in degrees clockwise from north, the pitch in degrees from looking straight down, the roll in degrees, the vertical field of view in degrees, and the padding as `EdgeInsets` in logical pixels, which insets the area that the camera centers in from the widget's edges. An initial camera that omits the altitude, roll, field of view or padding SHALL get MapLibre's defaults for them. The map SHALL start at the initial camera, limited by the camera limits.

#### Scenario: Initial camera with pitch
- **WHEN** an application places a `MapigradeMap` with an initial camera of zoom 14, bearing 30, pitch 45, roll 10 and field of view 50
- **THEN** the first displayed frame's camera has zoom 14, bearing 30, pitch 45, roll 10 and field of view 50, within 0.001

#### Scenario: Padding moves the center
- **WHEN** an application places a `MapigradeMap` 800 logical pixels tall with an initial camera whose padding is 400 logical pixels at the top and 0 elsewhere
- **THEN** the camera's center coordinate is drawn 200 logical pixels below the widget's vertical middle, within 0.5 logical pixels

#### Scenario: Zoom convention
- **WHEN** a `MapigradeMap` and a `MapigradeLayer` in a `flutter_map` map show the same center, the map at zoom 10 and the `flutter_map` camera at zoom 11
- **THEN** both show the map at the same scale

### Requirement: Camera limits
The widget SHALL take `CameraLimits` with a minimum and a maximum zoom, a minimum and a maximum pitch, and optional `GeoBounds` that the camera's center stays within. Gestures, camera commands and the initial camera SHALL NOT take the camera outside the limits. When the application rebuilds the widget with different limits, a camera outside them SHALL move to the nearest camera within them.

#### Scenario: Maximum pitch
- **WHEN** the limits have a maximum pitch of 60 and a gesture tilts the map past it
- **THEN** the camera's pitch stops at 60

#### Scenario: Bounds
- **WHEN** the limits have bounds and a camera command targets a center outside them
- **THEN** the camera's center stays within the bounds

### Requirement: Camera controller
`mapigrade` SHALL provide `MapigradeCameraController`, which an application creates and gives to `MapigradeMap`. It SHALL be attached to at most one `MapigradeMap` at a time, as the `feature-query` requirement "Map controller" describes for `MapigradeController`, and calls on a detached controller, or before the map exists, SHALL fail with a `StateError`. It SHALL NOT extend or be extended by `MapigradeController`. Its `camera` SHALL be the camera of the frame that the widget displayed in the last Flutter frame it built, and SHALL be the initial camera before the first displayed frame.

#### Scenario: Camera of the displayed frame
- **WHEN** a gesture moves the camera and the application reads `camera` in a build
- **THEN** it equals the camera of the frame that the widget displays in that build

#### Scenario: Detached controller
- **WHEN** an application calls a camera command on a controller that isn't given to a widget in the tree
- **THEN** the returned `Future` completes with a `StateError`

### Requirement: Camera commands
The camera controller SHALL provide commands that jump to a camera, ease to a camera, fly to a camera, fit the camera to `GeoBounds` with optional padding, bearing and pitch, and cancel running transitions. A camera given to a command MAY omit fields, which keep their values. Each command except cancel SHALL return a `Future` that completes with a `CameraTransitionOutcome` when its transition ends: `completed` when it reached its target, `cancelled` when a cancel or a gesture stopped it, and `replaced` when a later command set every field it was still animating. Ease and fly SHALL take an optional duration.

#### Scenario: Jump
- **WHEN** the application jumps to a camera with zoom 12
- **THEN** the `Future` completes with `completed`, and a displayed frame after it has zoom 12

#### Scenario: Gesture interrupts a fly
- **WHEN** a fly is running and the user starts a pan
- **THEN** the fly's `Future` completes with `cancelled`, and the pan moves the map

#### Scenario: Fit to bounds
- **WHEN** the application fits the camera to the bounds of a route with 20 logical pixels of padding
- **THEN** every point of the route is at least 20 logical pixels inside the widget's edges in the frame after the transition

### Requirement: Camera streams
The camera controller SHALL provide a stream of `CameraChange` values, one for each displayed frame whose camera differs from the previous displayed frame's, each with the frame's camera and a `CameraChangeSource` that states whether a gesture or a command moved it. It SHALL also provide a stream that emits each time the camera comes to rest: when no gesture, glide, snap or camera transition is moving it.

#### Scenario: Pan reports gesture changes
- **WHEN** the user pans the map
- **THEN** the stream emits `CameraChange` values with the source `gesture`, and the rest stream emits once after the pan and its glide end

#### Scenario: Command reports command changes
- **WHEN** the application eases to a camera
- **THEN** the stream emits `CameraChange` values with the source `command`, and the rest stream emits once after the ease ends
