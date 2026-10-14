## ADDED Requirements

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
