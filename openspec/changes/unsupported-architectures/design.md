## Context

See proposal.md for motivation and scope, and specs/map-layer/spec.md for the requirement. The in-flight change `http-headers-and-assets` uses decisions up to D84; decisions here are numbered from D85. This change starts after `public-api`.

Current state, as checked in this repository on 2026-10-12:

- `MapigradePlugin.onAttachedToEngine` (Kotlin) calls `System.loadLibrary("flutter_mapigrade")`, then `nativeInit`, and registers `ComponentCallbacks2`. `onAttachedToActivity` registers activity lifecycle callbacks that call `nativeSetPaused`, and may call `nativeSetPaused(true)` directly. The memory callbacks call `nativeReduceMemoryUse`. All three are JNI `external` functions in `libflutter_mapigrade.so`.
- The plugin's Gradle build packages `libflutter_mapigrade.so` for `arm64-v8a` only (`abiFilters += "arm64-v8a"` in the plugin module). The app module of an application decides which ABIs the APK or app bundle contains for Flutter's own libraries.
- `GeneratedPluginRegistrant` wraps each plugin's registration in `catch (Exception e)`. `UnsatisfiedLinkError` is an `Error`, so it isn't caught.
- The Dart bindings use `@Native` with `@DefaultAsset('package:flutter_mapigrade/native')`. On Android `hook/build.dart` declares that asset as `DynamicLoadingSystem('libflutter_mapigrade.so')`, so Dart opens the library by name when it resolves the first symbol. On macOS and iOS no asset is declared, and the symbols resolve from the process. A symbol that can't be resolved throws `ArgumentError` at the first call.
- `MapTextureLayer` catches `MapTextureException` from `MapTextureController.create` and reports `LayerCreateException` once (design D67).

## Goals / Non-Goals

**Goals:**
- An app that depends on the package never crashes because the native library is missing.
- One check that answers whether the layer can create a map, used both by applications and by the controller.

**Non-Goals:**
- No change to the Darwin build or the Darwin plugin class.
- No API for the reason the library is missing. The log and the exception message state it.

## Decisions

### D85. The Kotlin plugin loads its library in a `try`, and records the result

`onAttachedToEngine` wraps `System.loadLibrary` in `try`/`catch (e: UnsatisfiedLinkError)`. On failure it logs one warning with `android.util.Log.w`, naming the library and `Build.SUPPORTED_ABIS`, sets a companion field `libraryLoaded = false`, and returns before `nativeInit` and the registration of the memory callbacks. `onAttachedToActivity` and the callbacks return without calling native functions when `libraryLoaded` is false. The field is in the companion object because the load result applies to the process, and a second engine would otherwise try to load the library again.

Alternative: load the library lazily on the first map. Rejected: `nativeInit` passes the texture registry and the application context, which the plugin has only in `onAttachedToEngine`, and the lifecycle callbacks need to be registered before the first map exists.

### D86. Dart checks availability by resolving a symbol, not by the ABI

A new internal file, `lib/src/texture/native_library.dart`, defines `bool get nativeLibraryAvailable`, computed once per isolate:

- On Android: `DynamicLibrary.open('libflutter_mapigrade.so')` succeeds. It returns the copy that the plugin loaded, so it succeeds exactly when the Kotlin load succeeded.
- On macOS and iOS: `DynamicLibrary.process().providesSymbol('map_texture_create')`.
- On any other platform: false.

A failure to open throws `ArgumentError`; the check catches it and returns false.

`MapigradeLayer.isSupported` returns `nativeLibraryAvailable`. `MapTextureController.create` throws `MapTextureException('the native library of flutter_mapigrade is not available in this process')` before it creates the `NativeCallable` when the value is false. `MapTextureLayer` already turns that exception into `LayerCreateException`, so the layer needs no change.

Alternative: compare `Abi.current()` with `androidArm64`, `iosArm64` and `macosArm64`. Rejected: it is true in an arm64 process whose APK lacks the library, for example when an app's packaging options exclude it, and the controller would then throw `ArgumentError` from the first binding. Resolving the library covers that case, and the test harness can exercise it on an arm64 device (D88).

### D87. A test override for the availability check

`native_library.dart` also defines `bool? nativeLibraryAvailableOverride`, which tests set to make `nativeLibraryAvailable` return a fixed value. `lib/src/testing.dart` exports it, as it exports the other test hooks (D69). Unit tests use it for `MapigradeLayer.isSupported` and for the `LayerCreateException` reported by a layer whose controller is created by the real `MapTextureController.create`.

### D88. The test harness can leave the native library out of the APK

`packages/test_harness/android/app/build.gradle.kts` reads a Gradle property, `mapigrade.omitNativeLibrary`. When it is `true`, the app excludes `**/libflutter_mapigrade.so` through `packaging.jniLibs.excludes`. An integration test, `integration_test/unsupported_test.dart`, run with `flutter test integration_test/unsupported_test.dart --android-project-arg=mapigrade.omitNativeLibrary=true` on an arm64 emulator or device, checks that the app starts, that `isSupported` is false, and that the layer reports `LayerCreateException`. The property is in the test harness only, not in the plugin.

Alternative: test on an `x86_64` emulator. Rejected as the only check: the Android emulator on Apple-silicon Macs runs arm64 system images only. A run on a 32-bit device is in the tasks as an optional check.

### D89. Documentation

The README's limitation becomes: the native library is built for arm64; on Android, an app that also runs on other ABIs reads `MapigradeLayer.isSupported` and places another layer when it is false. The README shows an example with `TileLayer`. It also states that an app that wants no fallback sets `abiFilters` to `arm64-v8a` in its own app module, so that Google Play offers it only to devices with an arm64 ABI. `docs/limitations.md` and `CHANGELOG.md` are updated.

## Risks / Trade-offs

- [The check on Android uses `dlopen` by library name, which depends on the app's linker namespace] → It is the same lookup that `DynamicLoadingSystem` already uses for every binding, so if it fails, the bindings fail too.
- [`providesSymbol` on Darwin depends on `map_texture_create` being visible to `dlsym`] → `@Native` already resolves the symbols from the process the same way. The unit and integration tests on macOS and iOS check that `isSupported` is true.
- [An application that ignores `isSupported` gets a viewport without a map] → This matches any other creation failure, and the failure handler receives `LayerCreateException`.
- [`tile-cache-maximum-size` adds a static setter that calls native code] → That change's setter must check `nativeLibraryAvailable` first. Task 5.1 updates its tasks.
- [Behavior on a real 32-bit device is checked only if one is available] → The arm64 run without the library (D88) exercises the same code path, because `loadLibrary` fails with the same error.
