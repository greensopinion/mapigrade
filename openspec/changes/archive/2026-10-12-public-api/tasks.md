## 1. Source files and names

- [x] 1.1 Rename `lib/src/layer/camera_alignment.dart` to `layer_alignment.dart` and `CameraAlignment` to `LayerAlignment` as a `final` class (D65), update `test/layer/camera_alignment_test.dart` (renamed `layer_alignment_test.dart`), and verify `flutter test` in `packages/flutter_mapigrade` passes
- [x] 1.2 Add `lib/src/layer/layer_exception.dart` with `LayerException` (`abstract final`, implements `Exception`) and `LayerLoadException`, `LayerRenderException`, `LayerCreateException` (`final`), with `==`, `hashCode` and `toString` as in D68, and verify a new `test/layer/layer_exception_test.dart` covers equality, inequality across subclasses, and `toString`
- [x] 1.3 Rename `lib/src/texture/testing.dart` to `test_hooks.dart` and move `processThreadCount` into it from `map_texture_controller.dart` (D69), and verify `flutter analyze` in `packages/flutter_mapigrade` reports no errors

## 2. Layer widgets

- [x] 2.1 Rename `map_libre_texture_layer.dart` to `map_texture_layer.dart` and `MapLibreTextureLayer` to `MapTextureLayer`, with `onStyleLoaded`, `onError` and `createController` parameters next to `copyFree` and `onController`, and the library doc comment taken from `lib/src/layer/README.md`; remove the README (D65, D66), and verify `flutter analyze` reports no errors
- [x] 2.2 Add `lib/src/layer/mapigrade_layer.dart` with the `final` `StatelessWidget` `MapigradeLayer` that asserts exactly one of `styleUrl` and `styleJson` and builds `MapTextureLayer` with `copyFree: true` (D66), and verify a widget test in `test/layer/mapigrade_layer_test.dart` finds a `MapTextureLayer` with the given values below it
- [x] 2.3 In `MapTextureLayer`'s `State`, listen to `controller.events` and map `StyleLoaded`, `LoadingFailed` and `RenderError` to `onStyleLoaded` and `LayerLoadException`/`LayerRenderException`, reading callbacks from the current widget, reporting through `FlutterError.reportError` when `onError` is null, and cancelling the subscription in `dispose` (D67), and verify `flutter analyze` reports no errors
- [x] 2.4 Catch `MapTextureException` from controller creation in `didChangeDependencies`, report `LayerCreateException` once, don't retry, and build `SizedBox.fromSize(size: viewport)` while creation has failed (D67), and verify widget tests in `test/layer/map_texture_layer_test.dart` that use a failing `createController` show: the handler receives one `LayerCreateException` across repeated dependency changes; with no handler `FlutterError.onError` receives it once with library `flutter_mapigrade`; a `MarkerLayer` after the layer is still drawn

## 3. Libraries

- [x] 3.1 Replace `lib/flutter_mapigrade.dart` with the three `show` exports of D65 and a library doc comment with the usage snippet (D74), and verify `flutter analyze` in `packages/flutter_mapigrade` reports no errors
- [x] 3.2 Add `lib/src/testing.dart` with the `show` exports listed in D69 and remove `lib/testing.dart`, and verify `flutter analyze` in `packages/flutter_mapigrade` reports no errors

## 4. Test harness

- [x] 4.1 Change the test harness imports from `package:flutter_mapigrade/testing.dart` to `package:flutter_mapigrade/src/testing.dart`, disable `implementation_imports` in its `analysis_options.yaml`, use `MapTextureLayer` where it passes `onController` or `copyFree`, `MapigradeLayer` elsewhere, and `LayerAlignment` for `CameraAlignment` (D69, migration plan), and verify `flutter analyze` in `packages/test_harness` reports no errors and `flutter test` there passes
- [x] 4.2 Add integration tests to `packages/test_harness/integration_test/map_layer_test.dart` for the map-layer scenarios "Style loaded", "Style changed on a layer in the tree" (the second style change waits for the first `onStyleLoaded`; the controller passed to `onController` stays the same), "Style fails to load" and "No failure handler", and verify they pass with `flutter test integration_test/map_layer_test.dart -d macos`
- [x] 4.3 Run the full integration test suite of the test harness on macOS and verify every test passes, including the existing insert/remove and alignment tests

## 5. API tests

- [x] 5.1 Add `package:analyzer` as a dev dependency of the plugin at a version that resolves with the workspace, and verify `flutter pub get` at the repo root succeeds (if no version resolves, follow the fallback in design.md Risks and record it there)
- [x] 5.2 Add `test/api_test.dart` with the checks of D70 item 1 and the class-modifier check of item 2, with failure messages that name the name and the rule, and verify it passes, and that it fails with such a message when a temporary `export ... show` of `MapTextureController` is added to the main library (then remove the export)
- [x] 5.3 Add `test/api_usage_test.dart` that imports the main library, `flutter_map`, `latlong2` and `material.dart` without prefix or `hide` and refers to every exported name (D70 item 2), and verify it passes with `flutter test`

## 6. Native asset, dependencies and lints

- [x] 6.1 Annotate `bindings.dart` with `@DefaultAsset('package:flutter_mapigrade/native')` and change the Android asset name in `hook/build.dart` to `native` (D71), and verify the test harness builds and shows the map on an Android emulator or device, and still runs on macOS
- [x] 6.2 Change the plugin's `flutter_map` constraint to `^8.3.2` (D72), and verify `flutter pub get` at the repo root resolves `flutter_map` 8.3.2
- [x] 6.3 Add `public_member_api_docs` and `strict-casts`, `strict-inference`, `strict-raw-types` to the plugin's `analysis_options.yaml` and fix the findings in `lib/` and `test/` (D72), and verify `flutter analyze` in `packages/flutter_mapigrade` reports no issues

## 7. Example app

- [x] 7.1 Create `packages/flutter_mapigrade/example/` with `flutter create --template=app --platforms=android,ios,macos --org com.greensopinion --project-name flutter_mapigrade_example`, set the platform settings of D73, and add it to the workspace members in the root `pubspec.yaml`, and verify `flutter pub get` at the repo root succeeds
- [x] 7.2 Write `example/lib/main.dart` with a `FlutterMap`, `MapigradeLayer` (OpenFreeMap Liberty), a `MarkerLayer` with one marker and a `SnackBar` for `LayerException` messages, importing only the main library of the package (D73), and verify `flutter analyze` in the example reports no issues and `grep` finds no `package:flutter_mapigrade/src/` import in it
- [x] 7.3 Run the example on macOS, the iOS simulator and the Android emulator, and verify on each that the map appears below the marker and the marker is at its coordinate

## 8. Documentation and related change

- [x] 8.1 Replace the template `README.md` of the plugin with the content listed in D74 and write the 0.0.1 entry of `CHANGELOG.md`, and verify `dart pub publish --dry-run` in `packages/flutter_mapigrade` reports no errors about the README, CHANGELOG or example
- [x] 8.2 Update the proposal (and design, specs and tasks, where they name it) of `tile-cache-maximum-size` to use `MapigradeLayer.maximumCacheSizeBytes` instead of `MapTextureController.setMaximumCacheSize`, and verify `openspec validate tile-cache-maximum-size` passes
