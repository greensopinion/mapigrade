## Why

maplibre-native-ffi PR #760 merged on 2026-10-21 and replaced the synchronous C API that mapigrade uses with a core executor: asynchronous commands, frame demands and completions. FFI release 0.202610.2 (2026-10-22) includes it, and the iOS 15.0 deployment target that the change `support-ios-15-0` waits for, so mapigrade can't take that release or a later one until its native code uses the new API. The experiment `experiment-maplibre-pr-760-port` showed that #760 at FFI `main` serves mapigrade on macOS, iOS and Android (`docs/maplibre-pr-760-port-findings.md` on its branch); this change makes that port real, so that it can merge to `main`.

## What Changes

- The native core uses #760's C API: the map thread drives a render session with the caller-graphics-thread driver, applies cameras as commands, waits for each camera command's completion before it renders, and matches each frame to its camera through the render update generation that the command's completion reports.
- On macOS and iOS, a copy-free map renders into its 4 display slots through one borrowed texture ring with frame acquisition and release, and ends outstanding frame demands before a resize replaces the ring. The map with the copy stays.
- On Android, the surface target uses #760's surface session and attaches a new session when its target is lost.
- Teardown, pausing, resizing, surface replacement and memory reduction use #760's operations and their completions.
- The native tests move from the fake of the synchronous API to a headless FFI target if one serves them, or to a fake of the asynchronous API.
- The FFI pin moves from release 0.202610.1 to 0.202610.2, whose tag is `v0.202610.2`: the FFI dropped the `core/` prefix from its release tags.
- A memory warning while rendering is paused releases the renderer's cached resources when rendering resumes, not at once, because #760 runs memory reduction as driver work.
- Out of scope: the pacing of rendering ahead (a separate change), and placing the map thread on the performance cores on iOS. On the iPhone 15 Pro Max the displayed map frame rate is 2% to 3% lower than with the released FFI, and on the iPhone 13 at most 2% lower, with faster renders.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: the requirement "Memory warnings release cached renderer resources" allows the release to wait until rendering resumes while the application is in the background.
- `third-party-notices`: the requirement "Native notices in the license registry" adds three Android entries for the notice files that FFI release 0.202610.2 adds: Kotlin, its NOTICE file, and the FFI's patched rustls-platform-verifier.

## Impact

- Native core: `packages/flutter_mapigrade/src/core/` (map thread loop, camera, rendering, events, logging, teardown) and the render target interface.
- Platform targets: `darwin/.../MapTextureMetal.mm` and `android/src/main/cpp/map_texture_android.cpp`.
- FFI pin: `maplibre_ffi.lock`, `darwin/flutter_mapigrade/Package.swift`, the notices in `notices/`, and the scripts that name the release tag.
- Native tests in `packages/flutter_mapigrade/test/native/`.
- Docs: `docs/benchmarks.md`, `CONTRIBUTING.md`, `docs/limitations.md`, and the experiment's findings document, which moves to `main`.
- Dart code and the public API of `flutter_mapigrade` don't change.
- `support-ios-15-0` follows this change: it needs 0.202610.2, which this change pins, and stays a change of its own.
- The branch `experiment-maplibre-pr-760-port` and its draft PR are the reference for the code; this change starts from `main`.
