## ADDED Requirements

### Requirement: Maximum tile cache size
The system SHALL let Dart set the maximum size, in bytes, of the cache in which the renderer keeps downloaded resources (tiles, styles, glyphs and sprites). The value SHALL apply to every map that is created after it is set, in the whole process, and SHALL NOT change the limit of a map that already exists. A map SHALL apply its limit before it stores or evicts any cached resource. When Dart has not set a value, a map SHALL use a limit of 50 MiB. Zero SHALL be a valid value. When the cache holds more resources than a map's limit allows, the map SHALL evict resources, at the latest each time it stores a resource, until the cache holds at most its limit. A negative value SHALL be rejected with an error and SHALL leave the previous value in effect. When the system fails to apply the limit to a map, it SHALL report an error to Dart, and the map SHALL continue to load styles and render.

#### Scenario: Larger limit keeps the cache across restarts
- **WHEN** Dart sets a limit of 200 MiB before it creates a map, and the cache holds more than 50 MiB of resources from an earlier run of the application with the same limit
- **THEN** after the map has loaded its style and tiles, the cache still holds more than 50 MiB of resources

#### Scenario: Smaller limit evicts resources
- **WHEN** Dart sets a limit of 10 MiB before it creates a map, and the cache holds more than 10 MiB of resources
- **THEN** after the map has loaded its style and stored new tiles, the cache holds at most about 10 MiB of resources, and the map displays frames

#### Scenario: Default limit
- **WHEN** Dart creates a map without having set a limit, and the map loads more than 50 MiB of resources
- **THEN** the cache holds at most 50 MiB of resources

#### Scenario: Existing map keeps its limit
- **WHEN** Dart sets a limit while a map exists, and then creates a second map
- **THEN** the existing map keeps the limit it was created with, and the second map uses the new limit

#### Scenario: Negative limit is rejected
- **WHEN** Dart sets a limit of -1
- **THEN** the call fails with an error, and maps created afterwards use the value that was in effect before the call
