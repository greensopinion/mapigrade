## MODIFIED Requirements

### Requirement: Visible bounds and tiles of the visible ground

When pitched, the camera's visible bounds SHALL contain every coordinate visible in the viewport, except that, as for an unpitched map, they SHALL be limited to longitudes from -180 to 180. The tile layer SHALL load tiles that cover the visible ground, each at the zoom that the requirement "Tile zoom from size on screen" gives, including on both sides of the antimeridian.

#### Scenario: Far edge in visible bounds

- **WHEN** the map is at pitch 60
- **THEN** the coordinates at the four corners of the viewport are within the visible bounds

#### Scenario: Tiles across the antimeridian

- **WHEN** the map is at pitch 60, in a CRS that repeats the world horizontally, with the far edge of the view across the antimeridian
- **THEN** the tile layer loads the tiles on both sides, and every position in the viewport shows a tile

#### Scenario: Far tiles loaded

- **WHEN** the map is at pitch 60 and a coordinate is at the top edge of the viewport
- **THEN** the tile layer loads a tile that contains the coordinate, at a zoom coarser than the tile zoom at the center of the viewport

## ADDED Requirements

### Requirement: Tile zoom from size on screen

The tile layer SHALL choose each tile's zoom so that, at the tile's point nearest the camera within the visible ground, one pixel of the tile is drawn at more than 1/√2 and at most √2 screen pixels, as at the center of an unpitched map, but no finer than the tile zoom of an unpitched map at the same camera zoom: the camera zoom rounded, within the native zoom limits. Where that zoom is below the minimum native zoom, the tile layer SHALL use the minimum native zoom. Where a tile is replaced by its four children because one of them needs a finer zoom, a child MAY be drawn at 1/√2 or fewer screen pixels per tile pixel.

#### Scenario: Coarser tiles far away

- **WHEN** the map is at pitch 60
- **THEN** every loaded tile in the visible ground that is coarser than the tile at the center is drawn at most √2 screen pixels per tile pixel at its nearest point, and the tiles at the top edge of the viewport are at a coarser zoom than the tile at the center

#### Scenario: No finer tiles near the camera

- **WHEN** the map is at pitch 60 and the camera zoom is 0.45 above an integer
- **THEN** no loaded tile is at a zoom above the camera zoom rounded, and the tiles at the bottom edge of the viewport are at that zoom

#### Scenario: Maximum native zoom

- **WHEN** the map is at pitch 60 and the tile at the center is at the maximum native zoom
- **THEN** no loaded tile is at a zoom above the maximum native zoom

### Requirement: Tiles that the tile layer loads and keeps

The tile layer SHALL load the tiles that touch the visible ground and the tiles within the pan buffer of them, where the pan buffer of a tile is the tiles at that tile's zoom within a number of tiles of it that don't touch the visible ground. It SHALL NOT load other tiles, except tiles that fill a gap while a tile loads. It SHALL keep loaded tiles within the larger of the pan buffer and the keep buffer of those tiles, defined in the same way, and tiles that fill a gap, and prune the others. An unrotated, unpitched map SHALL load, draw and prune the same tiles as the release the fork starts from.

#### Scenario: Rotated map

- **WHEN** the map is unpitched at rotation 45 with a pan buffer of 1
- **THEN** every loaded tile at the tile zoom touches the viewport or is a neighbor of a tile that does, and no tile in the corners of the viewport's bounding box beyond that is loaded

#### Scenario: Pitched and rotated map

- **WHEN** the map is at pitch 60 and rotation 45 with a pan buffer of 1
- **THEN** every loaded tile touches the visible ground, or doesn't touch it and is a neighbor, at its own zoom, of a tile that does

#### Scenario: Unrotated, unpitched map

- **WHEN** the map is unpitched and unrotated
- **THEN** the tile layer's existing tests pass without changes

### Requirement: Tile load order

The tile layer SHALL start loading new tiles in order of the distance on screen from the center of the viewport to the center of each tile.

#### Scenario: Pitched load order

- **WHEN** the map is at pitch 60 and the tile layer starts loading the tiles of a new view
- **THEN** each tile starts loading no later than every tile whose center is farther from the center of the viewport on screen
