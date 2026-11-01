## ADDED Requirements

### Requirement: Android network security configuration
On Android, the map SHALL send its HTTP requests in accordance with the application's network security configuration. The package SHALL NOT add or change a network security configuration of the application. When the configuration blocks a request, for example a cleartext `http://` request to a host for which the application doesn't allow cleartext traffic, the map SHALL NOT send the request, and the layer SHALL report a load failure as the requirement "Failure reporting" describes. Requests that the map serves from its cache, from local files or from Flutter assets SHALL NOT be affected.

#### Scenario: Cleartext request that the application allows
- **WHEN** an Android application whose network security configuration allows cleartext traffic to `127.0.0.1` places the layer with a style URL `http://127.0.0.1:<port>/style.json` that a local HTTP server serves
- **THEN** the map renders the style

#### Scenario: Cleartext request that the configuration blocks
- **WHEN** the application from the previous scenario places the layer with the style URL `http://localhost:<port>/style.json`, where its network security configuration doesn't allow cleartext traffic to `localhost`
- **THEN** the application's failure handler receives a load failure, and the local HTTP server receives no request

#### Scenario: Header rules on Android
- **WHEN** the application from the first scenario places the layer with that style and a header rule that matches the style URL
- **THEN** the style request that the server receives carries the rule's headers
