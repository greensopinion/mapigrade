## Why

`MapigradeMap` displays a MapLibre map on its own, with MapLibre's camera features (see change `add-mapigrade-map`). Applications that use it don't need `flutter_map`, so the code that doesn't need `flutter_map` moves to a new package, `mapigrade`, and `flutter_mapigrade` keeps only what integrates with `flutter_map`. Several types that both widgets will use are named after the layer, such as `LayerCreateException` and `LayerPlacement`, and would be misleading under `MapigradeMap`, so they get new names.

## What Changes

- Add the package `packages/mapigrade/`, published as `mapigrade`, with one public library `package:mapigrade/mapigrade.dart`. It doesn't depend on `flutter_map`. It contains:
  - all native code: the C++ core, the Darwin and Android platform code, the build hook, `maplibre_ffi.lock`, the FFI notices and the plugin registration, including the class that registers the notices;
  - the map controller, the texture view and their test hooks;
  - the polylines (`MapigradePolyline`, `MapigradePolylineLayer`, their translation) and the overlay host that they draw through;
  - the types that both widgets use, under these names:
    - `LayerException`, `LayerCreateException`, `LayerLoadException`, `LayerQueryException`, `LayerRenderException` → `MapigradeException`, `MapigradeCreateException`, `MapigradeLoadException`, `MapigradeQueryException`, `MapigradeRenderException`
    - `LayerMetrics`, `LayerMetricsSnapshot` → `MapigradeMetrics`, `MapigradeMetricsSnapshot`
    - `LayerPlacement` → `OverlayPlacement`
    - `LayerController` → `MapigradeController`, which controls everything about a map except its camera: in this version, the feature queries and the feature state. Both widgets take it by composition; no type of either package extends a type of the other.
    - `HttpHeaderRule` and `QueriedFeature`, unchanged.
- `flutter_mapigrade` becomes a package without native code that depends on `mapigrade` and `flutter_map`. It keeps `MapigradeLayer`, which takes a `MapigradeController`, `LayerAlignment`, camera prediction and the internal layer widget, which depends on `flutter_map`. Its library re-exports the types it shares with `mapigrade`, so an application that imports only `flutter_mapigrade` needs no new import. **BREAKING**: the renamed types have no aliases under their old names. The `flutter_mapigrade` CHANGELOG lists each rename.
- `mapigrade` gets an integration library under `lib/src/` that only `flutter_mapigrade` imports, for what the layer needs and `mapigrade`'s API doesn't offer, such as the map controller and attaching a `MapigradeController` to a map. It isn't API. `flutter_mapigrade` depends on only the `mapigrade` release with its own version, so the two are always released together.
- Internal names that contain `flutter_mapigrade` change to `mapigrade`: the method channel, the Android library `libflutter_mapigrade.so`, the Android package name and the Darwin target. None of them is public API.
- Advice in doc comments about choosing between a `flutter_map` layer and a Mapigrade layer, such as in `MapigradePolylineLayer`, moves to the `flutter_mapigrade` README, phrased as when to use which layer.
- Versions: both packages always have the same version number, and `flutter_mapigrade` depends on `mapigrade` with a range that allows only that release, such as `>=0.2.0 <0.2.1`. The next release is 0.2.0 of both, the first of `mapigrade`. A script sets the version of both, and a test checks that they agree. Both are released after the FFI pin names a release (change `port-ffi-gesture-recognizer`), `mapigrade` first.

## Capabilities

### New Capabilities

### Modified Capabilities
- `package-api`: two packages with one public library each in place of one; `flutter_mapigrade` re-exports the shared types; each package has its own internal library for the tests; a new requirement covers the integration library and the exact version constraint. The naming rule for exported names (no `Map`, `Camera`, `Tile`, `Marker`, `Polyline` or `Polygon` prefix except `Mapigrade`, no name equal to a `flutter_map` name) applies to `flutter_mapigrade`'s exports, including the types it re-exports from `mapigrade`; `mapigrade`'s exports only must not equal a name exported by `latlong2`, `flutter/widgets` or `flutter/material`.
- `package-distribution`: the requirements on the FFI pin, the published archive and builds without a checkout apply to `mapigrade`; `flutter_mapigrade` contains no native code.
- `third-party-notices`: the notices and their license registry entries are provided by `mapigrade`.
- `feature-query`: the requirement "Layer controller" becomes "Map controller": `MapigradeController` provides the queries and feature state, and a failed filter is a `MapigradeQueryException`.
- `polyline-layer`: the placement type is `OverlayPlacement`, and a missing placement layer is a `MapigradeLoadException`.
- `demo-app`: the requirements "Metrics display", "Inspect features" and "Polylines" name `MapigradeMetrics`, `MapigradeController` and `OverlayPlacement`.

## Impact

- New: `packages/mapigrade/` with its `pubspec.yaml`, README, CHANGELOG and LICENSE; the pub workspace adds it. Its example comes with `MapigradeMap` in `add-mapigrade-map`.
- Moved from `packages/flutter_mapigrade/` to `packages/mapigrade/`: `src/core/`, `darwin/`, `android/`, `hook/`, `notices/`, `maplibre_ffi.lock`, `lib/src/texture/`, `lib/src/notices/`, `lib/src/polyline/`, the overlay host and the shared types in `lib/src/layer/`, and their tests. `map_texture_layer.dart` stays, because it uses `flutter_map`.
- Scripts that name the package's paths: `scripts/*.sh`, `android/build.gradle.kts`, `Package.swift`.
- `packages/test_harness/` and `packages/demo/`: imports and the renamed types.
- Documentation: both READMEs and CHANGELOGs, `CONTRIBUTING.md`, `docs/architecture.md`, `docs/packaging.md`, `docs/releasing.md` (two packages, release order), `docs/limitations.md`.
- Applications that use `flutter_mapigrade` 0.1.0: rename the types in the CHANGELOG's list.
