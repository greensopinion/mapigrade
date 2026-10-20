## ADDED Requirements

### Requirement: Multiple Flutter engines
The system SHALL support more than one Flutter engine in a process. Each map SHALL register its Flutter textures with the engine whose Dart code created the map, so that the map displays in that engine. A map SHALL keep working when another engine registers the plugin, and when another engine detaches the plugin or is destroyed. Maps that an engine creates after another engine has registered the plugin SHALL display in the engine that created them. The system SHALL use only public Flutter API to identify the engine.

On Android and iOS, when an engine detaches the plugin, the system SHALL release the maps that Dart in that engine created and didn't dispose, with their render resources, threads and texture registrations, and SHALL NOT change the maps of other engines. On macOS, where Flutter doesn't report that an engine detaches the plugin, the maps that Dart in a destroyed engine created and didn't dispose MAY remain until the process ends, and SHALL NOT change the maps of other engines.

#### Scenario: A second engine starts after the first engine shows a map
- **WHEN** the application shows a map, then starts a second engine that registers every plugin, and then creates a new map in the first engine
- **THEN** both maps display in the first engine, and frames of the new map are reported to Dart in the first engine

#### Scenario: A second engine is destroyed
- **WHEN** a second engine registers the plugin and is then destroyed, and the first engine then creates a map
- **THEN** the new map displays in the first engine, and the maps that existed in the first engine before keep rendering

#### Scenario: Maps of a destroyed engine are released
- **WHEN** on Android or iOS a second engine creates a map, doesn't dispose it, and is then destroyed
- **THEN** the thread count returns to its value before the second engine created the map, and the maps of the first engine keep rendering

#### Scenario: Map created in each of two engines
- **WHEN** two engines each create a map
- **THEN** each map registers its textures with the engine that created it, and each engine receives the frames and events of only its own map
