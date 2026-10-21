# Findings: porting mapigrade to maplibre-native-ffi PR #760

This document records what we learned by porting mapigrade to the C API of [maplibre-native-ffi PR #760](https://github.com/maplibre/maplibre-native-ffi/pull/760) ("Move execution into the native core and generate language bindings") on the branch `experiment-maplibre-pr-760-port`. The plan is the OpenSpec change `experiment-maplibre-pr-760-port` (proposal, design and tasks in `openspec/changes/experiment-maplibre-pr-760-port/`); the questions Q1 to Q7 and the decisions D166 to D172 are those of its design. The background is [discussion #877](https://github.com/maplibre/maplibre-native-ffi/discussions/877).

Each finding names the #760 commit it was made with, and states whether it comes from #760 or from the port's shortcuts (D172).

## #760 commit

| Date | Commit | Reason |
|---|---|---|
| 2026-10-21 | `3b56ef916` ("Merge origin/main into binding-codegen") | Initial pin (D166). |

## Baseline

The branch's first commit adds camera-to-frame latency to `map_texture_stats` (D171) and still uses the released FFI (0.202610.1, commit `a2f332ec`). The port is measured against that commit.

### macOS (2026-10-21, commit `c1b51b1`, 3 runs each)

Conditions: the Setup of `docs/benchmarks.md` (MacBook Pro M2 Max, window 1600x1000 logical pixels, display scaled to 1800x1169), macOS 26.6.2, Flutter 3.47.7, release builds, copy-free, rendering ahead with the hysteresis (the default). The result lines are in `docs/maplibre-pr-760-port-results/`.

Frame-rate benchmark (`benchmark.dart`, 30 s pan):

| Run | Displayed map fps | Per-second min / p10 / p50 / p90 | Frame cycle (ms) | `render_update` (ms) | Camera latency avg (ms) |
|---|---|---|---|---|---|
| 1 | 106.8 | 96 / 100 / 106 / 116 | 8.88 | 7.50 | 8.98 |
| 2 | 107.2 | 97 / 101 / 107 / 113 | 8.91 | 7.48 | 8.84 |
| 3 | 108.2 | 99 / 100 / 108 / 115 | 8.84 | 7.47 | 8.94 |

Alignment benchmark (`ALIGNMENT_CHILDREN=1`, mode `predict1`, 20 s per phase). The drawn error was 0 px at p50, p95 and max in every phase of every run. Ranges over the 3 runs:

| Phase | Lag p50 / p95 / max (px) | Camera latency avg (ms) | Map fps |
|---|---|---|---|
| pan100 | 0.83 / 1.67 / 3.33 | 9.27–9.76 | 102.3–104.0 |
| pan500 | 0–4.17 / 8.33 / 12.47–12.5 | 8.80–9.32 | 105.0–107.3 |
| pan1000 | 8.33 / 16.67 / 25.0–33.5 | 9.11–9.37 | 95.4–107.0 |
| stop | 0 / 16.67 / 33.33 | 10.45–10.67 | 82.8–84.4 |
| fling | 0.43–0.73 / 16.67–16.88 / 85.4–110.8 | 9.66–10.08 | 98.3–100.6 |
| reverse | 8.33 / 16.67 / 33.3–50.0 | 9.79–10.09 | 99.8–101.4 |

The camera latency is about one frame cycle (8.8–10.7 ms), measured from `setCamera` to the frame-ready event of the first frame with that camera. `camera_latency_max_ms` counts from the map's creation, not per phase, so the table leaves it out.

## Q1. Display slots on Apple platforms

Open. From reading #760's source at `3b56ef916` (not yet tested):

- A borrowed ring has 1 to 3 textures, and `mln_render_session_set_metal_borrowed_texture_target` keeps the count that the session attached with. mapigrade has 4 display slots on macOS and iOS.
- A frame that the host never acquires doesn't keep its slot. To choose the slot of a render, `render_session_common.cpp` (around line 2827) takes the first slot that isn't acquired, rendering, quarantined or holding a published frame, and otherwise the slot with the oldest published frame that isn't acquired. A ring of one texture therefore renders into its one texture every time, and D168's replacement before each render isn't refused because of an unacquired frame.
- `mln_render_frame_result` with `MLN_RENDER_RESULT_RENDERED` "states nothing about GPU completion" (`render_session.h`). Completion is stated only for an acquired frame: with `MLN_GPU_SYNC_CPU_COMPLETE`, the default and the only producer synchronization on Metal, the GPU writes completed before the frame became acquirable. So that Flutter doesn't sample a texture that MapLibre is still writing, the map thread acquires each rendered frame and releases it before the next target replacement, which `set_metal_borrowed_texture_target` requires ("fails while a frame of the ring is acquired"). This adds an acquire and a release per frame to D168.
- In practice the Metal backend waits for completion inside the render: `MetalTextureBackend`'s `swap()` (`metal_texture_backend.mm`, line 141) commits the command buffer and calls `waitUntilCompleted()`. With a caller-graphics-thread driver that wait runs on the map thread inside `service_driver_work`, so the GPU writes have completed when the frame result arrives. The C API doesn't promise this, so the port acquires and releases each frame anyway, and the findings record whether doing so costs measurable time.

## Q2. Latency from camera to frame

Open; measured in tasks 4.1 and 4.2. What the port does (D169), and what was harder than the design expected:

- A frame result carries the camera that the frame drew (`mln_render_frame_result.view.camera`), so no projection is needed to read it. The center's longitude is unwrapped (it can fall outside -180 to 180); before #760 `mln_map_projection_get_camera` returned it wrapped. Near longitude 0, as in the benchmarks, this makes no difference; elsewhere Dart would compare a camera off by 360°.
- To keep `FrameInfo.seq` (D125), the port must know which camera command a frame includes. The completion of `mln_map_update_camera` reports a map *snapshot* generation, while a frame result's `map_update_generation` counts *render updates*, a different counter. The design (D169) assumed they could be compared. The port reads `mln_map_get_snapshot` in the camera's completion and records the snapshot's `latest_render_update_generation`. If another command published an update between the camera command and that read, the recorded generation is later than the camera's, so the frame gets the camera's `seq` one frame late. A completion that also reported the render update generation of the command would remove this.
- With a caller-graphics-thread driver, the map thread arms one demand with `MLN_FRAME_DEMAND_IF_NEEDED | MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` as soon as a slot may be rendered. The camera command goes to the runtime's scheduler thread, which publishes an update, which wakes the map thread through `driver_work_wake`, whose service call then renders.

### First run (task 3.2, 2026-10-21)

A debug build of the test harness on macOS with continuous pan (`LOG_FRAMES`, `CONTINUOUS_PAN`, window 1200x800) showed the map and displayed about 121 map frames per second. Each displayed frame reported its camera and `seq`, and no render error was reported. The frames used display slots 0, 1 and 2 about equally (347, 346 and 346 of 1,039); slot 3 wasn't used in that run (task 3.3 checks it in a release build).

## Q3. Synchronous execution

Open.

## Q4. Glyph load failures

Open. #760's log records (`logging.h`) carry no map identity, and #760 has no glyph failure event. Error records are still delivered synchronously on the thread that emits them. On `main`, MapLibre's `RenderOrchestrator::onGlyphsError` emits the record on the thread that renders, which is the map thread. If the orchestrator still runs where the session renders, which with a caller-graphics-thread driver is mapigrade's map thread, the `thread_local` owner still identifies the map. If it runs on the runtime worker, it doesn't, and mapigrade has no way to set a thread-local value on that thread. Task 3.5 tests which.

## Q5. Android hook before the swap

Open. On `main`, Android switches the session's surface only when the window is replaced or the map parks on a pbuffer, not per frame. In discussion #877 we wrote that Android switches the OpenGL surface per frame; that was wrong.

## Q6. Lifecycle

Open; task 3.4 tests it. What the port showed so far:

- Pausing (D13): the port keeps "no GPU work while paused" by not servicing the driver while paused; demands and target replacements wait in the session. This needs no #760 change.
- Memory reduction while paused regresses. Before #760, `mln_render_session_reduce_memory_use` released cached tiles and images at once, also while paused, which is when iOS sends memory warnings. Under #760 it is driver work, so with a caller-graphics-thread driver it runs only when the map thread services the driver, which it doesn't do while paused. Servicing it anyway would also run any queued render. A way to run CPU-only driver work, such as cache release, without running GPU work would fix this; a core-worker session wouldn't have the problem.
- Resize: before #760 `set_target` replaced the target at once. Under #760 it is an ordered operation, while mapigrade releases the previous buffer set in the same step (D126). The previous textures must stay valid until the replacement runs, so the port services the driver until the replacement's completion before it continues. A replacement that the host could apply synchronously on the graphics thread would avoid the wait loop.
- Teardown: detach (servicing until its completion), then release the map and the runtime and wait for each completion, so that no completion or event callback reaches the map's object afterwards. Before #760 this was three synchronous destroy calls.

## Q7. Other API

Open. From the headers at `3b56ef916`:

- HTTP headers: `mln_http_header_transform` takes `mln_http_header_rule`s (resource kinds, a URL glob, headers) that native code applies without a callback. mapigrade's rules (D81) map onto them directly, which removes mapigrade's use of `mln_adapter_http_header_*`.
- `MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE` no longer exists (event values 9, 11, 12 and 22 are retired). mapigrade counts it in `render_update_available_events` and renders when it arrives; under #760 a frame demand with `MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` takes its place.
- The maximum cache size, the header transform and memory reduction become operations with completions.

## Complexity

Lines of the native code on `main` (commit `d71c9bc`), in `packages/flutter_mapigrade`:

| Area | Files | Lines on `main` | Lines on the branch |
|---|---|---|---|
| Core | `src/core/*` | 2,677 | 3,155 after task 3.2 |
| Apple target | `darwin/.../MapTextureMetal.mm` | 459 | 481 after task 3.3 |
| Android target | `android/src/main/cpp/map_texture_android.cpp` | 772 | |
| Native tests | `test/native/*` | 2,371 | not built (D172) |

Where the core's 478 added lines went (tasks 3.1 and 3.2), with `map_texture.cpp` growing from 1,085 to 1,463 lines:

- About 100 lines of completion plumbing: a waiter for completions that the map thread blocks on (map creation, attach, detach, target replacement after a resize, map and runtime release), a completion that runs a function on the completing thread, and freeing a completion's user data when its call is rejected. Before #760 every call that mapigrade made was synchronous.
- About 150 lines for the frame loop: arming one frame demand at a time, servicing the driver, draining frame results and matching them to the armed demand, and handling a result of a demand whose slot a resize reset. Before #760 this was one `render_update` call.
- About 60 lines in `Init`: the event handler, the native header rules (which replace about 25 lines of adapter tables), and waiting for map creation.
- About 40 lines of teardown: detach and wait while servicing, then release the map and the runtime and wait for each.
- The rest: a condition variable in place of the runtime's wake source, the wake callback, and the event callback, which replaces draining events.

## Build

- `macos-arm64-metal` (task 2.1): `scripts/build_maplibre_ffi.sh` built #760 at `3b56ef916` without changes; only `MAPLIBRE_FFI_COMMIT` in `maplibre_ffi.lock` changed. #760 still has the presets, the `[vars]` of `mise.toml` and the scripts `.mise/bin/sync-submodules` and `sync-rustls-platform-verifier` that the script uses. The build took 148 s on top of an earlier build directory.
- `android-arm64-egl` (task 2.2): built without changes in 117 s on top of an earlier build directory, after deleting the install directory. The patched `rustls-platform-verifier-android` component built and installed as version `3b56ef916410`. NDK 30.0.16248370, which #760's `mise.toml` pins, was already installed.
- A defect of mapigrade's script, not of #760: the script reuses the FFI's install directory, so headers that #760 removed (`callback_adapter.h`, `diagnostics.h`) stayed in the framework. Deleting `third_party/maplibre-native-ffi-src/build/<preset>/install` before the build removes them. The real port should make the script delete the install directory.

## What broke

Nothing yet.

## Feedback for #760

None yet. Issue drafts go here for review before anything is posted.
