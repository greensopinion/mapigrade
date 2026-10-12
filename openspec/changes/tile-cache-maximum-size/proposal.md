## Why

MapLibre stores tiles, styles, glyphs and sprites in a SQLite database (the ambient cache) at the path the plugin passes when it creates each map's runtime. The cache holds at most MapLibre's default of 50 MiB, and applications can't change that limit. An application whose users return to large areas, or who use the map with poor connectivity, needs a larger cache; an application with little storage to spare may need a smaller one.

## What Changes

- Dart can set the maximum size of the tile cache in bytes with a static function, `MapTextureController.setMaximumCacheSize(int bytes)`. The value applies to every map created after the call, in the whole process. Maps that already exist keep the limit they were created with.
- When no value has been set, maps use MapLibre's default of 50 MiB, as they do today.
- A negative value is rejected with an error. Zero is valid: MapLibre then keeps no ambient resources.
- Each map applies the limit to its runtime before it loads a style, so that no tile is stored, and no cached resource is evicted, under the 50 MiB default first.
- A failure to apply the limit is reported to Dart as a `RenderError` event. The map continues to load its style and render.

Out of scope: changing the limit of maps that already exist, setting the cache path, changing where the cache is stored (including the shared path of non-sandboxed macOS apps), and changing how long cached resources are fresh. MapLibre continues to use the server's `Cache-Control` and `Expires` headers.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: a new requirement, "Maximum tile cache size", covers setting the limit, its default, which maps it applies to, and invalid values.

## Impact

- Native core: `packages/flutter_mapigrade/src/core/map_texture_api.h` and `map_texture_api.cpp` (a new exported function and the process-wide value), `map_texture.cpp` (`MapTexture::Init()` applies the value to the new runtime). The platform code for macOS, iOS and Android doesn't change.
- Dart API: `packages/flutter_mapigrade/lib/src/texture/bindings.dart` and `map_texture_controller.dart` (the new static function). The change adds API and removes none.
- Tests: `packages/flutter_mapigrade/test/native/map_texture_tests.cpp` and `fake_mln.cpp` (the fake records the size calls); an example integration test or manual check that the limit holds across restarts.
- Documentation: the plugin's README.
- The in-flight change `android-texture-vertical-slice` modifies other `map-texture` requirements; this change adds a requirement and doesn't conflict with it.
