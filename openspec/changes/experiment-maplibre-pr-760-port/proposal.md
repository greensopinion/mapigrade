## Why

maplibre-native-ffi PR #760 ("Move execution into the native core and generate language bindings") replaces the synchronous, host-driven C API that mapigrade uses with a core worker that owns the map, asynchronous commands, and frame demands. `mln_runtime_pump`, `mln_map_jump_to` and `mln_render_session_render_update` no longer exist. In discussion #877 the PR's author asked us to evaluate mapigrade's use case against #760's core executor before they consider a synchronous executor, and said that mapigrade's display slots and surface switching are in scope for #760. We want to find out how well #760 supports mapigrade while the PR is still open, so that we can give feedback that changes its API before it merges.

## What Changes

- An experimental port of mapigrade's native core and platform render targets to the C API of #760, on the branch `experiment-maplibre-pr-760-port`. We expect to discard the branch; if #760 merges, it is a reference for the real port.
- The FFI that the branch builds against is #760 at a pinned commit, built from source. The package's released FFI pin on `main` doesn't change.
- A findings document, `docs/maplibre-pr-760-port-findings.md`, that records how well #760 supports mapigrade, where the complexity is, what breaks, which questions remain open, and the feedback for #760.
- Measurements with the existing frame-rate and alignment benchmarks, comparing the branch with `main`.
- Drafts of upstream issues for #760, each backed by findings and measurements.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. The port isn't meant to change mapigrade's behavior. Where it can't keep a requirement, for example the number of display slots on Apple platforms, the findings document records that as a result of the experiment. The change sets `skip_specs: true`.

## Impact

- Native core: `packages/flutter_mapigrade/src/core/` (map thread loop, camera, rendering, events, logging, teardown).
- Platform render targets: `darwin/.../MapTextureMetal.mm` and `android/src/main/cpp/map_texture_android.cpp`.
- FFI build: `packages/flutter_mapigrade/maplibre_ffi.lock`, `scripts/build_maplibre_ffi.sh`, and the local xcframework that `Package.swift` uses.
- Native tests in `packages/flutter_mapigrade/test/native/`, which fake the current C API, don't build on the branch.
- Dart code, the public API of `flutter_mapigrade`, and `main` are not affected.
