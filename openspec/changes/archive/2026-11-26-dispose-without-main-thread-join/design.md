## Context

See proposal.md for the ANR. The release of a map has three parts, and today `MapTexture::Dispose()` runs all three on the calling thread:

1. Clear `callback_` under `callback_mutex_`. After this, `Emit` and `EmitQueryResult` send no event to Dart, so Dart can close its `NativeCallable` when dispose returns.
2. Queue `kDispose`, signal the map thread and join it. The map thread finishes its current `RunOnce()` iteration and runs `Teardown()`, which waits up to 30 s each for `mln_map_release` and `mln_runtime_release`.
3. Call `target_->Unregister()`. It has to run after the map thread has stopped, because it closes images and surfaces that the map thread used. On Android it calls `MapSurface.release`, which releases the `SurfaceProducer` and has to run on the main thread. On Darwin it unregisters the textures through `RunOnMainSync`.

The callers are `map_texture_dispose` (Dart, on the platform thread) and `DisposeEngineMaps` (engine detach, on the main thread). On Android and iOS the platform thread is the main thread.

## Goals / Non-Goals

**Goals:**

- Neither `map_texture_dispose` nor `MapTexture::Dispose()` waits for the map thread.
- No thread waits on the platform thread for a task that needs the platform thread.
- Tests can wait for every pending release to finish.

**Non-Goals:**

- Make the engine detach return without waiting for the map thread. The detach keeps waiting, because the texture registrations have to be released while the engine is attached (D4). Engines are destroyed rarely compared with map disposal.
- Change `ReleaseReader()` on Android activity stop, which waits on the main thread for a map-thread task but not for `Teardown()`.
- Shorten `Teardown()`.

## Decisions

### D1. Dispose returns after it queues the stop

`MapTexture::Dispose()` clears `callback_`, queues `kDispose`, signals the map thread and hands the map's `shared_ptr` to the release queue (D2). It doesn't join. `map_texture_dispose` already removes the handle from the registry before it calls `Dispose()`, so calls after dispose keep failing with `MAP_TEXTURE_ERROR_DISPOSED`.

Alternative considered: keep the join but shorten `Teardown()` (lower the 30 s waits). This doesn't remove the wait for the current render, and the waits exist so that no completion runs into a freed object.

### D2. One release thread joins the map threads

A process-wide release queue in the core holds the maps whose map thread is stopping. A release thread takes each map, joins its map thread, marks the map stopped and posts the map's unregistration to the platform thread (D3). The release thread starts when a map enters the empty queue and exits when the queue is empty, so it adds no thread while no release is pending, and the thread-count tests stay valid.

The release thread joins maps in queue order. The maps stop in parallel, because each `Dispose()` has queued `kDispose` already, so the order delays only the unregistration of a later map behind the stop of an earlier one.

Alternatives considered:

- Detach the map thread and let `Run()` post the unregistration when it ends. Nothing could then wait for a release, which D4 and the test hook need.
- One release thread per disposal. This works, but it starts a thread for every dispose, and the queue gives D4 and D5 one place to wait.

### D3. Unregistration runs on the platform thread, once

A new platform function `PostToPlatformThread(std::function<void()>)` runs a task on the platform thread later:

- Android: an `ALooper` of the main thread, acquired in `nativeInit` (which `MapigradePlugin` calls on the main thread), with an `eventfd` registered through `ALooper_addFd`. The fd callback runs the queued tasks. We chose this over a Kotlin `Handler.post` because it needs no Java class with a native `Runnable`.
- Darwin: `dispatch_async(dispatch_get_main_queue(), …)`.

The posted task calls `MapTexture::UnregisterOnce()`, which calls `target_->Unregister()` only if no earlier call has, under a mutex. D4 and D5 call it too, so it has to be idempotent.

### D4. Engine detach finishes the releases of its engine

`DisposeEngineMaps` runs on the main thread. It disposes the engine's live maps as in D1, then waits until the release thread has stopped every map of that engine in the release queue, including maps that Dart disposed before, and then calls `UnregisterOnce()` for each of them on the main thread. The waiting thread never waits for a platform-thread task, so a posted unregistration that hasn't run yet can't deadlock it; when it runs later, it does nothing.

This keeps today's order on detach: on Android, `MapSurface.release` releases the `SurfaceProducer` before `onDetachedFromEngine` returns, while the engine's `FlutterJNI` is still attached. We haven't checked whether releasing a `SurfaceProducer` after the engine detached throws, and D4 avoids depending on it.

### D5. A test hook waits for every pending release

`map_texture_wait_for_releases_for_testing(int64_t timeout_ms)` does what D4 does, for every map in the release queue, and returns whether the releases finished within the timeout. Dart calls it on the platform thread, so it runs the unregistrations inline, as D4 does. The thread-count integration tests call it before they count threads after disposal. Native tests on macOS call it too, because nothing runs the main dispatch queue in the native test runner.

## Risks / Trade-offs

- [A map's render resources and runtime live up to 60 s after dispose, as today on the map thread, but now while the app continues] → Memory use is bounded by the number of maps disposed within that time. The "Dispose releases resources" scenario checks it after the releases finish.
- [The process exits with releases pending] → The release thread and the map threads are still joinable at exit, as the map thread is today while `Dispose()` waits. The OS frees the resources.
- [A Flutter texture stays registered after the widget that showed it is gone] → Nothing displays it, and the registration is released after the map thread stops.
- [Engine detach still waits on the main thread] → Accepted for now (Non-Goals). The wait includes `Teardown()` only for maps of the detaching engine.
- [A test that checks threads or resources right after dispose without the hook becomes flaky] → Tasks 4.x update every such test to call the hook.
