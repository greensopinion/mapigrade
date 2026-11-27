## Why

MapLibre Native FFI moved to mln-rs: commits `d62ed4c` and `79dee41` of maplibre/maplibre-native-ffi rebuilt the C library on mln-rs and reshaped the C API around it. Every later FFI release is built on mln-rs, including the release that includes terrain, so the package has to port to this C API to get any later FFI fix or feature. The move also brought two things that `MapigradeMap` needs: the gesture recognizer (`gesture.h`) and the projection that each frame was drawn with (`mln_render_frame_result.frame_projection`). `MapigradeMap` displays a MapLibre map on its own, with MapLibre's camera features (see change `add-mapigrade-map`). The package pins release 0.202610.3. No FFI release includes the move yet, and it changes much of the C API, so the port is a change of its own.

## What Changes

- Pin a commit on the FFI's `main` branch that includes `d62ed4c` and `79dee41`, in place of release 0.202610.3. The design names the commit. On the branch `mapigrade-map`, the package then builds only with a local FFI build. We release neither package until an FFI release includes the pinned features and the pin names that release.
- Rewrite `scripts/build_maplibre_ffi.sh` for the FFI's new build, which compiles mln-rs with Cargo and has new preset names, so that the example, the test harness and the demo build with a local FFI build on macOS, iOS and Android.
- Port the native code to the C API of the pinned commit: the shared C++ core, the Metal glue, the Android glue and the native tests. The port keeps the package's behavior.
- Carry `frame_projection` from each frame result to the frame that the map thread publishes, so that a later change can give it to Dart. Dart doesn't read it in this change.
- Compare the change with `main` on the Mac in the frame-rate benchmark and the alignment benchmark, and record the results in `docs/benchmarks.md`.

Not in this change: the gesture recognizer's use, the frame projection in Dart, and terrain. `add-mapigrade-map` uses the first two. Terrain waits until the FFI renders terrain.

## Capabilities

### New Capabilities

### Modified Capabilities

None expected: the port keeps the package's behavior. If the port finds a behavior that the new C API changes, as the 0.202610.3 port found for cleartext HTTP on Android, the change adds a delta spec for it.

## Impact

- `packages/flutter_mapigrade/maplibre_ffi.lock`, and the binary target in `darwin/flutter_mapigrade/Package.swift` that `scripts/update_ffi_pins.sh` writes.
- `scripts/build_maplibre_ffi.sh` and the scripts it sources.
- Native code: `packages/flutter_mapigrade/src/core/`, `android/src/main/cpp/map_texture_android.cpp`, `darwin/.../MapTextureMetal.mm`, and `test/native/`.
- `packages/flutter_mapigrade/notices/`, if the pinned commit's notice files differ from those of 0.202610.3.
- Documentation: `CONTRIBUTING.md` (building with a local FFI build, the pinned commit), `docs/benchmarks.md`, and `docs/packaging.md` where it names the FFI release.
- Release: the `package-distribution` requirements that an application's build gets the FFI from the stated release can't be met while the pin names a commit. They are met again when the pin names an FFI release, before either package is released.
