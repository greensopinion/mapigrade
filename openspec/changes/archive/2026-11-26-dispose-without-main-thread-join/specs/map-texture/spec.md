## MODIFIED Requirements

### Requirement: Lifecycle and resource release
The system SHALL release the map, its render resources, its threads and its Flutter texture registration when Dart disposes the map. Dispose SHALL return to the caller without waiting for the map's threads to stop or for the map's render resources to be released; the system SHALL finish the release after dispose returns. No event SHALL reach Dart after dispose returns. Creating and disposing maps repeatedly SHALL NOT increase memory use or thread count without bound. Calls made after dispose SHALL fail with an error and SHALL NOT crash.

#### Scenario: Dispose releases resources
- **WHEN** a Dart caller creates and disposes a map 50 times in sequence, and the system then finishes every release
- **THEN** thread count returns to its value before the first create, and memory use stays within a bounded range

#### Scenario: Dispose doesn't wait for the map's threads
- **WHEN** Dart disposes a map while the map's render thread is blocked and doesn't stop for 10 seconds
- **THEN** dispose returns within 100 ms, no event of the map reaches Dart afterwards, and the system releases the map's threads and texture registration after the render thread stops

#### Scenario: Call after dispose
- **WHEN** a Dart caller sets the camera on a map that has been disposed
- **THEN** the call reports an error and the application continues to run

#### Scenario: Widget removed while rendering
- **WHEN** the map widget is removed from the tree and the map is disposed while a frame is rendering
- **THEN** the system completes or abandons the frame, releases its resources, and does not crash or deadlock

### Requirement: Multiple Flutter engines
The system SHALL support more than one Flutter engine in a process. Each map SHALL register its Flutter textures with the engine whose Dart code created the map, so that the map displays in that engine. A map SHALL keep working when another engine registers the plugin, and when another engine detaches the plugin or is destroyed. Maps that an engine creates after another engine has registered the plugin SHALL display in the engine that created them. The system SHALL use only public Flutter API to identify the engine.

On Android and iOS, when an engine detaches the plugin, the system SHALL release the maps that Dart in that engine created and didn't dispose, with their render resources, threads and texture registrations, and SHALL NOT change the maps of other engines. The detach SHALL NOT return before the texture registrations of every map of that engine are released, including maps that Dart disposed before the detach and whose release hasn't finished. On macOS, where Flutter doesn't report that an engine detaches the plugin, the maps that Dart in a destroyed engine created and didn't dispose MAY remain until the process ends, and SHALL NOT change the maps of other engines.

#### Scenario: A second engine starts after the first engine shows a map
- **WHEN** the application shows a map, then starts a second engine that registers every plugin, and then creates a new map in the first engine
- **THEN** both maps display in the first engine, and frames of the new map are reported to Dart in the first engine

#### Scenario: A second engine is destroyed
- **WHEN** a second engine registers the plugin and is then destroyed, and the first engine then creates a map
- **THEN** the new map displays in the first engine, and the maps that existed in the first engine before keep rendering

#### Scenario: Maps of a destroyed engine are released
- **WHEN** on Android or iOS a second engine creates a map, doesn't dispose it, and is then destroyed
- **THEN** the thread count returns to its value before the second engine created the map, and the maps of the first engine keep rendering

#### Scenario: Engine destroyed right after Dart disposes a map
- **WHEN** on Android or iOS a second engine creates a map, Dart in that engine disposes it, and the engine is destroyed before the map's release has finished
- **THEN** the application doesn't crash, no error is logged for the texture registration, and the thread count returns to its value before the second engine created the map

#### Scenario: Map created in each of two engines
- **WHEN** two engines each create a map
- **THEN** each map registers its textures with the engine that created it, and each engine receives the frames and events of only its own map
