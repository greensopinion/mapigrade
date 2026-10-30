## MODIFIED Requirements

### Requirement: Gallery
The demo SHALL open at a gallery that lists its showcases in this order: "Flyover", "Inspect features" and "Polylines". Each entry SHALL show the showcase's title and a sentence that states what the developer can try on its screen. Choosing an entry SHALL open the showcase's screen. Each showcase screen SHALL have its own map, which the screen creates when it opens and disposes when it closes. Each showcase screen SHALL have a control that goes back to the gallery, and the platform's back navigation SHALL also go back to the gallery. The gallery SHALL list only showcases of features that a user of an application sees or does; it SHALL NOT list settings such as HTTP headers, the layer's alignment or the tile cache size.

#### Scenario: Launch
- **WHEN** the demo starts without the recording mode
- **THEN** it shows the gallery with "Flyover", then "Inspect features", then "Polylines", each with a sentence that states what to try, and no map

#### Scenario: Open and close a showcase
- **WHEN** the developer chooses "Inspect features", and then uses the screen's control to go back
- **THEN** the inspect screen shows its map, and after going back the gallery is shown and the inspect screen's map is disposed

#### Scenario: Platform back navigation
- **WHEN** the developer uses the Android back gesture on the flyover screen
- **THEN** the demo shows the gallery

## ADDED Requirements

### Requirement: Polylines
The polyline screen SHALL display the map with `MapigradeLayer` as the base layer of a `flutter_map` map, with the `flutter_map` gestures for panning, zooming and rotating enabled. When the screen opens, the map SHALL show downtown New York in Liberty at zoom 16, with the camera over the Financial District. The screen SHALL draw these routes with one `MapigradePolylineLayer` in the layer's children, each along the streets or the water it names:

- a solid route along Broadway from Bowling Green to City Hall Park, with a border;
- a dashed route of the Staten Island Ferry from the Whitehall Terminal into the Upper Bay;
- a route along West Street from the Battery to Chambers Street, with a gradient from its start to its end;
- a route along Wall Street with a width in meters, which gets wider on the screen as the map zooms in.

The screen SHALL have a control that chooses the routes' placement: "Below buildings and labels", which is `LayerPlacement.belowLabels()` and is chosen when the screen opens, and "On top", which is `LayerPlacement.top()`. The screen SHALL offer the styles of the requirement "Styles", and choosing another style SHALL keep the camera, the routes and the chosen placement. The screen SHALL show a legend that names each route and how it is drawn.

#### Scenario: Open the polyline screen
- **WHEN** the developer chooses "Polylines" in the gallery
- **THEN** the map shows the Financial District in Liberty with its 3D buildings and the four routes, and the placement "Below buildings and labels" is chosen

#### Scenario: Buildings hide the routes
- **WHEN** the placement is "Below buildings and labels" and a tall building stands beside Broadway on the screen
- **THEN** the building hides the part of the route that it stands in front of, and street labels are drawn above the routes

#### Scenario: Routes on top
- **WHEN** the developer chooses "On top"
- **THEN** the routes are drawn above the buildings and the labels, and no building or label hides any part of them

#### Scenario: Width in meters
- **WHEN** the developer zooms in from zoom 16 to zoom 18
- **THEN** the Wall Street route is about four times as wide on the screen, and the other routes keep their width

#### Scenario: Change style on the polyline screen
- **WHEN** the placement is "On top" and the developer chooses Positron
- **THEN** the map shows Positron with the camera where it was, the four routes are drawn, and the placement is still "On top"
