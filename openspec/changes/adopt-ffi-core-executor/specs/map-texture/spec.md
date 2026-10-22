## MODIFIED Requirements

### Requirement: Memory warnings release cached renderer resources
When the operating system reports memory pressure (a memory warning on iOS; on Android, a trim memory level of `TRIM_MEMORY_BACKGROUND` or higher, or low memory), the system SHALL ask the renderer to release cached resources that it can rebuild. While the system submits no GPU work for the map because the application is in the background (requirement "No rendering while the application is in the background"), the renderer SHALL release them when rendering resumes, before it renders the next frame. The map SHALL continue to render and display frames afterwards.

#### Scenario: Memory warning during use
- **WHEN** the operating system reports memory pressure while a map is displayed
- **THEN** the application does not crash, and a later camera change produces a frame with that camera

#### Scenario: Memory warning while in the background
- **WHEN** the operating system reports memory pressure while the application is in the background, and the application then returns to the foreground
- **THEN** no GPU work is submitted for the map while the application is in the background, the map's statistics report the memory reduction after rendering resumes, and a later camera change produces a frame with that camera
