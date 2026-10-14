## 1. Android plugin

- [x] 1.1 In `MapigradePlugin.kt`, wrap `System.loadLibrary` in `try`/`catch (e: UnsatisfiedLinkError)`, log one warning with `Log.w` that names the library and `Build.SUPPORTED_ABIS`, record the result in a companion field `libraryLoaded`, and return before `nativeInit` and the memory callback registration when the load failed (D85), and verify `flutter build apk --debug` in `packages/test_harness` succeeds
- [x] 1.2 Make `onAttachedToActivity`, the activity lifecycle callbacks and the memory callbacks return without calling `nativeSetPaused` or `nativeReduceMemoryUse` when `libraryLoaded` is false (D85), and verify by reading the class that no `external` function is called on a path that doesn't check `libraryLoaded`

## 2. Dart availability check

- [x] 2.1 Add `lib/src/texture/native_library.dart` with `nativeLibraryAvailable`, computed once, by `DynamicLibrary.open('libflutter_mapigrade.so')` on Android, `DynamicLibrary.process().providesSymbol('map_texture_create')` on macOS and iOS, and false elsewhere, catching `ArgumentError`, plus `nativeLibraryAvailableOverride` (D86, D87), and export the override from `lib/src/testing.dart`; verify `flutter analyze` in `packages/flutter_mapigrade` reports no errors
- [x] 2.2 Make `MapTextureController.create` throw `MapTextureException` with the message in D86 before it creates the `NativeCallable` when `nativeLibraryAvailable` is false, and verify a unit test with the override set to false gets that exception and no `ArgumentError`
- [x] 2.3 Add the static getter `MapigradeLayer.isSupported` with a doc comment that tells applications to place another layer when it is false (D86), and verify a unit test in `test/layer/mapigrade_layer_test.dart` reads true and false with the override set to each value
- [x] 2.4 Add a widget test in `test/layer/mapigrade_layer_test.dart` that places `MapigradeLayer` with the override set to false, a failure handler, and a `MarkerLayer` after it, and verify the handler receives one `LayerCreateException` whose message states that the native library isn't available, no exception is thrown, and the marker is drawn
- [x] 2.5 Use `MapigradeLayer.isSupported` in `test/api_usage_test.dart`, and verify `flutter test` in `packages/flutter_mapigrade` passes, including the API test with the exported names unchanged

## 3. Test harness

- [x] 3.1 In `packages/test_harness/android/app/build.gradle.kts`, exclude `**/libflutter_mapigrade.so` through `packaging.jniLibs.excludes` when the Gradle property `mapigrade.omitNativeLibrary` is `true` (D88), and verify with `unzip -l` that a debug APK built with `-Pmapigrade.omitNativeLibrary=true` lacks the library and one built without the property contains it
- [x] 3.2 Add `packages/test_harness/integration_test/unsupported_test.dart`, which starts the app, checks that `MapigradeLayer.isSupported` is false, places the layer with a failure handler, and checks that the handler receives one `LayerCreateException`; verify it passes with `env 'ORG_GRADLE_PROJECT_mapigrade.omitNativeLibrary=true' flutter test integration_test/unsupported_test.dart` on the arm64 Android emulator, and that `adb logcat` shows the warning from 1.1
- [x] 3.3 Add a check to the harness's existing integration tests that `MapigradeLayer.isSupported` is true, and verify it passes on macOS, on an iPhone and on the Android emulator built without the property (2026-10-13: the iPhone 17 Pro Max simulator was used in place of an iPhone, as the user decided)
- [ ] 3.4 Optional, if a 32-bit Android device is available (2026-10-13: none is available): install a release build of the example without an app-level `abiFilters`, and verify that the app starts and that `MapigradeLayer.isSupported` is false

## 4. Documentation

- [x] 4.1 Replace the README limitation "arm64 only on every platform" with the text of D89, including a `TileLayer` fallback example and the `abiFilters` setting, and add an entry to `CHANGELOG.md`; verify the example compiles by copying it into a scratch test in `packages/flutter_mapigrade/test/` and running `flutter analyze`, then remove the scratch test
- [x] 4.2 Update the arm64 entry in `docs/limitations.md` to say what happens on Android without an arm64 ABI and that `MapigradeLayer.isSupported` reports it, and verify the entry names the integration test of 3.2

## 5. Related changes

- [x] 5.1 The change `tile-cache-maximum-size` was archived on 2026-10-12, so instead of updating its tasks, make `MapTextureController.setMaximumCacheSize` return without calling native code when `nativeLibraryAvailable` is false, so that the setter of `MapigradeLayer.maximumCacheSizeBytes` only stores the value, and verify a unit test in `test/layer/mapigrade_layer_test.dart` with the override set to false sets and reads the value
