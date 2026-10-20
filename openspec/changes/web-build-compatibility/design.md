## Context

See proposal.md, "Why", for the failure.

Four files under `lib/src/texture/` import `dart:ffi`:

- `bindings.dart`: the `@Native` bindings. It also imports `package:ffi`.
- `map_texture_controller.dart` (673 lines): the class `MapTextureController`, and the types that the layer code uses without FFI: `MapCamera`, `FrameCamera`, `MapEvent` and its subclasses, `MapTextureStats`, `MapTextureException`, `MapTextureDisposedException` and `HeaderRule`. It also imports `package:ffi`.
- `native_library.dart`: `nativeLibraryAvailable`, which also imports `dart:io` for `Platform`. It returns false on platforms other than Android, iOS and macOS.
- `test_hooks.dart`: reached only through `lib/src/testing.dart`, which isn't API.

The main library reaches `map_texture_controller.dart` through `mapigrade_layer.dart`, `layer_metrics.dart` and `map_texture_layer.dart`, and `native_library.dart` through `mapigrade_layer.dart`. `MapTextureController.create` already throws a `MapTextureException`, "the native library of flutter_mapigrade is not available in this process", without calling native code when `nativeLibraryAvailable` is false. `MapTextureLayer` reports that exception as a `LayerCreateException` (unsupported-architectures change, design D86). `MapTextureController.setMaximumCacheSize` returns early in the same case.

`scripts/consumer_build.sh`, on the branch `consumer-build-ci`, creates an app from the archive that `flutter pub publish` would upload, and builds it for Android, iOS and macOS.

## Goals / Non-Goals

**Goals:**
- One definition of the controller's members, which the FFI implementation and the web code can't drift from.
- On web, the same failure path as an Android device without the native library, with no new code in the layer.
- A check that fails in `flutter test`, before CI, and names the file that brings a web-incompatible import into the main library.

**Non-Goals:**
- Making `lib/src/testing.dart` or the test harness compile for web.
- A warning on web. The Android warning names the device's ABIs; on web the absence of the library is known when the app is built, and `onError` reports the failure.

## Decisions

### D160. `MapTextureController` becomes an interface with platform implementations

`map_texture_controller.dart` keeps the shared types and declares `abstract interface class MapTextureController` with the controller's instance members and their documentation. Its static `create` and `setMaximumCacheSize` keep their current checks of `nativeLibraryAvailable` and then call functions of a conditionally imported platform file. The FFI implementation moves to `map_texture_controller_ffi.dart` as a private class that implements the interface, together with the code that imports `dart:ffi` and `package:ffi`. The web platform file, `map_texture_controller_web.dart`, has the same two functions; they throw a `StateError`, because the checks before them always fail on web.

The layer code, `layer_metrics.dart`, `map_texture_view.dart` and `testing.dart` keep using the name `MapTextureController` and don't change.

Alternatives:
- A conditional export of a second `MapTextureController` class for web, with the same members and bodies that throw. Rejected: the analyzer checks only the default file, so a member added to the FFI class and not to the web class breaks the web build and nothing else.
- Moving the condition up to `MapTextureLayer`, with a web layer that reports the failure. Rejected: `layer_metrics.dart` and `map_texture_view.dart` also take the controller as a type, so the shared types still have to move, and the layer's failure reporting would exist twice.

### D161. The condition is `dart.library.js_interop`, and the default is the FFI file

Each conditional import names the FFI file as its default and the web file under `if (dart.library.js_interop)`, which both dart2js and dart2wasm define. The analyzer, the IDE, `flutter test` and every native build use the default, so they see the code that runs on Android, iOS and macOS. Linux and Windows also use the FFI file, as they do now.

Alternative: the stub as the default with `if (dart.library.ffi)` naming the FFI file. Rejected: the default would be the file that runs only on web, and tools that don't evaluate the condition would analyze the stub.

### D162. `native_library_web.dart` returns false without `dart:io`

`native_library.dart` keeps `nativeLibraryAvailableOverride` and `nativeLibraryAvailable`, and takes the platform result from a conditionally imported file: the current `DynamicLibrary` checks in `native_library_ffi.dart`, and `false` in `native_library_web.dart`. The override still applies on web, so a widget test that runs in a browser can set it. Because `create` checks `nativeLibraryAvailable` before it calls the platform file, a layer on web reports the existing `LayerCreateException`, and `maximumCacheSizeBytes` stores its value and calls nothing (proposal, "What Changes").

### D163. An import-graph test in `flutter test`

A new test, `test/web_imports_test.dart`, uses the analyzer as `test/api_test.dart` does. It starts at the main library and follows the import and export directives of the package's own files. For a directive with configurations it follows the URI of the `dart.library.js_interop` configuration, and otherwise the default URI. It fails when a reached file imports `dart:ffi`, `dart:io`, `dart:isolate`, `dart:mirrors` or `dart:cli`, or `package:ffi`, and it names the file and the import chain from the main library. It doesn't follow imports into other packages; the package's dependencies `flutter_map` and `latlong2` support web.

Alternative: building a web app inside `flutter test`. Rejected: a web build takes about 20 s and needs Flutter's web artifacts; CI runs it instead (D164).

### D164. The existing macOS CI job builds the consumer app for web

`scripts/consumer_build.sh` gets a `web` target, which runs `flutter build web` and then `flutter build web --wasm`. Its consumer app places `MapigradeLayer` behind `isSupported`, as the README shows. The macOS job of `.github/workflows/consumer-build.yml` gets two steps: the `web` target, and the widget test of D165 in Chrome, which GitHub's macOS runners include. The job's triggers also get `packages/flutter_mapigrade/lib/**`. The workflow gets no new job.

D163 checks only the package's own imports. The web build also catches a dependency that stops compiling for web, and compile errors on web that aren't imports, such as an FFI type in the shared types file.

Alternatives:
- Jobs on `ubuntu-latest` and `windows-latest` that also build for Linux and Windows. Rejected: the plugin declares neither platform, so Flutter builds no native plugin code for them; the build hook returns early for every OS except Android; and the Dart code takes the FFI path that `flutter test` on the macOS host already compiles. This change doesn't alter any of that, so the jobs would guard little for their runner time. Linux and Windows are out of scope (proposal, Non-goals).
- No web build in CI, only D163. Rejected: see above.

### D165. One widget test for a process without the native library

`test/unsupported_platform_test.dart` places `MapigradeLayer` with an `onError` handler in a `FlutterMap` without setting `nativeLibraryAvailableOverride`, and checks that `isSupported` is false, that the handler receives one `LayerCreateException` whose message states that the native library isn't available, and that an overlay after the layer is built. It runs with `flutter test --platform chrome`. On a macOS host under `flutter_tester` the process has no `map_texture_create` symbol, so the test also passes with plain `flutter test`, which checks the FFI path of the same failure.

## Risks / Trade-offs

- [`flutter test --platform chrome` may not run a package with a build hook] → Task 1.2 finds out before any change. If the hook prevents the run, the test moves to the consumer app's `integration_test/` and runs under `flutter drive -d web-server`, and the design records it.
- [A dependency of the package stops supporting web] → The web build in CI fails. D163 doesn't cover other packages, by design.
- [A later change breaks Linux or Windows apps, for example a `DynamicLibrary` call outside the `Platform` checks of `native_library_ffi.dart`] → Not checked. It would be a runtime exception in code that review sees, not a build failure.
- [The interface adds one indirection to every controller call] → It is a virtual call in Dart; the per-frame calls are a few per Flutter frame.

## Migration Plan

Groups 1 to 3 and 5 of the tasks don't touch CI files and can start now. Group 4 (D164) edits `scripts/consumer_build.sh` and `.github/workflows/consumer-build.yml`, which the branch `consumer-build-ci` (PR #1) adds and another session is still changing; it starts only after that branch is merged, and never edits the branch or its worktree. The publish-readiness change modifies the requirement that this change renames, so publish-readiness is archived first. No application changes: the public API is the same.
