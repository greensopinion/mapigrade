## Why

An application that targets web can't build with the package. The main library imports `dart:ffi` through `lib/src/texture/map_texture_controller.dart` and `lib/src/texture/native_library.dart`, and dart2js and dart2wasm reject `dart:ffi`. On 2026-10-20, `flutter build web` and `flutter build web --wasm` of a new app that depends on the package and places `MapigradeLayer` only when `MapigradeLayer.isSupported` is true both failed with "Dart library 'dart:ffi' is not available on this platform". Many `flutter_map` apps build for web as well as for mobile, so these apps can't use the package at all, even with a fallback layer on web. We want to fix this before 0.0.1 is published.

## What Changes

- An application that depends on the package builds for web with dart2js and with dart2wasm. On web the package imports no `dart:ffi`, `dart:io` or `package:ffi` code.
- On web, `MapigradeLayer.isSupported` is false, and a placed `MapigradeLayer` reports a `LayerCreateException` and draws nothing, as on an Android device without the native library. Setting `MapigradeLayer.maximumCacheSizeBytes` stores the value and calls no native code.
- The requirement "Unsupported architectures" of `map-layer` is renamed "Unsupported platforms and architectures" and also covers web.
- A unit test fails when a file that the main library reaches on web imports `dart:ffi`, `dart:io` or `package:ffi`. A widget test of the layer without the native library runs in Chrome. The consumer build check builds the consumer application for web, with and without `--wasm`, in its existing macOS job.
- The plugin README and `CHANGELOG.md` state the behavior on web.

Non-goals:

- No map rendering on web, Linux or Windows. Rendering on web, with `vector_map_tiles` or with maplibre-gl-js, is a later change.
- No `web`, `linux` or `windows` entry in `flutter.plugin.platforms`. pub.dev would then show support for platforms where the layer draws nothing.
- No change on Android, iOS and macOS.
- No requirement or check for Linux and Windows. Apps built for them already compile with the package and see `isSupported == false`, and this change doesn't alter the code that does it, but nothing tests it and we have no Linux or Windows machine. The README states it as untested.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-layer`: the requirement "Unsupported architectures", as the publish-readiness change modifies it, is renamed "Unsupported platforms and architectures" and covers applications built for web: they build, `isSupported` is false, and a placed layer reports a creation failure.

## Impact

- Dart API: no new or changed names. `isSupported` returns false on web.
- Code: `lib/src/texture/map_texture_controller.dart` is split into the shared types, the controller's interface and its FFI implementation; `lib/src/texture/native_library.dart` gets a web counterpart; `lib/src/testing.dart` keeps its exports. New test in `test/`.
- Scripts and CI: a `web` target in `scripts/consumer_build.sh`, and two steps in the macOS job of `.github/workflows/consumer-build.yml`. The publish-readiness change adds both files on the branch `consumer-build-ci` (PR #1), where work is in progress, so this change edits them only after that branch is merged.
- Documentation: `packages/flutter_mapigrade/README.md`, `CHANGELOG.md`, `docs/adoption-gaps.md`.
- Ordering: the publish-readiness change modifies the same requirement, so it is archived before this change.
