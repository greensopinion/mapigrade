## 1. Release queue in the core

- [x] 1.1 Add the release queue and release thread (design D2) in `packages/flutter_mapigrade/src/core/`: the thread starts when a map enters the empty queue, joins each map's map thread, marks the map stopped, posts its unregistration (D3), and exits when the queue is empty; verify with a native test in `test/native/core_tests.cpp` or `map_texture_tests.mm` that the release thread exits after the last release
- [x] 1.2 Add `MapTexture::UnregisterOnce()` (D3) and make `MapTexture::Dispose()` clear `callback_`, queue `kDispose`, signal and hand the map to the release queue without joining (D1); keep `~MapTexture()` joining for a failed `Start()`; verify with a native test that dispose returns within 100 ms while a blocking target task holds the map thread, and that no event is emitted after it returns
- [x] 1.3 Add `map_texture_wait_for_releases_for_testing(int64_t timeout_ms)` to `map_texture_api.h`/`.cpp` and the Dart binding in `lib/src/texture/bindings.dart`, exported through `lib/src/testing.dart` (D5); verify with a native test that it returns true after a dispose and that the target's `Unregister()` ran exactly once

## 2. Platform thread tasks

- [x] 2.1 Add `PostToPlatformThread` for Android: acquire the main thread's `ALooper` in `nativeInit`, register an `eventfd` with `ALooper_addFd`, and run queued tasks in the fd callback (D3); verify on the Pixel that a disposed map's `MapSurface.release` runs on the main thread (log the thread id once, then remove the log)
- [x] 2.2 Add `PostToPlatformThread` for Darwin with `dispatch_async` on the main queue, and a test implementation for the native test runner; verify that the native tests build and pass with `ctest --test-dir build/native-tests --output-on-failure`

## 3. Engine detach

- [x] 3.1 Make `map_texture::DisposeEngineMaps` dispose the engine's live maps (D1), wait until the release thread has stopped every queued map of that engine, and call `UnregisterOnce()` for each on the calling thread (D4); verify with a native test (`DisposeEngineMapsDisposesOnlyThatEngine` and a new test for a map disposed before the detach) that every map of the engine is unregistered when the call returns and the other engine's maps aren't

## 4. Tests

- [x] 4.1 Update the native tests in `test/native/map_texture_tests.mm` that expect the map thread stopped when dispose returns (e.g. `TaskWaitEndsAtDispose`, `SelectAfterDisposeReportsDisposed`) to call the wait hook; verify all native tests pass
- [x] 4.2 Call the wait hook before counting threads after disposal in `packages/test_harness/integration_test/map_texture_test.dart` and `map_layer_test.dart` ("50 create/dispose cycles keep the thread count stable" and similar); verify the tests pass on macOS
- [x] 4.3 Add the "Engine destroyed right after Dart disposes a map" scenario to `packages/test_harness/integration_test/engines_test.dart`; verify it passes on the Pixel and the iPhone with no error logged for the texture registration

## 5. Device verification

- [x] 5.1 Run the integration tests on macOS, the iPhone and the Pixel in parallel (one background command per device) and confirm they pass; close the apps on the devices afterwards
  - Note: macOS and the Pixel passed every file. On iPhones, the following tests failed, and each also fails on the base commit, so the change didn't cause them:
    - iPhone 13 (390 points wide): `static_alignment_test.dart`; in `map_texture_test.dart`, "style loads from URL and renders" and "a maximum cache size set while a map exists" (both need a 400-point view), "map with the copy renders frames with copies" and "resize keeps the selected frame until a new-size selection"; in `engines_test.dart`, "a second engine starts after the first engine shows a map" and "a second engine is destroyed" (the two-map Row overflows).
    - Wireless iPhone (iOS 27.2.1): in `engines_test.dart`, "maps of a destroyed engine are released" failed in 2 of 8 runs on this branch. Its limit of one extra thread is tighter than the drift between runs on this phone (from −2 to +2 here, and from −2 to +1 on the base commit).
- [x] 5.2 In the demo app on the Pixel, open and close map screens repeatedly while the map renders and loads tiles; confirm no ANR or main-thread stall is reported (`adb logcat` shows no "Input dispatching timed out") and that the thread count returns to its baseline after the wait
