## 1. Rest probe in the core

- [x] 1.1 Add `MapTexture::AtRestForTesting()`, its probe command and `map_texture_at_rest_for_testing()` (design D1): the map thread answers at the end of the `RunOnce()` iteration in which it took the probe, without changing `repaint_wanted_` or queued frames; verify with native tests that a map with a loaded style is at rest, and a paused map with a pending update isn't until it resumes

## 2. Native test helpers

- [x] 2.1 Rewrite `Settled()` to wait for the frame count and then probe until at rest (design D2), failing after 10 seconds; verify with a new native test in which the fake surface target sleeps 400 ms before its second frame, that `Settled()` returns after that frame and `QueryFindsLineAtRest`'s check of the frame count then holds
- [x] 2.2 Verify that every caller of `Settled()` reaches rest: the native suite passes

## 3. Engine thread count

- [x] 3.1 Make `engines_test.dart` "maps of a destroyed engine are released" expect at most four more threads after the engine is destroyed than before (design D3); verify that the test passes on the Pixel, and 10 times in a row on the iPhone

## 4. Style loads

- [x] 4.1 Make `map_layer_test.dart` "onStyleLoaded is called once after the style has loaded" load `asset://assets/polyline_style.json` (`assets/style.json` has a PMTiles source, which leaks threads in MapLibre), and document on `onStyleLoaded` of `MapigradeLayer` and `MapTextureLayer` that the handler is called each time the map loads a style, which can be twice for one style URL; verify that `flutter analyze` reports no issues, and that the test passes 10 times in a row on the iPhone, after the 50-cycle test as in the full file
- [x] 4.2 Run the native suite 20 times in a row on macOS, and the integration tests on macOS, the Pixel and the iPhone (one background command per device); verify that every run passes, apart from the iPhone 13 failures caused by its 390-point width if that phone is used
