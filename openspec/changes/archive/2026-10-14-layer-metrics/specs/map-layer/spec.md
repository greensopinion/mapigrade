## ADDED Requirements

### Requirement: Metrics
The layer SHALL accept an optional metrics object from the application. When the application takes a snapshot of the object, the snapshot SHALL contain:

- the time of the snapshot, on a monotonic clock that all metrics objects in the process share;
- the number of map frames given to Flutter for display. On macOS and iOS a frame SHALL count when Flutter takes it for display; on Android, when the map has queued it for display;
- the number of frames the map rendered;
- the total time the map spent in its render calls.

The counts and the render time SHALL be those of one map, from the map's creation: the map of the layer that the object was last given to. Before the layer has a map, and when the layer's map couldn't be created, every count and the render time SHALL be 0. A style change keeps the map, and SHALL NOT reset the counts. When the layer disposes its map, the object SHALL keep the values read just before the dispose; these MAY lack frames that the map rendered after the read. When the layer has a new map, for example after the application gives the layer a new key, an object given to it SHALL report the new map's values, starting from 0. When the application rebuilds the layer with a different object and the layer keeps its map, the new object SHALL report that map's values from the map's creation, and the previous object SHALL keep the values read when it was replaced. Taking a snapshot SHALL NOT throw, and a layer given no metrics object SHALL behave as before this requirement.

#### Scenario: Camera moves
- **WHEN** an application places the layer with a metrics object and a style, takes a snapshot, pans the camera for 2 seconds and takes another snapshot
- **THEN** in the second snapshot the time, the displayed frames, the rendered frames and the render time are greater than in the first; on macOS and iOS the displayed frames are at most the rendered frames, and on Android they are equal

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
