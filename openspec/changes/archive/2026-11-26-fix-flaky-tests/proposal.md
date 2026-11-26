## Why

Three tests fail now and then for reasons outside the code they test, and we found each one while verifying the change `dispose-without-main-thread-join`:

- The native test helper `Settled()` treats 200 ms without a finished frame as "the map is at rest". A frame that takes longer, such as one that compiles a Metal shader on a cold cache, or a tile that loads after 200 ms, passes that check, and the test's later check of the frame count fails. `QueryFindsLineAtRest` failed this way once in about 155 runs; we reproduced it on `main` by making one render sleep 400 ms. `Settled()` has 38 callers.
- `engines_test.dart` "maps of a destroyed engine are released" allows one thread more after the engine is destroyed than before. On an iPhone, threads the test doesn't control (Dart and GCD pools) change the count by −2 to +2 between runs, so the test fails on `main` too.
- `map_layer_test.dart` "onStyleLoaded is called once after the style has loaded" expects exactly one call for a style URL. MapLibre delivers a cached copy of a style and then requests it from the network, and parses the style again when the network response has data. One map then reports two style loads about a second apart. This happens on `main`, and the `map-layer` spec's scenario "Style loaded" states the wrong behavior.

## What Changes

- The native core gets a test hook through which the map thread reports whether the map is at rest. `Settled()` uses it, so no wait in the native tests depends on 200 ms without a frame.
- The engine test allows four more threads after the engine is destroyed than before. The drift we measured was at most 2, and a leaked map adds about 12.
- The `onStyleLoaded` test loads a style that doesn't come through the network cache. The `map-layer` scenario "Style loaded" and the documentation of `onStyleLoaded` state that the handler is called each time the map loads a style, which can be more than once for one style URL.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: the requirement "Base layer of a flutter_map map" changes its scenario "Style loaded": the handler is called for each style load, and only for style loads.

## Impact

- Native core: a test hook in `packages/flutter_mapigrade/src/core/` (`map_texture.{h,cpp}`, `command_queue.h`, `map_texture_api.{h,cpp}`).
- Tests: `test/native/map_texture_tests.mm` (`Settled()` and its callers), and `engines_test.dart` and `map_layer_test.dart` in `packages/test_harness/integration_test/`.
- Dart API: documentation of `onStyleLoaded` on `MapigradeLayer` and `MapTextureLayer`. No behavior changes.
- `dispose-without-main-thread-join` (PR #15) also edits `map_texture_tests.mm`; whichever change merges second is rebased onto the other.
