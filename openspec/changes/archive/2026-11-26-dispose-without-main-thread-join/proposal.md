## Why

Android vitals reported an ANR in `MapTexture::Dispose` (rank 9, 1 account, new): the main thread waited in `thread_.join()` for the map thread. Dart calls `map_texture_dispose` on the platform thread, because the Dart UI isolate runs on the platform thread (Flutter's merged platform and UI thread). The join waits for the map thread to finish its current loop iteration and then `Teardown()`, which waits up to 30 s for `mln_map_release` and up to 30 s for `mln_runtime_release`. Android reports an ANR after 5 s. iOS and macOS use the same join and can hang the main thread the same way.

## What Changes

- `map_texture_dispose` returns without waiting for the map thread to stop. The map's handle is invalid and no event reaches Dart after it returns, as before.
- A thread other than the platform thread waits for the map thread to stop. After the map thread stops, the system releases the Flutter texture registration on the platform thread.
- When an engine detaches the plugin, the detach waits for the release of that engine's maps, including maps that Dart disposed before and whose release is still running, so that their texture registrations are released before the engine detaches.
- A test hook waits until every pending release has finished, for tests that count threads or check release after dispose.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: "Lifecycle and resource release" requires that dispose doesn't wait for the map's threads to stop, and that the release finishes after dispose returns. "Multiple Flutter engines" requires that an engine's detach waits for the release of maps of that engine that Dart disposed before.

## Impact

- Native core: `MapTexture::Dispose()`, `map_texture_dispose`, `map_texture::DisposeEngineMaps` in `packages/flutter_mapigrade/src/core/`.
- Platform targets: a way to run a task on the platform thread from another thread. Android has none today; Darwin already uses `dispatch_async` and `RunOnMainSync`.
- Tests: native tests in `packages/flutter_mapigrade/test/native/` and the thread-count integration tests in `packages/test_harness/integration_test/` (`map_texture_test.dart`, `map_layer_test.dart`, `engines_test.dart`).
- Dart API: no change. `MapTextureController.dispose()` keeps its contract.
- Out of scope: `ReleaseReader()` on Android activity stop also waits on the main thread for a map-thread task. That wait doesn't include `Teardown()`, and this change doesn't alter it.
