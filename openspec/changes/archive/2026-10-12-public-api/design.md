## Context

See proposal.md for motivation and scope, and specs/package-api/spec.md and specs/map-layer/spec.md for the requirements. The in-flight change `tile-cache-maximum-size` uses decisions up to D64; decisions here are numbered from D65. This change starts after `repo-layout`, so paths below use `packages/test_harness/` for the app that is `example/` today.

Current state, as checked in this repository on 2026-10-12:

- `lib/flutter_mapigrade.dart` exports four files without `show` lists: `src/layer/camera_alignment.dart`, `src/layer/map_libre_texture_layer.dart`, `src/texture/map_texture_controller.dart` and `src/texture/map_texture_view.dart`. `lib/testing.dart` exports `src/layer/alignment_error.dart`, `ViewCamera` and `viewCameraOf` from `src/layer/camera_projection.dart`, and `src/texture/testing.dart`.
- `MapLibreTextureLayer` creates its `MapTextureController` in `didChangeDependencies`, once the window's metrics have arrived. `MapTextureController.create` throws `MapTextureException` when the native map can't be created. The layer doesn't listen to `controller.events`; the test harness reads them through `onController`.
- `hook/build.dart` declares the Android code asset with the name `src/texture/bindings.dart`, which equals the default asset id of the `@Native` declarations in that file. On macOS and iOS no asset is declared, and the symbols resolve from the process.
- `test/texture_boundary_test.dart` enforces design D9 (only `lib/src/layer/` imports `flutter_map`).

## Goals / Non-Goals

**Goals:**
- Make every exported name a deliberate choice that a test checks.
- Keep every parameter and hook that tests and measurements need, without exporting it.

**Non-Goals:**
- No change to native code, to rendering, or to the alignment behavior.
- No public controller, stream of events, or API for style layers or sources. Applications change the style by rebuilding the layer.
- The maximum cache size is implemented by `tile-cache-maximum-size`, not here.

## Decisions

### D65. The main library exports with `show` lists, one file per exported type

`lib/flutter_mapigrade.dart` becomes:

```dart
export 'src/layer/mapigrade_layer.dart' show MapigradeLayer;
export 'src/layer/layer_alignment.dart' show LayerAlignment;
export 'src/layer/layer_exception.dart'
    show LayerException, LayerLoadException, LayerRenderException, LayerCreateException;
```

Files in `lib/src/layer/`:

| File | Contents |
|---|---|
| `mapigrade_layer.dart` | `MapigradeLayer` (D66) |
| `map_texture_layer.dart` | `MapTextureLayer` and its `State`, from today's `map_libre_texture_layer.dart` |
| `layer_alignment.dart` | `LayerAlignment`, from today's `camera_alignment.dart` |
| `layer_exception.dart` | `LayerException` and its three subclasses (D68) |

The exception classes share one file because a subclass of an `abstract final` class must be in the same library. Every other exported type is in its own file, named after the type. `camera_prediction.dart`, `camera_projection.dart`, `alignment_error.dart` and `lib/src/texture/` keep their names.

The note in `lib/src/layer/README.md` becomes a library doc comment in `map_texture_layer.dart`, and the README is removed. `test/texture_boundary_test.dart` keeps enforcing D9.

Alternative: keep `export` without `show` and rely on review. Rejected: that is how `processThreadCount` became API.

### D66. `MapigradeLayer` builds the internal `MapTextureLayer`

```dart
final class MapigradeLayer extends StatelessWidget {
  const MapigradeLayer({super.key, this.styleUrl, this.styleJson,
      this.alignment = const LayerAlignment.prediction(),
      this.onStyleLoaded, this.onError});
  // build returns MapTextureLayer(... the same values ..., copyFree: true)
}

class MapTextureLayer extends StatefulWidget {
  // every parameter of MapigradeLayer, and:
  final bool copyFree;
  final void Function(MapTextureController controller)? onController;
  final MapTextureController Function({required double pixelRatio, required bool copyFree})?
      createController;   // replaces MapTextureController.create in tests (D67)
}
```

The internal widget is named `MapTextureLayer`, like `MapTextureController` and `MapTextureView`, not `TextureLayer`: Flutter's `rendering.dart`, which `widgets.dart` and `material.dart` export, declares a `TextureLayer`, and every file of the test harness that imports Flutter and `src/testing.dart` would need to hide one of them. We changed the name during implementation, on 2026-10-12.

`MapTextureLayer` is the only widget with state. The application's key is on `MapigradeLayer`. Because `MapigradeLayer` always builds a `MapTextureLayer` at the same position, the `State`, and so the map, survives rebuilds of `MapigradeLayer`, including a style change. The assert that exactly one of `styleUrl` and `styleJson` is given moves to `MapigradeLayer` and also stays on `MapTextureLayer`, which the test harness builds directly.

`tile-cache-maximum-size` adds the static property `maximumCacheSizeBytes` to `MapigradeLayer`.

Alternatives:
- A global hook in `lib/src/testing.dart` that the layer calls with each controller it creates. Rejected: global mutable state shared by every test, and `copyFree` would need a second global.
- Reading the controller from the `State` through a `GlobalKey`. Rejected: every test needs a key, and it doesn't solve `copyFree`.

### D67. The layer turns map events into callbacks

`MapTextureLayer`'s `State` listens to `controller.events` from the moment it creates the controller, and cancels the subscription in `dispose`:

| Map event | Layer reports |
|---|---|
| `StyleLoaded` | calls `onStyleLoaded` |
| `LoadingFailed(message)` | reports `LayerLoadException(message)` |
| `RenderError(message)` | reports `LayerRenderException(message)` |
| `MapIdle` | nothing; the test harness reads it from the controller |

A failure is reported through one method: if `onError` is not null it is called; otherwise the layer calls

```dart
FlutterError.reportError(FlutterErrorDetails(
  exception: exception,
  library: 'flutter_mapigrade',
  context: ErrorDescription('while displaying the MapigradeLayer map'),
));
```

The callbacks are read from the current widget at the time of the event, so a rebuild with a new callback takes effect for the next event.

MapLibre retries a request that failed to connect, after 1 s, then 2 s more, with backoff, for as long as the request fails, and sends a `LoadingFailed` for each failed attempt, with the same message (measured on macOS on 2026-10-12: events at 11 ms, 1,023 ms and 3,031 ms for one unreachable style URL). The layer therefore reports a `LoadingFailed` only if no load failure with the same message has been reported since the layer last loaded a style. A failure with a different message, such as the device going offline or a sprite that fails to load, is still reported. We decided this during implementation, on 2026-10-12, instead of reporting each event as above.

Creating the map: `didChangeDependencies` calls `createController` (or `MapTextureController.create` when it is null) inside a `try`. On `MapTextureException`, the `State` records that creation failed, reports `LayerCreateException(message)`, and doesn't try again while it is in the tree, so a failure is reported once and not on every dependency change. While creation has failed, `build` returns `SizedBox.fromSize(size: viewport)`, which draws nothing, and `flutter_map` still draws the layers after it.

The `createController` parameter exists so that a widget test can make creation fail. No platform offers a way to make the native map fail to be created.

Alternative: throw the exception from the `State`. Rejected: the events arrive from the map thread after the application's code has returned, so no frame of application code is on the stack to catch the exception (see the discussion recorded in the proposal).

### D68. Exception hierarchy

```dart
abstract final class LayerException implements Exception {
  const LayerException(this.message);
  final String message;
  // == and hashCode compare runtimeType and message; toString is '<TypeName>: <message>'
}
final class LayerLoadException extends LayerException { ... }
final class LayerRenderException extends LayerException { ... }
final class LayerCreateException extends LayerException { ... }
```

`abstract final`, not `sealed`: with `sealed`, applications could switch over the subclasses without a default case, and a new subclass would break that code. `abstract final` still prevents subclasses outside the package. The classes implement `Exception`, not extend `Error`, because they are failures at run time that an application is expected to handle, not errors in the program. Flutter passes `NetworkImageLoadException` to listeners in the same way, without throwing it at the application.

### D69. One internal library for tests

`lib/src/texture/testing.dart` is renamed `lib/src/texture/test_hooks.dart`, so that only one file is named `testing.dart`. `processThreadCount` moves into it from `map_texture_controller.dart`.

`lib/src/testing.dart` exports, with `show` lists: `MapTextureController`, `MapTextureView`, `MapCamera`, `FrameCamera`, `MapEvent` and its subclasses, `MapTextureStats`, `MapTextureDisposedException`, `MapTextureException`, `MapTextureLayer`, `AlignmentError`, `alignmentError`, `ViewCamera`, `viewCameraOf`, and every function in `test_hooks.dart`. `lib/testing.dart` is removed.

The test harness imports `package:flutter_mapigrade/src/testing.dart` and `package:flutter_mapigrade/flutter_mapigrade.dart`, and its `analysis_options.yaml` disables `implementation_imports`. Files that also import `flutter_map` keep `hide MapCamera` or use a prefix. The plugin's own tests in `test/` may import any file under `lib/src/`.

### D70. API tests

Two tests in `packages/flutter_mapigrade/test/`:

1. `api_test.dart` uses `package:analyzer` (a new dev dependency) to resolve the package in an `AnalysisContextCollection`. It checks:
   - the export namespace of `lib/flutter_mapigrade.dart` equals the six names of the spec;
   - every export directive in that file has a `show` combinator;
   - no exported name other than `MapigradeLayer` starts with `Map`, `Camera`, `Tile`, `Marker`, `Polyline` or `Polygon`;
   - no exported name is in the export namespace of `package:flutter_map/flutter_map.dart`, `package:latlong2/latlong.dart`, `package:flutter/widgets.dart` or `package:flutter/material.dart`;
   - `lib/` contains no Dart file outside `lib/src/` other than `flutter_mapigrade.dart`.

   A failure message names the name and the rule it breaks. The expected set of names is written in the test, so that adding API requires editing the test.

2. `api_usage_test.dart` imports the main library, `flutter_map`, `latlong2` and `material.dart` without prefixes or `hide`, and refers to each exported name. An ambiguous import fails compilation, which fails the test. It also declares no subclass, because a class that extends an exported type wouldn't compile; the closed types are checked by inspection of the class modifiers in `api_test.dart` (each exported class is `final`, or `abstract final` for `LayerException`).

Alternative: only the usage test. Rejected: it catches clashes at the resolved versions, but not a missing `show` list or a name that breaks the naming rule without clashing yet.

### D71. Native asset id independent of the file path

`bindings.dart` gets the library annotation `@DefaultAsset('package:flutter_mapigrade/native')`, and `hook/build.dart` declares the Android asset with `name: 'native'`, which gives that id. The asset id no longer changes when `bindings.dart` moves. On macOS and iOS no asset is declared, as today, and the symbols resolve from the process as they do now.

### D72. Dependency constraint, lints and analyzer settings

- `flutter_map: ^8.3.2` in the plugin's `pubspec.yaml`. The test harness and the example keep `8.3.2`, so the workspace resolves to that version.
- The plugin's `analysis_options.yaml`, which includes the root file from `repo-layout`, adds the lint `public_member_api_docs` and the analyzer language settings `strict-casts`, `strict-inference` and `strict-raw-types`. The findings in `lib/` and `test/` are fixed in this change.

### D73. Example app

`packages/flutter_mapigrade/example/` is created with `flutter create --template=app --platforms=android,ios,macos --org com.greensopinion`, as the Dart package `flutter_mapigrade_example`, and added to the workspace members. Its platform settings match the plugin's supported platforms, using the test harness's settings as the reference: iOS deployment target 15.5, macOS 14.3 with the network client entitlement, Android `minSdk` 29 and the arm64 ABI only.

`lib/main.dart` shows a `FlutterMap` with `MapigradeLayer` (style: OpenFreeMap Liberty, the test harness's default) and a `MarkerLayer` with one marker, and shows the message of a `LayerException` in a `SnackBar`. It is the usage example that pub shows, so it uses no other feature.

On 2026-10-12 we ran the example on macOS, on the iPhone 16 Pro simulator and on the Android emulator (Pixel 10a, API 37), and on each the map appeared below the marker, with the marker at its coordinate. We decided that the simulator and the emulator are enough to verify the example: this change doesn't change native code or rendering, and the example's platform-specific parts are its project settings, which the simulator and emulator builds use. The device slices of the native libraries and code signing (the example uses the test harness's development team) aren't checked by these runs; the test harness runs on the iPhone with the same slice and team.

### D74. Documentation

- `README.md`: what the package does, a usage snippet, supported platforms, the alignment option, failure handling, and the main limitations, with a link to `docs/limitations.md` in the repository.
- `CHANGELOG.md`: an entry for 0.0.1 that lists the API.
- A library doc comment on `lib/flutter_mapigrade.dart` with the same usage snippet.
- Doc comments on every exported member, as `public_member_api_docs` requires.

## Risks / Trade-offs

- [`package:analyzer` may conflict with versions that `flutter_test` pins, such as `meta` or `collection`] → Choose an `analyzer` version that resolves with the workspace. If none does, move the check to a script in `packages/test_harness/tool/` that runs with `dart run`, and run it with the tests.
- [`public_member_api_docs` may also report public members in `lib/src/`] → Document them; the internal types are also what the test harness reads. If the number of findings is out of proportion, disable the lint for `lib/src/` files that aren't exported, and record that in this design. On 2026-10-12 the lint reported 109 members: 65 in `bindings.dart`, which mirror the constants and struct fields of `src/core/map_texture_api.h` and are documented there, and 44 in other files under `lib/src/`. We disabled the lint in `bindings.dart` only, and documented the other 44.
- [`FlutterError.reportError` in debug mode prints the error, and a test that expects no reported errors fails when a style URL can't be reached] → Tests that use unreachable URLs set `onError`.
- [A style change before the previous style has loaded may produce one `StyleLoaded` event, not two] → The spec requires a report each time a style has loaded, not one per change; the integration test changes the style after the first one has loaded.
- [`tile-cache-maximum-size` reports a failure to apply the cache size as `RenderError`, which this change reports as `LayerRenderException`] → Revisit when that change's proposal is updated to `MapigradeLayer.maximumCacheSizeBytes`; it may need its own subclass, which D68 allows.

## Migration Plan

No application depends on the package. The test harness changes in this change: imports (D69), `MapLibreTextureLayer` to `MapTextureLayer` where it uses `onController` or `copyFree` and to `MapigradeLayer` elsewhere, `CameraAlignment` to `LayerAlignment`. The proposal of `tile-cache-maximum-size` is updated to the new name before that change is implemented.
