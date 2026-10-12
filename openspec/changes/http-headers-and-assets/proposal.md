## Why

Applications can't use a tile server that requires an access key in an HTTP header, because the layer sends no application headers. They also can't display a style or tiles that they bundle as Flutter assets, because MapLibre's `asset://` scheme reads from a root directory that the layer doesn't set. MapLibre Native FFI already supports both: a runtime-scoped HTTP header transform with native URL rules, and a runtime-scoped root for `asset://` URLs.

## What Changes

- `MapigradeLayer` gets a parameter `httpHeaders`, a list of `HttpHeaderRule`. Each rule has a URL glob and a map of header names to values. On each HTTP request that the map sends, the first rule whose glob matches the URL adds its headers. A request that matches no rule is sent without them, so an access key isn't sent to hosts that the application didn't list.
- The layer reads `httpHeaders` when it creates its map. When the layer is rebuilt with different rules, the map keeps the rules it was created with. The parameter's documentation says so.
- The layer rejects a header that MapLibre doesn't allow (an invalid name or value, or a header that MapLibre or the platform HTTP client manages): creating the map with it reports a `LayerCreateException`, and in debug builds the `HttpHeaderRule` constructor asserts on an invalid name or value.
- The layer resolves `asset://` URLs against the directory of the application's Flutter assets, so `asset://<asset key>` loads the Flutter asset with that key, for example `asset://assets/style.json` or `asset://packages/foo/tiles.pmtiles`. This applies to the style URL, and to every URL in a style, including the inner URL of `pmtiles://asset://...`.
- The main library exports `HttpHeaderRule`.
- The plugin's README describes both features, the glob syntax, and that an Android application must exclude `.pmtiles` assets from APK compression.

MBTiles files bundled as Flutter assets are out of scope: MapLibre opens MBTiles only from an absolute file path, and can't read a file inside an APK.

This change starts after `public-api` is archived, because it adds a parameter to `MapigradeLayer` and a name to the list of exported names that `public-api` introduces.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: new requirements "HTTP headers" (header rules, matching, validation, rules fixed at creation) and "Flutter assets" (`asset://` URLs load Flutter assets).
- `package-api`: the requirement "Exported names" adds `HttpHeaderRule`.

## Impact

- Dart API: new `MapigradeLayer.httpHeaders` parameter and new exported type `HttpHeaderRule`. No existing API changes.
- Dart code: `lib/src/layer/` (the public layer, the internal `MapTextureLayer`, a new file for `HttpHeaderRule`), `lib/src/texture/map_texture_controller.dart` and `bindings.dart` (the create call), the main library's `show` list, and tests.
- Native code: `map_texture_create` and `MapTexture` take and keep the header rules; `MapTexture::Init` sets the runtime's asset root and header transform; a new `PlatformAssetPath()` with an implementation for Android and one for macOS and iOS; `mln.h` includes the FFI's `callback_adapter.h`; the native test fake gains the new FFI functions.
- Test harness: an integration test with a local HTTP server that checks headers, and bundled assets (a style and a PMTiles file) with a `noCompress` rule in its Android build.
- Documents: the plugin's `README.md` and `CHANGELOG.md`.
