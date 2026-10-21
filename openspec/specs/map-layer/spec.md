# map-layer Specification

## Purpose

Displays the MapLibre map as the base layer of a `flutter_map` map, at the camera that `flutter_map` controls, so that `flutter_map` overlays drawn above it stay aligned with the map. Also measures how far the map and the overlays are apart during camera changes.

## Requirements

### Requirement: Base layer of a flutter_map map
The system SHALL provide a layer that an application places among the children of a `flutter_map` map. The layer SHALL display the map in the full viewport of the `flutter_map` map. Layers placed after it SHALL be drawn above it. The layer SHALL accept an optional list of child widgets, typically `flutter_map` layers, and SHALL draw them above the map, in list order, in the full viewport, as the requirement "Children aligned with the displayed map frame" describes. The layer SHALL load the style it is given, create its map when it is inserted into the widget tree, and dispose the map when it is removed. When the application gives a layer that is in the tree a different style, the layer SHALL load the new style into the map it has, without creating another map. The layer SHALL report to the application each time a style has loaded.

#### Scenario: Map below overlays
- **WHEN** an application places the layer as the first child of a `flutter_map` map, followed by a marker layer and a polyline layer
- **THEN** the map fills the `flutter_map` viewport, and the markers and polylines are drawn above it

#### Scenario: Map below its children
- **WHEN** an application places the layer with a polyline layer and a marker layer as its children
- **THEN** the map fills the `flutter_map` viewport, the polylines are drawn above the map, and the markers above the polylines

#### Scenario: Layer removed
- **WHEN** the layer is removed from the widget tree
- **THEN** its map is disposed, and repeating insert and remove 50 times doesn't increase thread count or memory use without bound

#### Scenario: Style loaded
- **WHEN** an application places the layer with a reachable style URL and a handler for loaded styles
- **THEN** the handler is called once after the style has loaded

#### Scenario: Style changed on a layer in the tree
- **WHEN** the style of a layer in the tree has loaded, and the application rebuilds the layer with a different style URL, as it does when the platform switches between light and dark mode
- **THEN** the map renders using the new style, the handler for loaded styles is called again, and the layer creates no other map

### Requirement: Map follows the flutter_map camera
The system SHALL set the map camera from the `flutter_map` camera whenever the `flutter_map` camera changes. The MapLibre zoom SHALL be the `flutter_map` zoom minus 1, the MapLibre bearing SHALL be the negated `flutter_map` rotation, and the map viewport SHALL be the size of the `flutter_map` viewport before rotation. Pitch SHALL be 0. In the camera prediction mode the system SHALL set the predicted camera instead (requirement "Camera prediction").

#### Scenario: Camera change
- **WHEN** the `flutter_map` camera changes through a gesture or a camera controller call
- **THEN** a later displayed map frame reports the converted camera

#### Scenario: Camera jump larger than the viewport
- **WHEN** the `flutter_map` camera moves in one step by more than the viewport
- **THEN** a later displayed map frame reports the new camera, and the map shows it

#### Scenario: Rotated map
- **WHEN** the `flutter_map` rotation is 30 degrees
- **THEN** the map is rotated by the same angle in the same direction as the overlays, and fills the viewport without empty corners when the camera is at rest

### Requirement: Alignment at rest
When the camera is at rest and the map has displayed a frame for it, a geographic coordinate SHALL appear at the same screen position in the map and in `flutter_map` overlays, within 1 logical pixel.

#### Scenario: Marker at a known coordinate
- **WHEN** the style draws a marker at a coordinate, a `flutter_map` marker is placed at the same coordinate, and the camera is at rest
- **THEN** the centers of the two markers on screen are at most 1 logical pixel apart

#### Scenario: Zoom, rotation, latitude and longitude
- **WHEN** the static alignment check runs at fractional and integer zoom levels, with rotation, at latitudes up to 80 degrees, and with the camera within 1 degree of the antimeridian
- **THEN** each case meets the 1 logical pixel limit

#### Scenario: After resize
- **WHEN** the `flutter_map` viewport is resized and the camera is then at rest
- **THEN** the markers meet the 1 logical pixel limit at the new size

### Requirement: Camera prediction
The system SHALL provide a camera prediction mode for the layer, with a lead given as a number of display refresh intervals. The layer SHALL provide one alignment option with two values: camera prediction at a stated lead, or no alignment. Camera prediction with a lead of 1 SHALL be the layer's default. In the prediction mode the system SHALL set the map camera to the converted `flutter_map` camera extrapolated by the lead from the camera's velocity over the last Flutter frames, for center, zoom and bearing. When the `flutter_map` camera hasn't changed since the previous Flutter frame, the predicted camera SHALL equal the converted camera. With either value, the system SHALL draw the displayed map frame at the position of the layer, without moving, scaling or rotating it.

#### Scenario: Default layer
- **WHEN** an application places the layer without configuring its alignment, and the `flutter_map` camera pans at a constant speed
- **THEN** the camera the map renders is ahead of the converted camera by 1 refresh interval of that movement, and the displayed map frame is drawn at the position of the layer

#### Scenario: Steady pan
- **WHEN** the prediction mode is on with a lead of n refresh intervals, and the `flutter_map` camera pans at a constant speed
- **THEN** the camera the map renders is ahead of the converted camera by n refresh intervals of that movement, in the direction of the pan

#### Scenario: Camera at rest
- **WHEN** the prediction mode is on and the `flutter_map` camera stops changing
- **THEN** a later displayed map frame reports the converted camera, and the map and the overlays meet the requirement "Alignment at rest"

#### Scenario: Antimeridian
- **WHEN** the prediction mode is on and the `flutter_map` camera pans across the antimeridian
- **THEN** the velocity uses the shorter longitude difference, and the predicted camera does not jump by a world width

#### Scenario: No alignment
- **WHEN** the layer is configured with no alignment, and the `flutter_map` camera moves
- **THEN** the map camera is the converted camera, the displayed map frame is drawn at the position of the layer, and no strips are uncovered at the viewport edges

### Requirement: Alignment measurement
The system SHALL provide a measurement mode that records, for each Flutter frame during camera changes, the map frame that Flutter displayed and the `flutter_map` camera. From these it SHALL compute the alignment error in logical pixels: the largest distance at the viewport corners and center between where the displayed map frame, as the layer draws it, draws a coordinate and where the overlays draw it. The measurement mode SHALL run with the layer configured with camera prediction at a stated lead or with no alignment, and with the overlays placed after the layer or as its children, and SHALL report the configuration. With the overlays as children, the overlays SHALL be drawn at the camera the layer gives its children, and the measurement mode SHALL also report the lag: the distance at the viewport center between where the displayed map frame draws a coordinate and where the live `flutter_map` camera places it. The measurement mode SHALL include phases in which the pan stops abruptly, decelerates as a `flutter_map` fling does, and reverses direction, and for these SHALL report the overshoot: the largest alignment error from the moment the camera's motion changes (an abrupt stop, the start of a deceleration, or a reversal) until half a second after the camera is at rest or moves at constant speed again, and the overshoot ahead: over the same time, the largest distance at the viewport center by which the drawn map is ahead of the overlays in the direction of motion before the change, or 0 if it isn't ahead. With the overlays as children, the overshoot ahead SHALL be measured against the live `flutter_map` camera instead of the overlays.

#### Scenario: Pan at a stated speed
- **WHEN** the alignment benchmark pans at a constant stated speed in logical pixels per second
- **THEN** the report states the speed, the layer configuration, and the p50, p95 and largest alignment error

#### Scenario: Pan at a stated speed with children
- **WHEN** the alignment benchmark pans at a constant stated speed with the overlays as children of the layer
- **THEN** the report states the speed, the layer configuration, the p50, p95 and largest alignment error, and the p50, p95 and largest lag

#### Scenario: Pan that stops
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and stops abruptly, or decelerates to rest as a `flutter_map` fling does
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead of each stop, as p50 and largest over the stops in the phase

#### Scenario: Pan that reverses
- **WHEN** the alignment benchmark pans at 1,000 logical px/s and reverses direction abruptly
- **THEN** the report states the layer configuration, and the overshoot and the overshoot ahead after each reversal, as p50 and largest over the reversals in the phase

### Requirement: Failure reporting
The layer SHALL report each failure of its map to the application's failure handler, with a type that states the kind of failure and a message that describes the cause. The kinds SHALL be: loading the style or a resource it needs failed, rendering failed, and the map couldn't be created. When the map reports the same load failure again while it retries, the layer SHALL report it only once until the application gives a different style. When the application gives no failure handler, the layer SHALL report the failure through Flutter's error reporting, naming the package as the source. A failure SHALL NOT be thrown into the application's code, and the application SHALL continue to run.

#### Scenario: Style fails to load
- **WHEN** an application places the layer with an unreachable style URL and a failure handler
- **THEN** the handler receives a load failure with a message that describes the cause, and the application continues to run

#### Scenario: No failure handler
- **WHEN** an application places the layer with an unreachable style URL and no failure handler
- **THEN** Flutter's error reporting receives the load failure once, with the package named as the source, and the application continues to run

#### Scenario: Map can't be created
- **WHEN** creating the layer's map fails
- **THEN** the handler receives a creation failure, the layer occupies the viewport without drawing anything, and the overlays after it are still drawn

### Requirement: HTTP headers
The layer SHALL accept a list of header rules from the application. Each rule SHALL consist of a URL pattern and a set of HTTP headers, each a name and a value. For each HTTP request that the map sends, the map SHALL add the headers of the first rule, in list order, whose pattern matches the complete URL of the request, and SHALL add no application headers when no rule matches. A pattern SHALL be compared with the URL byte for byte and case-sensitively, where `*` matches any run of characters that contains no `/`, `**` matches any run of characters, `?` matches one character other than `/`, and `\` makes the next character literal. The layer SHALL reject a header whose name isn't a valid HTTP field name, whose value contains a control character other than horizontal tab, or whose name is one that MapLibre or the platform HTTP client manages: creating the map SHALL report a creation failure that names the header and doesn't contain its value. In debug builds, the rule's constructor SHALL also fail an assertion for an invalid name or a control character in a value. The layer SHALL read the rules when it creates its map; when the application rebuilds a layer that is in the tree with different rules, the map SHALL keep sending the rules it was created with. Requests that the map serves from its cache or from local files SHALL NOT be affected.

#### Scenario: Header sent to a matching host
- **WHEN** an application places the layer with a style whose tiles are on `https://tiles.example.com/`, and the rule `https://tiles.example.com/**` with the header `X-Access-Key: k1`
- **THEN** each tile request to `tiles.example.com` carries `X-Access-Key: k1`

#### Scenario: Header not sent to another host
- **WHEN** the style from the previous scenario also loads glyphs from `https://fonts.example.org/`
- **THEN** the glyph requests carry no `X-Access-Key` header

#### Scenario: First matching rule wins
- **WHEN** the rules are `https://tiles.example.com/v2/**` with `X-Access-Key: k2`, followed by `https://tiles.example.com/**` with `X-Access-Key: k1`
- **THEN** a request to `https://tiles.example.com/v2/1/2/3.pbf` carries `k2` only, and a request to `https://tiles.example.com/v1/1/2/3.pbf` carries `k1`

#### Scenario: Single-segment wildcard
- **WHEN** the rule is `https://*.example.com/**`
- **THEN** a request to `https://a.example.com/x` carries the rule's headers, and a request to `https://attacker.example/x.example.com/x` doesn't

#### Scenario: Header that MapLibre manages
- **WHEN** an application places the layer, in a release build, with a rule whose header name is `Host`, or whose header value contains a line feed
- **THEN** the application's failure handler receives a creation failure that names the header and doesn't contain its value

#### Scenario: Rules changed on a layer in the tree
- **WHEN** the application rebuilds a layer in the tree with a rule that has a different header value
- **THEN** the map keeps sending the value it was created with, and the layer creates no other map

### Requirement: Flutter assets
The layer SHALL resolve URLs with the `asset://` scheme against the application's Flutter assets: `asset://<key>` SHALL load the Flutter asset with the key `<key>`, where the key is percent-decoded. This SHALL apply to the style URL and to every URL in a style, including the URL inside a `pmtiles://` URL. A request for a key that has no asset SHALL report a load failure.

#### Scenario: Style from an asset
- **WHEN** the application bundles `assets/style.json` as a Flutter asset and places the layer with the style URL `asset://assets/style.json`
- **THEN** the map renders the style

#### Scenario: PMTiles from an asset
- **WHEN** the style has a vector source with the URL `pmtiles://asset://assets/tiles.pmtiles`, and the application bundles that file as a Flutter asset
- **THEN** the map renders the tiles of that file on Android, iOS and macOS

#### Scenario: Asset of a package
- **WHEN** a package `foo` that the application depends on declares the asset `assets/style.json`, and the layer's style URL is `asset://packages/foo/assets/style.json`
- **THEN** the map renders the style

#### Scenario: Missing asset
- **WHEN** the layer's style URL is `asset://assets/missing.json` and no such asset exists
- **THEN** the application's failure handler receives a load failure

### Requirement: Unsupported platforms and architectures
An application that depends on the package SHALL build, start and run where the package's native library isn't available: on an Android device whose process can't load the native library, for example because the device has none of the ABIs `arm64-v8a`, `armeabi-v7a` and `x86_64`, and on web, for which the package has no native library. An application built for web SHALL build with the package with both web compilers, to JavaScript and to WebAssembly. The package SHALL then not call native code for the life of the process. The layer SHALL offer a static property, `MapigradeLayer.isSupported`, that is true when the native library is available in the process and false otherwise, and that an application can read before it places the layer. When the native library isn't available and an application places the layer, the layer SHALL report a creation failure whose message states that the native library isn't available, as the requirement "Failure reporting" describes, and SHALL NOT throw into the application's code.

#### Scenario: App starts without the native library
- **WHEN** an application that depends on the package starts on an Android device whose process can't load the native library
- **THEN** the application starts and runs, and the package logs a warning that names the device's ABIs

#### Scenario: Application built for web
- **WHEN** an application that depends on the package and places `MapigradeLayer` is built for web, once compiled to JavaScript and once to WebAssembly
- **THEN** both builds succeed

#### Scenario: Application runs on web
- **WHEN** an application that depends on the package runs on web
- **THEN** the application starts and runs, and `MapigradeLayer.isSupported` is false

#### Scenario: Application chooses another layer
- **WHEN** an application reads `MapigradeLayer.isSupported` in a process without the native library
- **THEN** the value is false, and the application can place another layer, such as a raster tile layer, in place of `MapigradeLayer`

#### Scenario: Layer placed without the native library
- **WHEN** an application places `MapigradeLayer` with a failure handler in a process without the native library, including on web
- **THEN** the handler receives one creation failure that states that the native library isn't available, the layer occupies the viewport without drawing anything, and the overlays after it are still drawn

#### Scenario: Supported device
- **WHEN** an application reads `MapigradeLayer.isSupported` on an Android device or emulator running the application with the ABI `arm64-v8a`, `armeabi-v7a` or `x86_64`, on an iPhone or on an Apple-silicon Mac, in an app built with the package's native library
- **THEN** the value is true

### Requirement: Metrics
The layer SHALL accept an optional metrics object from the application. When the application takes a snapshot of the object, the snapshot SHALL contain:

- the time of the snapshot, on a monotonic clock that all metrics objects in the process share;
- the number of map frames given to Flutter for display. On macOS and iOS a frame SHALL count when Flutter takes it for display; on Android, when Dart chooses it for display;
- the number of frames the map rendered;
- the total time the map spent in its render calls.

The counts and the render time SHALL be those of one map, from the map's creation: the map of the layer that the object was last given to. Before the layer has a map, and when the layer's map couldn't be created, every count and the render time SHALL be 0. A style change keeps the map, and SHALL NOT reset the counts. When the layer disposes its map, the object SHALL keep the values read just before the dispose; these MAY lack frames that the map rendered after the read. When the layer has a new map, for example after the application gives the layer a new key, an object given to it SHALL report the new map's values, starting from 0. When the application rebuilds the layer with a different object and the layer keeps its map, the new object SHALL report that map's values from the map's creation, and the previous object SHALL keep the values read when it was replaced. Taking a snapshot SHALL NOT throw, and a layer given no metrics object SHALL behave as before this requirement.

#### Scenario: Camera moves
- **WHEN** an application places the layer with a metrics object and a style, takes a snapshot, pans the camera for 2 seconds and takes another snapshot
- **THEN** in the second snapshot the time, the displayed frames, the rendered frames and the render time are greater than in the first, and the displayed frames are at most the rendered frames

#### Scenario: Map at rest
- **WHEN** the map has loaded the style and stopped rendering, and the application takes two snapshots 1 second apart
- **THEN** both snapshots have the same counts and render time, and the second has a later time

#### Scenario: No map yet
- **WHEN** the application takes a snapshot of an object that it hasn't given to a layer, or given to a layer that hasn't created its map
- **THEN** the counts and the render time are 0

#### Scenario: Map can't be created
- **WHEN** the layer's map can't be created and the application takes a snapshot
- **THEN** the counts and the render time are 0, and the snapshot doesn't throw

#### Scenario: Style change
- **WHEN** the application gives the layer a different style after the map has rendered frames
- **THEN** no count in a later snapshot is lower than in the snapshot before the change

#### Scenario: Layer removed
- **WHEN** the application removes the layer from the tree and then takes snapshots
- **THEN** each snapshot has the values read when the layer disposed its map, no count is lower than in the last snapshot before the removal, and later snapshots have the same values

#### Scenario: New key with the same object
- **WHEN** the application gives the layer a new key and the same metrics object
- **THEN** snapshots report the new map's values, starting from 0

#### Scenario: Different object for the same map
- **WHEN** the application rebuilds the layer, with the same key, with a different metrics object
- **THEN** the new object reports the map's values from the map's creation, and the previous object keeps the values read when it was replaced

### Requirement: Children aligned with the displayed map frame
The layer SHALL draw its children at the `flutter_map` camera that the displayed map frame was rendered for, including when the system refuses the layer's choice of a frame (requirement "Display slots" of `map-texture`): the camera from which the layer converted, or with camera prediction predicted, the map camera of that frame. In each Flutter frame, during camera changes and at rest, a geographic coordinate SHALL appear at the same screen position in the map and in the children, within 1 logical pixel. Until the map has displayed a frame, the layer SHALL draw its children at the live `flutter_map` camera. The children SHALL get the same `flutter_map` map controller and map options as the layers placed after the layer. The children SHALL receive pointer input, and a child that hit-tests its content SHALL hit-test it at the position where it draws it. The layer SHALL NOT change the camera that the layers placed after it, and `flutter_map`'s gesture handling, use.

#### Scenario: Pan with children
- **WHEN** a polyline layer is a child of the layer, and the `flutter_map` camera pans at 1,000 logical px/s
- **THEN** in each Flutter frame the polyline and the same line drawn by the style are at most 1 logical pixel apart

#### Scenario: Fling, stop and reversal with children
- **WHEN** a marker layer is a child of the layer, and the `flutter_map` camera decelerates as a fling does, stops abruptly, or reverses
- **THEN** in each Flutter frame the markers and the map meet the 1 logical pixel limit

#### Scenario: Children with camera prediction
- **WHEN** the layer has camera prediction on with a lead of 1, and its children include a marker layer
- **THEN** the markers are drawn at the predicted camera of the displayed map frame, and meet the 1 logical pixel limit

#### Scenario: Tap on a child
- **WHEN** during a pan the user taps a polyline that is a child of the layer, at a point where the screen shows it
- **THEN** the polyline layer's hit test reports the polyline

#### Scenario: Siblings keep the live camera
- **WHEN** a marker layer is a child of the layer and a scale bar is placed after the layer
- **THEN** the scale bar is drawn at the live `flutter_map` camera

#### Scenario: Before the first displayed frame
- **WHEN** the layer has children and its map hasn't displayed a frame yet
- **THEN** the children are drawn at the live `flutter_map` camera

#### Scenario: Android
- **WHEN** on the reference Android device the layer has a route and markers as children, and a tester pans and flings the map by hand
- **THEN** the route and the markers stay on the map in every Flutter frame, as the tester judges by eye
