## 1. Native core (D61, D62, D63)

- [x] 1.1 Add `map_texture_set_maximum_cache_size(int64_t bytes)` to `src/core/map_texture_api.h` and `.cpp`: it stores the value under `registry_mutex` and returns `MAP_TEXTURE_ERROR_INVALID_ARGUMENT` for a negative value; `map_texture_create` passes the stored value (or none) to the `MapTexture` constructor; verify that the plugin builds for macOS (`flutter build macos` in `packages/test_harness/`)
- [x] 1.2 In `MapTexture::Init()`, when the map has a value, call `mln_runtime_set_maximum_ambient_cache_size_start()` right after `mln_runtime_create()` and before `mln_map_create()`, discard the operation with `mln_runtime_offline_operation_discard()`, and on a start failure call `ReportStatus()` and continue; verify with the native tests in 1.3
- [x] 1.3 In `test/native/fake_mln.cpp` and `fake_mln.h`, implement the two FFI functions so that the fake records each size and the order of the size call relative to `mln_map_create` and the style load, and can make the start fail; add tests to `map_texture_tests.cpp`: no size call without a value; a set value reaches the next map before `mln_map_create` and its style load; a value set while a map exists doesn't reach that map but reaches the next one; a negative value returns `MAP_TEXTURE_ERROR_INVALID_ARGUMENT` and the previous value stays; a start failure emits a render error and the map still renders; verify with `ctest --test-dir build/native-tests --output-on-failure`

## 2. Dart API (D64)

- [x] 2.1 Add the `map_texture_set_maximum_cache_size` binding to `lib/src/texture/bindings.dart` and the internal static `MapTextureController.setMaximumCacheSize(int bytes)` to `map_texture_controller.dart`; it throws `ArgumentError` for a negative value and `MapTextureException` for a native error; verify with `flutter analyze` in the package and a unit test in `test/` that a negative value throws `ArgumentError`
- [x] 2.2 Add the static property `MapigradeLayer.maximumCacheSizeBytes` to `lib/src/layer/mapigrade_layer.dart`, with the documentation D64 lists: the getter returns the last value set or 52,428,800, the setter calls `MapTextureController.setMaximumCacheSize` and stores the value only when the call succeeds; verify with unit tests in `test/layer/mapigrade_layer_test.dart` that the getter returns 52,428,800 before any set, that setting -1 throws `ArgumentError` and leaves the getter unchanged, and that `test/api_test.dart` still passes

## 3. Example and integration test

- [ ] 3.1 Add an integration test to `packages/test_harness/integration_test/map_texture_test.dart` that sets a limit through `MapigradeLayer.maximumCacheSizeBytes`, creates a map, loads the style and waits for `MapIdle` without a render error; a second case sets the limit while a map exists, creates a second map, and both reach `MapIdle`; verify that the tests pass on macOS and on the iPhone

## 4. Limit holds across restarts (spec scenarios)

- [ ] 4.1 On macOS, set 200 MiB in the test harness before the first map is created (a temporary change, or a `--dart-define`), browse until the cache database's size (`sqlite3 <cache.db> 'pragma page_count; pragma page_size'`, path from `PlatformCachePath()` in the app container) exceeds 50 MiB, quit, start the app again and load the same area; verify that the size is still above 50 MiB. Repeat with no limit set and verify that the size is at most about 50 MiB, then with 10 MiB and verify that it falls to at most about 10 MiB and the map displays frames. Record the measured sizes in the change's design.md under a "Results" heading

## 5. Documentation

- [x] 5.1 Describe the setting in `packages/flutter_mapigrade/README.md`: the default of 50 MiB, that it applies to maps created after the call, that maps sharing the cache file each evict to their own limit, and that freshness follows the server's cache headers; verify that `git grep -n maximumCacheSizeBytes packages/flutter_mapigrade/README.md` finds the section
