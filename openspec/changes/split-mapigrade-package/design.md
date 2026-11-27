## Context

`flutter_mapigrade` 0.1.0 is one Flutter plugin package: native code under `src/core/`, `darwin/` and `android/`, a build hook, the FFI pin and notices, and Dart code in `lib/src/texture/` (map controller, view, bindings), `lib/src/layer/` (the layer, its controller, failures, metrics, camera prediction, the overlay host) and `lib/src/polyline/`. Only the layer code depends on `flutter_map`: `mapigrade_layer.dart`, `map_texture_layer.dart` (which builds `flutter_map`'s `MapInheritedModel`), `camera_prediction.dart`, `layer_alignment.dart`, `alignment_error.dart`, and the `flutter_map` conversions in `camera_projection.dart`. `ViewCamera` and the Mercator math in that file don't use `flutter_map`.

`LayerController` is attached to a layer through library-level functions (`bindLayerController`, `setLayerControllerMap`, `releaseLayerController`), and queries convert their position with a callback that returns the camera of the displayed frame. The controller doesn't depend on `flutter_map`.

This change runs after `port-ffi-gesture-recognizer` on the branch `mapigrade-map`, so the native files are ported before they move. See proposal.md for the motivation and the specs for the requirements.

## Goals / Non-Goals

**Goals:**
- `mapigrade` builds, tests and publishes without `flutter_map` in its dependency graph.
- `flutter_mapigrade` behaves as 0.1.0 does, apart from the renamed types.
- Git history follows the moved files.

**Non-Goals:**
- `MapigradeMap` and its API (`add-mapigrade-map`).
- A place for process-wide settings other than `MapigradeLayer`: `MapigradeLayer.isSupported` and `MapigradeLayer.maximumCacheSizeBytes` stay where they are; `add-mapigrade-map` decides where `MapigradeMap` applications find them.

## Decisions

### D228. Move files with `git mv`, one package per directory

`packages/mapigrade/` gets `src/core/`, `darwin/`, `android/`, `hook/`, `notices/`, `maplibre_ffi.lock`, `lib/src/texture/`, `lib/src/notices/`, `lib/src/polyline/`, and from `lib/src/layer/`: `overlay_host.dart`, `layer_controller.dart`, `layer_exception.dart`, `layer_metrics.dart`, `layer_placement.dart`, `http_header_rule.dart` and `queried_feature.dart`, each renamed after the type it declares (`mapigrade_controller.dart`, `overlay_placement.dart` and so on). `camera_projection.dart` splits: `ViewCamera` and the Mercator math move; `viewCameraOf` and `flutterMapCameraOf` stay in `flutter_mapigrade`. The files move with `git mv` in a commit of their own, before any edit, so that `git log --follow` finds their history. The tests move with the code they test.

Alternative: keep the native code in `flutter_mapigrade` and make `mapigrade` depend on it. Then `mapigrade` would depend on `flutter_map` through it, which defeats the split.

### D229. `MapigradeController` by composition

`MapigradeController` is a `final class` in `mapigrade`, renamed from `LayerController` with the same members. `MapigradeLayer.controller` takes it. The attach functions keep their shape, renamed to `bindController`, `setControllerMap` and `releaseController`, and take the owning widget's state and its callback for the displayed frame's camera, so that any widget that owns a map can attach a controller. They are in the integration library (D230), not in the API.

No type in either package extends, implements or mixes in a type of the other. Dart's class modifiers apply per library, so a type that another package could extend could also be extended by applications, which the requirement "Exported types are closed to applications" forbids.

Alternative: keep `LayerController` as a wrapper that forwards to a `MapigradeController`. It adds a second controller type for one map and a method for each forwarded one, and gives applications nothing.

### D230. The integration library

`package:mapigrade/src/integration.dart` exports what `flutter_mapigrade` needs and `mapigrade`'s API doesn't offer: `MapTextureController`, `MapTextureView`, `ViewCamera` and the Mercator math, the controller attach functions, the overlay host scope that `MapTextureLayer` provides, the metrics binding, and `nativeLibraryAvailable`. It is the only library of `mapigrade` that `flutter_mapigrade` imports besides the main library; each import carries `// ignore: implementation_imports`, and the API test of `flutter_mapigrade` checks that no other `src/` library of `mapigrade` is imported. `mapigrade`'s README says that applications must not import it.

`package:mapigrade/src/testing.dart` exports the controller, the view and the test hooks for the test harness; `package:flutter_mapigrade/src/testing.dart` exports `MapTextureLayer`, `AlignmentError` and the other layer helpers it exports today.

Alternative: a public `package:mapigrade/integration.dart` marked unsupported. A file outside `lib/src/` is API by convention and by the requirement "Exported names", so applications would have a supported-looking way to depend on internals.

### D231. One version number, exact constraint, released together

Both packages always have the same version, and `flutter_mapigrade` depends on exactly that version of `mapigrade`, with no range. The first release of `mapigrade` is 0.2.0, the same version as the next `flutter_mapigrade`. Because of the exact constraint, a release of one package is unusable without a release of the other, so every release releases both; a package without changes gets a CHANGELOG entry that says so.

`scripts/set_version.sh <version>` writes the three values: the `version` of each `pubspec.yaml` and `flutter_mapigrade`'s constraint on `mapigrade`. A unit test fails, and names the value that differs, when the three aren't equal. Between releases, both pubspecs keep the last released version, and the pub workspace resolves `mapigrade` to `packages/mapigrade/` because its version satisfies the constraint.

`flutter pub publish` resolves `mapigrade` from pub.dev, so `docs/releasing.md` orders the release: run pana on both packages from the clean clone, publish `mapigrade`, then dry-run and publish `flutter_mapigrade` once `mapigrade` is on pub.dev.

Alternatives: a caret constraint, with which a newer `mapigrade` could break an older `flutter_mapigrade`, because the integration library may change in any version; independent version numbers, with which each release has to keep a mapping between the two.

### D232. Native names follow the package

The plugin is declared in `mapigrade`'s `pubspec.yaml` with the plugin classes it has today. The method channel is `mapigrade`, the Android library `libmapigrade.so`, the Android package `com.greensopinion.mapigrade`, the Swift package directory `darwin/mapigrade/`, and the code asset `package:mapigrade/native`. `flutter_mapigrade`'s `pubspec.yaml` has no `plugin` section, no build hook and no assets.

The notices' `dartPluginClass` registration moves with the plugin, so `mapigrade` registers the FFI notices once, whether an application depends on it directly or through `flutter_mapigrade`.

### D233. Tests per package

`mapigrade` gets the native tests, the controller, view and texture tests, the notices tests, `ffi_pins_test.dart`, `pending_queries_test.dart`, `texture_boundary_test.dart`, the polyline tests, `unsupported_platform_test.dart`, `web_imports_test.dart`, and an API test and API usage test of its own. `flutter_mapigrade` keeps the layer, alignment and prediction tests and its API tests, and gains the check of D230. The test harness and the demo depend on both packages. `scripts/consumer_build.sh` copies both published file lists and resolves `mapigrade` from its copied directory with a dependency override.

### D234. Web builds

The web stubs of the native library move with it. `web_imports_test.dart` runs in `mapigrade` and checks its library; `flutter_mapigrade` keeps a test that its main library builds for web, which now also covers its imports of `mapigrade`.

## Risks / Trade-offs

- [pub.dev lists platforms of a package without a `plugin` section from what pana infers, so `flutter_mapigrade` could lose its Android, iOS and macOS tags] → Run pana on both dry-run archives before the release; if `flutter_mapigrade` loses tags, state the platforms in its `pubspec.yaml` `platforms` field.
- [An application that pinned `flutter_mapigrade: ^0.1.0` doesn't get 0.2.0, and one that upgrades must rename types] → Expected for a 0.x minor version; the CHANGELOG lists each rename.
- [The integration library couples the two packages tightly] → Accepted, with the exact version constraint (D231). It is the price of keeping the API closed (D229).
- [`git mv` and edits in one commit lose history] → D228 moves files in their own commit.

## Migration Plan

Applications rename the types that the `flutter_mapigrade` CHANGELOG lists, including `LayerController` to `MapigradeController`, and change nothing else. `mapigrade` arrives as a transitive dependency.
