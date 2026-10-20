## Why

The plugin keeps one texture registry for the process: the registry of the Flutter engine that registered the plugin last. Every map registers its Flutter textures with that registry. When a second engine registers the plugin, maps that the first engine creates after that register their textures with the wrong engine, and the first engine most likely shows no map. We haven't tested this.

A second engine is common on Android. Plugins such as `firebase_messaging`, `workmanager`, `android_alarm_manager_plus` and `flutter_local_notifications` run Dart callbacks in a background engine, and a new `FlutterEngine` registers every plugin of the app by default. An app with push notifications therefore loses its maps after a message arrives in the background: maps that exist keep working, but a map created after the message, for example on another screen or when the layer is rebuilt, is blank. On iOS and macOS a second engine is less common, but add-to-app hosts, `FlutterEngineGroup` and some background task plugins create one.

## What Changes

- The plugin keeps one texture registry for each engine that registers it, and gives each engine a token that identifies the registry.
- Dart asks its engine for the token once per isolate, through a method channel that the plugin registers with each engine, and passes the token when it creates a map. The map registers its textures with that engine's registry. Each platform uses only public Flutter API; we rejected Flutter's private `+[FlutterEngine engineForIdentifier:]` on iOS and macOS.
- Creating a map in Dart becomes asynchronous, because the first creation in an isolate waits for the token. `MapigradeLayer` creates its map when the token arrives, and the public API doesn't change.
- When an engine detaches the plugin (Android, and iOS through `detachFromEngineForRegistrar:`), the plugin removes that engine's registry and releases the maps that Dart in that engine created and didn't dispose. Maps of other engines are unaffected. macOS has no detach callback, so on macOS the maps that a destroyed engine didn't dispose stay until the process ends.
- An integration test starts a second engine on each platform and checks that the first engine's new maps display, and on Android and iOS that the second engine's maps are released when it is destroyed.
- `docs/limitations.md` and the plugin README no longer list one Flutter engine per process as a limitation; the macOS detach behavior is listed instead.
- Not in this change: pausing rendering per engine. On Android, a stopped Flutter activity still pauses every map in the process, and memory pressure still reaches every map. This matters only for apps with two Flutter activities, each with its own engine.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: a new requirement that each map registers its textures with the Flutter engine whose Dart code created it, that maps of one engine keep working when other engines register or detach the plugin, and that maps an engine created are released when that engine detaches.

## Impact

- Native core (`packages/flutter_mapigrade/src/core/`): `map_texture_create` takes the engine token; `CreatePlatformRenderTarget` receives it; a new function releases the maps of one engine.
- iOS and macOS (`darwin/.../MapigradePlugin.mm`, `MapTextureMetal.mm`, `MapTextureRegistry.h`): a plugin instance and method channel per registrar, a registry table instead of `gTextureRegistry`, and detach on iOS.
- Android (`MapigradePlugin.kt`, `map_texture_android.cpp`): a token per plugin instance, a method channel per engine, a registry table instead of the global `texture_registry`, and detach.
- Dart (`lib/src/texture/map_texture_controller.dart`, `lib/src/layer/map_texture_layer.dart`, bindings) and their unit tests; the test harness and its integration tests, which call `MapTextureController.create` directly; native code in the test harness to start and destroy a second engine.
- Documentation: `docs/limitations.md`, `docs/architecture.md`, and `packages/flutter_mapigrade/README.md`.
