## Context

See proposal.md, "Why", for the failure and how common it is.

Dart calls the native code through `@Native` FFI bindings, not through a platform channel, so a native call carries no information about the engine whose Dart code made it.

- iOS and macOS: `+[MapigradePlugin registerWithRegistrar:]` stores `registrar.textures` in the global `gTextureRegistry`. `CreatePlatformRenderTarget` in `MapTextureMetal.mm` reads it through `MLTTextureRegistry()` and registers the four slot textures with it on the main thread. The plugin has no instance and registers no channel.
- Android: each engine creates its own `MapigradePlugin` instance. `onAttachedToEngine` calls `nativeInit(binding.textureRegistry, …)`, which replaces the global reference `texture_registry` in `map_texture_android.cpp`. `CreatePlatformRenderTarget` passes it to the `MapSurface` constructor. `onDetachedFromEngine` leaves the reference in place. Memory callbacks and activity callbacks belong to the plugin instance.
- The core (`src/core/map_texture_api.cpp`) keeps every map in `Registry()`, keyed by handle. `map_texture_create` creates a `MapTexture`, whose constructor calls `CreatePlatformRenderTarget(owner, copy_free)`.
- Flutter offers `PlatformDispatcher.instance.engineId` in Dart. Android has the public `FlutterEngine.engineForId(long)`. Flutter 3.47.5 on iOS and macOS has `+[FlutterEngine engineForIdentifier:]` in its binaries but not in its public headers.

## Goals / Non-Goals

**Goals:**
- Each map registers its textures with the engine whose Dart code created it, on every platform, through one Dart code path.
- Only public Flutter API.
- An engine that detaches doesn't affect the maps of other engines, and on Android and iOS its own maps are released.

**Non-Goals:**
- Pausing rendering or reducing memory use per engine. `SetAllPaused`, `SetReadersReleased` and `ReduceAllMemoryUse` stay process-wide.
- Releasing the maps of a destroyed engine on macOS.
- Changing the public API of `flutter_mapigrade`.

## Decisions

### D153. A token for each registration of the plugin

When an engine registers the plugin, the native code assigns a token, a positive `int64_t` that is never reused in the process, and stores the engine's texture registry in a table keyed by the token. The table replaces `gTextureRegistry` and `texture_registry`. A mutex protects it, because Dart's UI thread is the main thread only when Flutter merges the platform and UI threads.

Alternatives:
- Dart passes `PlatformDispatcher.instance.engineId`, and native code looks the engine up. Android can do this with `FlutterEngine.engineForId`, but iOS and macOS would need the private `engineForIdentifier:`, which can change in any Flutter release. We use the token on Android as well, so that the native API and the Dart code are the same on every platform.

### D154. Dart asks for the token over a method channel

The plugin registers a method channel `flutter_mapigrade` with each engine's binary messenger: on iOS and macOS with `[registrar addMethodCallDelegate:instance channel:]`, on Android with `binding.binaryMessenger`. The handler answers the method `engineToken` with the token of the registration it belongs to. Because a channel belongs to one engine, Dart receives its own engine's token.

Dart asks at the first map creation in an isolate and keeps the token it receives. Creations that start while the request is pending wait for the same request. A failure, such as a `MissingPluginException` when the plugin isn't registered with the engine, becomes a `MapTextureException`, so `MapigradeLayer` reports a `LayerCreateException`. Dart doesn't keep a failed request, so the next creation asks again.

Alternatives:
- The native code sends the token to Dart when the engine registers the plugin, and Flutter buffers the message until Dart sets a handler. Plugins are often registered before the engine's root isolate runs, and a message sent then may be dropped. A request from Dart reaches a handler that exists from registration on.

### D155. Creating a map becomes asynchronous

`MapTextureController.create` returns `Future<MapTextureController>`. It awaits the token and then calls `map_texture_create` as today. After the first creation in an isolate the token is already available, so creation waits only for a microtask.

`MapTextureLayer` starts the creation in `didChangeDependencies`, as today, with the pixel ratio read at that time, and keeps a flag so that it starts only one creation. When the future completes, the layer sets up its subscriptions and loads the style; if the layer was disposed in the meantime, it disposes the controller instead. Until then it builds as it does before creation today. `MapTextureControllerFactory` returns a future. `MapTextureView` takes a controller, so it doesn't change.

Alternatives:
- Keep `create` synchronous and add a separate call that obtains the token first. Every caller would have to make that call, and the layer needs an asynchronous step either way.

### D156. `map_texture_create` takes the engine token

`map_texture_create` gets a first parameter `int64_t engine`. `MapTexture` stores it and passes it to `CreatePlatformRenderTarget(owner, copy_free, engine)`, which looks the registry up in the table. For an unknown token, for example one whose engine has detached the plugin, or on macOS a registry that no longer exists (D158), creation fails with `MAP_TEXTURE_ERROR_CREATE_FAILED` and the error "the Flutter engine of this isolate has detached flutter_mapigrade".

### D157. Detach releases the engine's maps

A new core function `DisposeEngineMaps(engine)` removes from `Registry()` every map with that token and disposes it as `map_texture_dispose` does. The platform code calls it when the engine detaches the plugin, after it removes the token's registry from the table:

- Android: `onDetachedFromEngine` calls a new `nativeDetach(token)`.
- iOS: `registerWithRegistrar:` creates a plugin instance and publishes it with `[registrar publish:instance]`, so that Flutter calls `detachFromEngineForRegistrar:` on it.

On iOS, Flutter calls `detachFromEngineForRegistrar:` when the engine is deallocated, after the engine's isolate has ended. On Android, `FlutterEngine.destroy()` detaches the plugins before it shuts down the isolate, but both run on the main thread, which is also Dart's UI thread unless the merged platform and UI thread is turned off, so no Dart code runs between them. Where Dart code does call with the handle of a released map, the call returns `MAP_TEXTURE_ERROR_DISPOSED` as for any disposed map.

### D158. macOS keeps a weak reference to the registry

macOS has no detach callback, so the table can't learn that an engine was destroyed. On macOS the table holds the registry with a weak reference, so that the table doesn't keep a destroyed engine's registry alive. The render targets of the maps that the destroyed engine didn't dispose hold the registry strongly, so while such a map exists the weak reference doesn't become nil. Those maps keep their threads until the process ends.

Only Dart code in an engine has that engine's token, and a destroyed engine runs no Dart code, so no map is created with the token of a destroyed engine. The failure of D156 for a registry that no longer exists guards a case that we don't expect to occur, and no test covers it on macOS.

On iOS the table holds the registry strongly. `registrar.textures` returns a `FlutterTextureRegistryRelay`, which doesn't keep the engine alive, so the engine can be deallocated and detach the plugin (D157). Task 5.1 verifies this with the scenario "Maps of a destroyed engine are released".

### D159. The test harness starts a second engine

The test harness gets a test channel, `mapigrade_test/engines`, with the methods `start` and `destroy`, implemented in its native code on each platform:

- Android: `FlutterEngine(context)`, which registers every plugin, running a Dart entry point `secondEngineMain` of the test harness through `dartExecutor.executeDartEntrypoint`; `destroy()`.
- iOS: `[[FlutterEngine alloc] initWithName:]`, `runWithEntrypoint:@"secondEngineMain"`, `[GeneratedPluginRegistrant registerWithRegistry:]`; `destroyContext`.
- macOS: `[[FlutterEngine alloc] initWithName:project:allowHeadlessExecution:YES]`, `runWithEntrypoint:`, `RegisterGeneratedPlugins(registry:)`; `shutDownEngine`.

`secondEngineMain` optionally creates a map without disposing it, and reports to the first engine over the test channel when it has done so. The integration tests cover the scenarios of the spec requirement "Multiple Flutter engines".

## Risks / Trade-offs

- [The first map in an isolate waits for a channel round trip.] → The wait is shorter than the style load that follows it, and `MapigradeLayer` already builds an empty placeholder until the map exists.
- [A headless second engine may not be able to create a map on Android, because `map_texture_create` must run on the main thread.] → Flutter runs the UI thread of every engine on the main thread when it merges the platform and UI threads, which is the default. If the test shows otherwise, the release scenario is tested on iOS only, and `docs/limitations.md` records the result.
- [On macOS, the maps of a destroyed engine keep their threads and memory.] → `docs/limitations.md` lists it. Several engines on macOS are rare.
- [An app that registers the plugin with an engine but runs Dart in an isolate without that engine's binary messenger, for example `Isolate.spawn`, can't create a map.] → Such an isolate can't display a `Texture` either. Creation fails with a `MapTextureException`.

## Migration Plan

`MapTextureController` and `map_texture_create` are internal, so applications don't change. The test harness, its integration tests and the plugin's unit tests move to the asynchronous `create`.
