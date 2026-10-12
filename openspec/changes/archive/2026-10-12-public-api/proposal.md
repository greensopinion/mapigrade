## Why

The package's main library exports every top-level declaration of four source files. No one decided that each of them is API: the exports include a test hook (`processThreadCount`), and the public layer has two parameters that exist for tests and measurements (`onController` and `copyFree`). Two exported names, `MapCamera` and `MapEvent`, are also exported by `flutter_map`, so an application that uses the layer with `flutter_map` must hide or qualify names. Exported classes have no class modifiers, so applications can extend or implement them, and adding a member would break those applications. The package is not published yet, so we can make these changes now without breaking any application.

## What Changes

- **BREAKING** The main library `package:flutter_mapigrade/flutter_mapigrade.dart` serves applications that use `flutter_map`. It exports, through `show` lists only: `MapigradeLayer`, `LayerAlignment`, `LayerException`, `LayerLoadException`, `LayerRenderException` and `LayerCreateException`.
- **BREAKING** `MapLibreTextureLayer` is renamed `MapigradeLayer`. Its parameters are `styleUrl`, `styleJson`, `alignment`, `onStyleLoaded` and `onError`. `CameraAlignment` is renamed `LayerAlignment`, with the same values.
- **BREAKING** `onController` and `copyFree` are removed from the public layer. `MapigradeLayer` builds an internal widget, `MapTextureLayer`, which has every parameter of the public layer and these two. Future parameters for tests and measurements go on `MapTextureLayer` only.
- The layer reports a failure by calling `onError` with a `LayerException`: `LayerLoadException` when the style or a resource it needs fails to load, `LayerRenderException` when rendering fails, and `LayerCreateException` when the map can't be created. Today a failure to create the map is thrown during the build. `LayerException` is an `abstract final` class, so that a new subclass is a compatible change. When `onError` is null, the layer reports the failure through `FlutterError.reportError` instead of discarding it.
- The layer calls `onStyleLoaded` each time a style has loaded, including after the application changes `styleUrl` or `styleJson` on a layer that exists.
- **BREAKING** `MapTextureController`, `MapTextureView`, `MapCamera`, `FrameCamera`, `MapEvent` and its subclasses, `MapTextureStats`, `MapTextureDisposedException`, `MapTextureException` and `processThreadCount` are no longer exported.
- **BREAKING** `lib/testing.dart` is removed. A new internal library, `lib/src/testing.dart`, exports the internal types and the test hooks. The test harness imports it, and disables the lint `implementation_imports` for that reason. It is not API, and the naming rule below doesn't apply to it.
- Exported types are `final` classes. The exception classes define `==` and `hashCode`.
- Naming rule for exported names: descriptive names without a package prefix, with types that belong to the layer named with `Layer`. Exported names don't start with a name that `flutter_map` uses for its own types (`Map`, `Camera`, `Tile`, `Marker`, `Polyline`, `Polygon`), and don't equal a name exported by `flutter_map`, `latlong2` or Flutter. Internal names may equal names in those packages. A test fails when an exported name breaks the rule or isn't listed in a `show` list.
- The FFI bindings declare their native asset with `@DefaultAsset`, and `hook/build.dart` uses that id, so that the asset id no longer depends on the path of `bindings.dart`.
- Each exported type is in its own file, named after the type. The note in `lib/src/layer/README.md` becomes a library doc comment, and the file is removed.
- The plugin depends on `flutter_map` with the constraint `^8.3.2`, not the exact version `8.3.2`.
- The plugin's lints add `public_member_api_docs`, and its analyzer settings add `strict-casts`, `strict-inference` and `strict-raw-types`.
- A new example, `packages/flutter_mapigrade/example/`, shows a `FlutterMap` with `MapigradeLayer` and a marker, imports only the main library, and runs on Android, iOS and macOS. It becomes a member of the pub workspace.
- The plugin gets a `README.md` that describes its use, supported platforms and limitations, a `CHANGELOG.md`, and a library doc comment with a usage example.
- `MapigradeLayer.maximumCacheSizeBytes`, a static property that applies to the whole process, is the public name for the maximum size of MapLibre's ambient cache. The change `tile-cache-maximum-size` adds it, and its proposal is updated to use this name before it is implemented.

This change starts after `repo-layout`, so that the test harness is in `packages/test_harness/` when it changes to the internal library.

## Capabilities

### New Capabilities

- `package-api`: what the main library exports, the naming rule for exported names and its test, that applications can't extend or implement exported types, that the internal library for tests isn't API, and that the example uses only the main library.

### Modified Capabilities

- `map-layer`: the requirement "Base layer of a flutter_map map" adds a scenario for changing the style of a layer that exists, and the report that a style has loaded. A new requirement, "Failure reporting", covers `onError`, the three kinds of failure, and the report through `FlutterError` when the application gives no handler.

## Impact

- Dart API: every name the main library exports today is renamed, removed or made internal. No application depends on the package yet.
- Code: `packages/flutter_mapigrade/lib/` (the main library, `lib/src/layer/`, `lib/src/testing.dart`, `bindings.dart`), `hook/build.dart`, `pubspec.yaml`, `analysis_options.yaml`, and new tests in `test/`.
- Test harness: `packages/test_harness/` changes its imports to `package:flutter_mapigrade/src/testing.dart`, uses `MapTextureLayer` where it needs the controller or `copyFree`, and uses the new names.
- New example: `packages/flutter_mapigrade/example/` with Android, iOS and macOS projects, and an entry in the root `pubspec.yaml`.
- Documents: the plugin's `README.md` and `CHANGELOG.md`.
- In-flight change: `tile-cache-maximum-size` uses `MapigradeLayer.maximumCacheSizeBytes` instead of `MapTextureController.setMaximumCacheSize`.
