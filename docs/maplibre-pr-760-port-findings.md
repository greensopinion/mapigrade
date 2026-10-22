# Findings: porting mapigrade to maplibre-native-ffi PR #760

This document records what we learned by porting mapigrade to the C API of [maplibre-native-ffi PR #760](https://github.com/maplibre/maplibre-native-ffi/pull/760) ("Move execution into the native core and generate language bindings") on the branch `experiment-maplibre-pr-760-port`. The plan is the OpenSpec change `experiment-maplibre-pr-760-port` (proposal, design and tasks in `openspec/changes/experiment-maplibre-pr-760-port/`); the questions Q1 to Q7 and the decisions D166 to D172 are those of its design. The background is [discussion #877](https://github.com/maplibre/maplibre-native-ffi/discussions/877).

Each finding names the #760 commit it was made with, and states whether it comes from #760 or from the port's shortcuts (D172).

## Summary

Status on 2026-10-21: the port runs on macOS, iOS and Android against #760 at `3b56ef916` with one local patch (D173). It is measured against the released FFI on the Mac, the iPhone 15 Pro Max and the Pixel 4a (5G). The integration tests that failed on the port on the Pixel and the iOS simulator now pass; the causes were two defects of the port and two behaviors of #760 that the port had to handle (frames rendered in any service call, and a lost target that only a new session recovers) ("What broke").

Findings:

- **Frame rate and overlay alignment don't change.** On the Mac and the iPhone, the displayed map frame rate, the time to render a frame, and the alignment of the layer's children (0 px error in every phase) are the same as with the released FFI ("Mac and iPhone compared"). On the Pixel the time to render a frame is the same and the frame rate is 1.3% lower; the alignment benchmark doesn't run on Android ("Pixel 4a (5G)").
- **mapigrade's 4 display slots on Apple platforms don't fit #760 as it is.** A borrowed texture ring holds at most 3 textures, and replacing the ring's texture before each frame, which the port does instead, makes an idle map render about 120 frames per second without end: #760's replacement resets the session's record of the rendered update. maplibre-native-ffi#807 fixed the same behavior in the earlier API. A 26-line patch with the semantic of #807 fixes it, and all measurements use it. #760's reset is intended and tested, so we ask the maintainers whether they prefer an opt-in or a changed default before proposing a change (Q1).
- **On the iPhone, a camera change reaches a finished frame 3.5 ms later unless the host waits for the camera command (11.4 → 15.0 ms; 11.0–11.3 ms with the wait).** Without the wait this is one more display frame of lag in fast pans. The cause isn't #760's runtime thread, which applies a camera and publishes its update in 60 µs, nor thread priority. It is ordering: the map thread services the driver right after submitting the camera, before the update is published, so the camera misses that render. The port has the wait only as a switch (`MLN760_WAIT_CAMERA=1`, off by default), and all benchmarks ran without it; ask 2 would replace the wait, which spins on a completion that runs on another thread. On the Mac and the Pixel the difference is about 0.3 ms; on the Pixel, renders paced to the 60 Hz refresh absorb the ordering effect (Q2).
- **Android works with the caller-graphics-thread driver.** Any service call can present the armed frame, including one made while waiting for a target replacement, so the port sets the next frame's presentation time before every service call. In practice no service call presented more than one frame, but the C API promises neither (Q5).
- **A lost target is terminal on Android.** During fast window replacements the session lost its target several times. Before #760 the next replacement recovered; under #760 the port must detach the session and attach a new one, which also rebuilds the renderer (Q6).
- **Ordered target replacement and driver-work operations make lifecycle code wait.** After a resize, a window replacement or a park, the map thread services the session until the replacement's completion before it releases the previous textures or surface. Memory reduction while paused no longer runs, because it is driver work and a paused session isn't serviced (Q6).
- **Glyph load failures are still attributed to their map**, because with a caller-graphics-thread driver the renderer reports them on mapigrade's map thread. With a core-worker driver they wouldn't be (Q4).
- **The native core grew by about 570 lines (21%)**, not counting about 125 lines of temporary diagnostics: mostly completion plumbing, where every call was synchronous before, the frame-demand loop, which replaces one `render_update` call, and the waits and re-attachment of Q6 ("Complexity").
- **Q3 (synchronous execution):** with asks 1 and 2 below, #760's core executor with a caller-graphics-thread driver serves mapigrade's requirements on the Mac, the iPhone and the Pixel, and a separate synchronous executor isn't needed.

Open: the iPhone alignment benchmark with the camera wait, which should show the extra frame of lag gone, hasn't run. The benchmarks ran before the last fixes to resizing and target loss, which don't affect a steady pan ("What broke").

Asks for #760, most important first (details in "Feedback for #760"):

1. Let a host rotate more display slots than a borrowed ring holds without rendering an idle map without end: either an opt-in that keeps the record of the rendered update across a same-size replacement (the semantic of #807; #760's default, which renders into the new texture at once, is intended and tested), or a frame demand that names the slot of a ring of more than 3 textures. We ask the maintainers which they prefer, then propose a stacked pull request.
2. Let a caller-graphics-thread host make the next render include a command it just submitted, for example a frame demand with a minimum render update generation. On the iPhone this is the whole difference between 15 ms and 11 ms of camera latency.
3. Report the render update generation that a map command published in its completion, so that a host can tell which frame includes the command. Today the completion reports a snapshot generation, which is a different counter.
4. Run CPU-only driver work, such as memory reduction, without the GPU work queued with it, so that a paused caller-driver session can release memory.
5. Make the per-frame hook before a surface target swaps explicit, for example a frame token that the session attaches to the presented buffer. Any service call can present a frame, including one that services a target replacement.
6. Let a target replacement bring a session whose surface target was lost back to attached, or document how a host recovers, so that a host doesn't have to rebuild the session and the renderer after a failed swap.

## #760 commit

| Date | Commit | Reason |
|---|---|---|
| 2026-10-21 | `3b56ef916` ("Merge origin/main into binding-codegen") | Initial pin (D166). |
| 2026-10-21 | `3b56ef916` with `scripts/patches/maplibre-native-ffi-760-same-size-retarget.patch` | D168 renders without end without it (Q1, D173). |

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

Answered: 4 display slots work only with the local patch of D173 (see "Result" and "With the local patch" below). From reading #760's source at `3b56ef916`, before testing:

- A borrowed ring has 1 to 3 textures, and `mln_render_session_set_metal_borrowed_texture_target` keeps the count that the session attached with. mapigrade has 4 display slots on macOS and iOS.
- A frame that the host never acquires doesn't keep its slot. To choose the slot of a render, `render_session_common.cpp` (around line 2827) takes the first slot that isn't acquired, rendering, quarantined or holding a published frame, and otherwise the slot with the oldest published frame that isn't acquired. A ring of one texture therefore renders into its one texture every time, and D168's replacement before each render isn't refused because of an unacquired frame.
- `mln_render_frame_result` with `MLN_RENDER_RESULT_RENDERED` "states nothing about GPU completion" (`render_session.h`). Completion is stated only for an acquired frame: with `MLN_GPU_SYNC_CPU_COMPLETE`, the default and the only producer synchronization on Metal, the GPU writes completed before the frame became acquirable. So that Flutter doesn't sample a texture that MapLibre is still writing, the map thread acquires each rendered frame and releases it before the next target replacement, which `set_metal_borrowed_texture_target` requires ("fails while a frame of the ring is acquired"). This adds an acquire and a release per frame to D168.
- In practice the Metal backend waits for completion inside the render: `MetalTextureBackend`'s `swap()` (`metal_texture_backend.mm`, line 141) commits the command buffer and calls `waitUntilCompleted()`. With a caller-graphics-thread driver that wait runs on the map thread inside `service_driver_work`, so the GPU writes have completed when the frame result arrives. The C API doesn't promise this, so the port acquires and releases each frame anyway, and the findings record whether doing so costs measurable time.

### Result: a replacement before each frame renders without end (task 3.4)

D168 doesn't work. With a borrowed ring of one texture replaced before each render, an idle copy-free map never stops rendering: in `map_texture_test.dart`, "idle map renders no frames for 10 seconds" and "idle copy-free map renders no frames for 10 seconds" rendered 39 → 1,240 and 39 → 1,232 frames in 10 s, about 120 per second. The map with the copy (one ring texture, never replaced) stayed at 39 → 39. `map_layer_test.dart` fails "metrics stay the same while the map is at rest" (99 expected, 219 rendered) for the same reason.

The cause is in #760's target replacement (`render_session_common.cpp` around line 1858): it sets `rendered_update_generation = 0` and `pending_changes = true`, and resumes the demands that wait for an update, because "the new target holds no frame of the latest update". So each replacement makes the next demand with `MLN_FRAME_DEMAND_IF_NEEDED | MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` render, and that render's slot is replaced again before the next one. Before #760, mapigrade had the same problem with `mln_metal_borrowed_texture_set_target`, and maplibre-native-ffi#807 fixed it by keeping the record of the rendered update across a same-size replacement. #760 reintroduces it, by design.

This is the strongest evidence for Q1: under #760 mapigrade can't rotate more display slots than the ring holds, neither by a larger ring (at most 3) nor by replacing the ring's texture (each replacement forces a render).

The engines test acquired 83 frames after `MLN_RENDER_RESULT_RENDERED` results, and none reported `MLN_STATUS_NOT_READY`.

### With the local patch (D173, task 3.6)

`scripts/patches/maplibre-native-ffi-760-same-size-retarget.patch` (26 lines added, 4 removed, in `src/render/render_session_common.cpp`) gives #760's target replacement the semantic of maplibre-native-ffi#807: a replacement of a borrowed texture ring with the same extent and physical size keeps the record of the rendered update, marks the new target as holding it, and doesn't resume demands that wait for an update. With it, "idle map renders no frames for 10 seconds" (38 → 38 frames) and "idle copy-free map renders no frames for 10 seconds" (39 → 39) pass, and `map_layer_test.dart` passes completely (15 tests). "metrics stay the same while the map is at rest" fails when it runs alone ("Expected: not null"), on the branch as a whole; it depends on an earlier test of the file, which is a defect of mapigrade's tests, not of the port.

From here on, every measurement of the copy-free path is of #760 at `3b56ef916` with this patch. The patch is the first change proposed for #760. We ask the maintainers first whether they prefer an opt-in or a changed default (task 7.3, draft in "Feedback for #760"), and prepare a stacked pull request after their answer (task 7.4).

The reset is intended in #760: `tests/native/abi/backend/retarget.c` has the test `a_borrowed_retarget_renders_a_waiting_demand`, whose comment says "A replacement holds no frame of the map's latest update, so a demand that waits for an update renders into it with no update to wait for." A host that reallocates its textures expects the new texture to get the latest frame without waiting. mapigrade needs the opposite, because it fills each texture only with its next frame. The patch changes the default and would break that test, so the stacked pull request shouldn't propose it as it is. An opt-in on the replacement (for example a descriptor field that keeps the rendered update across a same-size replacement), or a frame demand that names the ring slot to render into with a ring of more than 3 textures, would serve mapigrade without changing #760's default.

## Q2. Latency from camera to frame

Answered for the Mac, the iPhone and the Pixel (tasks 4.1, 4.2, 5.3, 6.2 and 6.4). What the port does (D169), and what was harder than the design expected:

- A frame result carries the camera that the frame drew (`mln_render_frame_result.view.camera`), so no projection is needed to read it. The center's longitude is unwrapped (it can fall outside -180 to 180); before #760 `mln_map_projection_get_camera` returned it wrapped. Near longitude 0, as in the benchmarks, this makes no difference; elsewhere Dart would compare a camera off by 360°.
- To keep `FrameInfo.seq` (D125), the port must know which camera command a frame includes. The completion of `mln_map_update_camera` reports a map *snapshot* generation, while a frame result's `map_update_generation` counts *render updates*, a different counter. The design (D169) assumed they could be compared. The port reads `mln_map_get_snapshot` in the camera's completion and records the snapshot's `latest_render_update_generation`. If another command published an update between the camera command and that read, the recorded generation is later than the camera's, so the frame gets the camera's `seq` one frame late. A completion that also reported the render update generation of the command would remove this.
- With a caller-graphics-thread driver, the map thread arms one demand with `MLN_FRAME_DEMAND_IF_NEEDED | MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` as soon as a slot may be rendered. The camera command goes to the runtime's scheduler thread, which publishes an update, which wakes the map thread through `driver_work_wake`, whose service call then renders.

### First run (task 3.2, 2026-10-21)

A debug build of the test harness on macOS with continuous pan (`LOG_FRAMES`, `CONTINUOUS_PAN`, window 1200x800) showed the map and displayed about 121 map frames per second. Each displayed frame reported its camera and `seq`, and no render error was reported. The frames used display slots 0, 1 and 2 about equally (347, 346 and 346 of 1,039); slot 3 wasn't used in that run (task 3.3 checks it in a release build).

### iPhone (2026-10-21, task 6.2)

Baseline `c1b51b1` (released FFI) against the branch at `c8a0321` (#760 at `3b56ef916` with the patch of D173), 3 runs each of the frame-rate benchmark and of the alignment benchmark (`ALIGNMENT_CHILDREN=1`, mode `predict1`, 20 s per phase), alternating, release builds, copy-free. iPhone 15 Pro Max on cable power, launched with `MLT_KEEP_AWAKE=1`, 430x932 logical pixels at pixel ratio 3. The thermal state was fair at the end of the first alignment run of each side and serious at the end of every later one, on both sides; the frame-rate benchmark doesn't report it. The result lines are in `docs/maplibre-pr-760-port-results/ios1-*`.

Frame-rate benchmark (30 s pan), mean of 3 runs:

| | Displayed map fps | Frame cycle (ms) | Service or `render_update` (ms) | Camera latency avg (ms) |
|---|---|---|---|---|
| Baseline | 109.6 (109.1–110.1) | 8.33–8.42 | 7.95 | 11.4 (11.35–11.5) |
| Port | 109.6 (108.7–110.2) | 8.31–8.37 | 7.92 | 15.0 (14.74–15.42) |

The port's lowest second was lower in two runs (94 and 78 frames against 101–102 for the baseline); p10 and p50 were the same.

Alignment benchmark, ranges over 3 runs. The drawn error was 0 px at max in every phase of every run on both sides, and every phase used all 4 display slots.

| Phase | Camera latency (ms), baseline | port | Lag p50 (px), baseline | port |
|---|---|---|---|---|
| pan100 | 10.9–12.4 | 15.1–16.1 | 0.83 | 0.84–1.66 |
| pan500 | 11.5–11.8 | 13.6–15.1 | 4.17 | 4.18–4.2 |
| pan1000 | 11.6–11.9 | 14.1–15.7 | 8.33–8.34 | 8.35–16.64 |
| stop | 12.8–13.1 | 16.6–17.6 | 0.01–0.03 | 0.05–1.52 |
| fling | 11.9–12.3 | 15.8–16.5 | 1.46–2.12 | 2.78–3.42 |
| reverse | 12.5–12.9 | 16.5–18.0 | 8.34 | 16.65–16.67 |

On the iPhone the port keeps the frame rate and the alignment of the layer's children (the error stays 0 px), but each camera reaches a finished frame about 3.5 ms later (about 30% more, or about 0.4 of a 120 Hz refresh interval). Where that pushes the frame past a refresh, the displayed map lags the live `flutter_map` camera by one more frame: in reverse in all 3 runs and in pan1000 in 2 of 3 runs, the median lag doubled from 8.3 px to 16.6 px (one frame at 1,000 px/s), and the p95 lag of stop and reverse rose from 16.7 px to 25 px. Camera prediction (`predict1`) doesn't hide the extra latency; task 4.2 tests whether a longer lead does. The extra time is the path from `mln_map_update_camera` through the runtime's scheduler thread, its render update and `driver_work_wake`, back to the map thread; the service call that renders costs the same as `render_update` did.

### macOS (2026-10-21, task 4.1)

Baseline `c1b51b1` against the branch at `c8a0321`, 3 runs each, alternating, in the Setup of the baseline above; every run's window was checked to be on screen. The thermal state was nominal throughout. The result lines are in `docs/maplibre-pr-760-port-results/cmp1-*`.

| | Displayed map fps | Per-second p10 / p50 | Service or `render_update` (ms) | Camera latency avg (ms) |
|---|---|---|---|---|
| Baseline | 104.9–108.3 | 98–102 / 105–108 | 7.44–7.48 | 8.79–9.11 |
| Port | 107.1–108.7 | 99–102 / 107–109 | 7.44–7.49 | 8.96–9.20 |

Alignment benchmark: the drawn error was 0 px at max in every phase of every run, every phase used all 4 display slots (task 3.3), and the median lag was the same on both sides in every phase. The port's camera latency was 0.2–0.6 ms longer per phase (for example pan100 9.34–9.56 ms against 9.91–10.0 ms, reverse 9.75–10.17 ms against 10.29–10.34 ms). The port's p95 lag in fling was 18.1–19.6 px against 16.67 px, and its maximum lag at stop was 41.7–58.3 px against 33.3 px.

### Mac and iPhone compared

On the Mac the port adds about 0.3 ms per camera, well inside the frame budget, so the lag doesn't change. On the iPhone it adds about 3.5 ms, enough to push frames past a 120 Hz refresh. The service call that renders costs the same on both. Task 6.4 found the cause: not thread priority or the runtime thread's speed, but the order of the camera command and the next service call ("Where the iPhone's extra latency goes", below).

### Camera prediction on macOS (2026-10-21, task 4.2)

The alignment benchmark with `ALIGNMENT_MODE=none` (no prediction), 3 runs each, alternating baseline and port, compared with the `predict1` runs of task 4.1. Median and p95 lag in px, ranges over 3 runs; the drawn error was 0 px everywhere.

| Phase | none, baseline | none, port | predict1, baseline | predict1, port |
|---|---|---|---|---|
| pan100 | 1.67 / 2.5 | 1.67 / 2.5 | 0.83 / 1.67 | 0.83 / 1.67 |
| pan500 | 8.33 / 12.5 | 8.33 / 12.5 | 4.17 / 8.33 | 4.17 / 8.33 |
| pan1000 | 16.67 / 25.0 | 16.67 / 25.0 | 8.33 / 16.67 | 8.33 / 16.67 |
| stop | 0–0.03 / 25.0 | 0–0.01 / 25.0 | 0 / 16.67 | 0 / 16.67 |
| fling | 8.33 / 27.1–32.7 | 8.26–8.33 / 33.3–34.5 | 0.65–0.74 / 16.67 | 0.86–0.92 / 18.1–19.6 |
| reverse | 16.67 / 25.0 | 16.67 / 25.0 | 8.33 / 16.67 | 8.33 / 16.67 |

On the Mac, prediction halves the median lag under #760 as it does with the released FFI, and without prediction the two are the same. The port's slightly higher p95 in fling appears with and without prediction. On the Mac, #760's extra 0.3 ms per camera doesn't cost a frame, so prediction keeps its full effect. On the iPhone, the extra 3.5 ms cost one frame in pan1000 and reverse even with `predict1` (task 6.2); whether a longer lead (`predict2`) recovers it on the iPhone is still open.

### System Trace on the iPhone (task 6.4)

An Instruments System Trace of 8 s of continuous pan (release builds, `CONTINUOUS_PAN=true`, phone unplugged and out of its case, but still warm from task 6.2) of the port and of the baseline, summarized per thread from the `thread-state` table:

- Every MapLibre thread runs at scheduler priority 31 (the default QoS) in both builds, including mapigrade's map thread in the baseline (the main thread runs at 47 and Flutter's raster thread at 50). #760 creates its worker threads with `pthread_create` and no QoS (`src/execution/worker_thread.cpp`), so its runtime thread has the same priority as mapigrade's map thread always had. Priority alone doesn't explain the extra latency.
- In the port, the thread that behaves like #760's runtime scheduler thread (priority 31, about 5,500 short running intervals in 8 s) was runnable but not running for 48.8 ms in total, about 9 µs per wake. Waiting for a core isn't where the 3.5 ms go either.
- Both builds ran mostly on performance cores; the busiest MapLibre thread spent about 10% of its running time on efficiency cores in both.
- The extra latency is real and not an artifact of `seq` attribution (D169): the layer draws its children at the camera of the frame's `seq`, and a late attribution would have shown as alignment error, which was 0 px.

The port now prints, every 300 cameras, the mean of four stages of camera-to-frame latency (`MLN760_STAGES`): `setCamera` to the camera command's submission, submission to its completion on the runtime thread, completion to the start of the service call that renders the frame, and that service call to the frame-ready event. A run on a cool phone will show which stage takes the extra time.

### Where the iPhone's extra latency goes (task 6.4)

On a cool iPhone (unplugged, out of its case), one frame-rate run of the port printed these stage means over 5,700 cameras (`docs/maplibre-pr-760-port-results/ios-stages-run.txt`):

| Stage | Mean |
|---|---|
| `setCamera` → the map thread submits the camera command | 3.0 ms |
| Submission → the command's completion on #760's runtime thread | 0.06 ms |
| Completion → start of the service call that renders the frame | 3.4 ms |
| That service call → frame ready | 7.7 ms |
| Camera-to-frame latency | 15.0 ms |

#760's runtime thread isn't slow: it applies the camera and publishes its update in 60 µs. The extra time is an ordering effect of the asynchronous camera command. The map thread submits the camera and then services the driver at once, usually before the update is published 60 µs later (in 2,187 of 5,700 cameras the rendering service call started before the completion). That service call renders the previous update, and the camera waits for the next render, about 8 ms later, which averages to about 3.4 ms. Before #760, `mln_map_jump_to` was synchronous, so the render that followed it always included the camera.

To confirm it, the port has a switch, `MLN760_WAIT_CAMERA=1`, with which the map thread waits for the camera command's completion (at most 2 ms) before it services the driver. On the iPhone, 2 runs each, alternating (`ios-wait0-*`, `ios-wait1-*`):

| | Camera latency avg | Completion → service | Displayed map fps | Frame cycle |
|---|---|---|---|---|
| Without waiting | 15.2–15.7 ms | 3.6–3.9 ms | 108.7–109.7 | 8.38–8.45 ms |
| Waiting for the camera | 11.0–11.3 ms | 0.03–0.04 ms | 110.1–110.6 | 8.35–8.41 ms |
| Baseline, released FFI (task 6.2) | 11.4 ms | | 109.6 | 8.33–8.42 ms |

Waiting for the camera brings the port's latency back to the baseline's, at no cost in frame rate. So #760's core executor can serve mapigrade's latency requirement on the iPhone, provided the host can make the next render include a command it just submitted. The port does that by spinning on the completion, which works but needs #760's completion to run on another thread quickly. A frame demand that names a minimum render update generation (for example the one a command's completion reports, Q2), or a camera command whose completion reports the render update generation it published, would let a caller-driver host express "render the update that includes this camera" without waiting.

Not yet measured with the wait: the alignment benchmark's lag on the iPhone. Since the latency matches the baseline's, the extra frame of lag in pan1000 and reverse (task 6.2) is expected to disappear.

### Pixel 4a (5G) (2026-10-21, task 5.3)

Baseline `c1b51b1` (the released FFI's runtime AAR) against the branch at `4173c68` (#760 at `3b56ef916` with the patch of D173), 3 runs each of the frame-rate benchmark, alternating, release builds for arm64, on USB power with the screen kept on. The alignment benchmark doesn't run on Android, which reports no display times (design D58); the frame-rate benchmark counts the frames that Dart chose. Logcat truncates the full result line, so both builds also print the timing fields in a short `BENCHMARK_KEY` line (`docs/maplibre-pr-760-port-results/px2-*`).

| | Map fps | Per-second min / p10 / p50 / p90 | Frame cycle | Service or `render_update` | Camera latency avg |
|---|---|---|---|---|---|
| Baseline | 53.1–53.7 | 42–47 / 50 / 53–54 / 57–58 | 17.17–17.22 ms | 7.73–7.85 ms | 29.9–30.5 ms |
| Port | 52.5–52.9 | 44–47 / 48–50 / 53–54 / 56–57 | 17.26–17.29 ms | 7.75–7.85 ms | 30.4–30.8 ms |

On the Pixel the port's camera latency is about 0.3 ms longer and its frame rate about 0.7 frames per second (1.3%) lower; the time to render a frame is the same. The ordering effect that costs 3.5 ms on the iPhone hardly shows here, because a surface target paces its renders to one per 16.7 ms refresh interval (designs D53 and D134): a camera that misses one service call is rendered by the next paced render, which waits for the interval in both builds (`interval_waits` about 1,700 in both).

## Q3. Synchronous execution

Tentative answer: not needed, if #760 takes asks 1 and 2 ("Feedback for #760"). The two places where the port couldn't match the released FFI's results are the display slots (Q1), which the patch of D173 fixes, and the iPhone's camera latency (Q2), which waiting for the camera command's completion fixes. In both cases a small change to the asynchronous API serves the use case. The rest of the port's added complexity (completions, waits for ordered replacements, the frame-demand loop) is the cost of the asynchronous API, not a blocker. 

## Q4. Glyph load failures

Answered: the attribution still works with a caller-graphics-thread driver. `resource_test.dart` "glyphs that fail to load report a load failure" passes on macOS (task 3.5). Neither the released FFI nor #760 has a glyph failure event; both forward `onGlyphsError` to the renderer observer (`map.cpp`, `render_session_common.hpp`), and with a caller-graphics-thread driver the renderer runs on mapigrade's map thread, where the `thread_local` owner identifies the map. With a core-worker driver the record would come from a thread that mapigrade doesn't own, and the attribution would break. A map event for glyph failures would remove the dependency on the log callback.

Before that, from the headers alone: #760's log records (`logging.h`) carry no map identity, and #760 has no glyph failure event. Error records are still delivered synchronously on the thread that emits them. On `main`, MapLibre's `RenderOrchestrator::onGlyphsError` emits the record on the thread that renders, which is the map thread. If the orchestrator still runs where the session renders, which with a caller-graphics-thread driver is mapigrade's map thread, the `thread_local` owner still identifies the map. If it runs on the runtime worker, it doesn't, and mapigrade has no way to set a thread-local value on that thread. Task 3.5 tests which.

## Q5. Android hook before the swap

On `main`, Android switches the session's surface only when the window is replaced or the map parks on a pbuffer, not per frame. In discussion #877 we wrote that Android switches the OpenGL surface per frame; that was wrong.

Port (task 5.1, `8af69ee`):

- `WillRender` (the frame id as the presentation time, and the scissor workaround) runs on the map thread before each `service_driver_work` call while a demand is armed (D170). This is correct only if one service call renders at most one frame. In a 13 s continuous pan on the Pixel 4a (5G) (debug build, `LOG_FRAMES`, `CONTINUOUS_PAN`), 603 frames were displayed, every image arrived with the id of a frame that a slot had queued, and no unknown frame was reported (D131), so no service call rendered more than one frame. The C API doesn't promise this; a per-frame hook that the driver calls right before it swaps, or a frame token that the session attaches to the presented buffer, would make it explicit.
- Before #760 the attachment made the dedicated context current at once, and the target set the swap interval right after it. Under #760 the context becomes current in driver work after the attach call returns, so the target sets the swap interval in `WillRender` once the session's context is current on the window surface.
- A window replacement or a park is an ordered operation under #760, while the target destroys the previous EGL surface right after it. The target services the session until the replacement's completion before it destroys the surface (Q6).
- The map rendered at about 55 map frames per second in that debug build, and all 6 display slots were used (130, 132, 128, 127, 84 and 2 frames).
- Any service call can render the armed demand's frame, not only the one that the map thread makes to render: a call that services a target replacement or an attachment also runs a demand that the replacement resumed. On the Pixel, a frame rendered while the map thread waited for a window replacement reached the image reader with the system's timestamp in place of a frame id, and the port reported "received an image of unknown frame 112078786893156" (this failed "a maximum cache size set while a map exists"). The port now sets the frame id before every service call, also in its wait loops, and the test passes. This makes ask 5 more important: a host can't know which service call will present a frame.

## Q6. Lifecycle

Answered (tasks 3.4, 5.2 and 6.3). What the port showed:

- Pausing (D13): the port keeps "no GPU work while paused" by not servicing the driver while paused; demands and target replacements wait in the session. This needs no #760 change.
- Memory reduction while paused regresses. Before #760, `mln_render_session_reduce_memory_use` released cached tiles and images at once, also while paused, which is when iOS sends memory warnings. Under #760 it is driver work, so with a caller-graphics-thread driver it runs only when the map thread services the driver, which it doesn't do while paused. Servicing it anyway would also run any queued render. A way to run CPU-only driver work, such as cache release, without running GPU work would fix this; a core-worker session wouldn't have the problem.
- Resize: before #760 `set_target` replaced the target at once. Under #760 it is an ordered operation, while mapigrade releases the previous buffer set in the same step (D126). The previous textures must stay valid until the replacement runs, so the port services the driver until the replacement's completion before it continues. A replacement that the host could apply synchronously on the graphics thread would avoid the wait loop.
- Teardown: detach (servicing until its completion), then release the map and the runtime and wait for each completion, so that no completion or event callback reaches the map's object afterwards. Before #760 this was three synchronous destroy calls.
- A lost target is terminal. Before #760 a failed render was reported, and the next target replacement recovered. Under #760 a failed render (`render_session_render_update_on_driver` returning an error) puts the session into `MLN_RENDER_SESSION_STATE_TARGET_LOST`; frame requests then fail, because they require `MLN_RENDER_SESSION_STATE_ATTACHED` (`render_session_common.cpp`, line 3096), and no replacement sets that state again. On the Pixel, "resizing on every frame for 10 seconds" lost its target after 9 to 21 frames and then showed a blank map until the test timed out. The surface that the session presented to is most likely the Surface of an ImageReader that `MapSurface` had just replaced on the main thread. The port now detaches a session whose target is lost and attaches a new one to the current surface; with that, `map_texture_test.dart` passes on the Pixel (28 passed, 2 skipped), and the map thread recovered a lost target 4 times during the file. A replacement that brings a lost surface target back to attached (or a documented recovery path) would remove the re-attachment, which also rebuilds the renderer and its caches.

## Q7. Other API

Answered: nothing here blocked the port. From the headers at `3b56ef916`, confirmed by the port:

- HTTP headers: `mln_http_header_transform` takes `mln_http_header_rule`s (resource kinds, a URL glob, headers) that native code applies without a callback. mapigrade's rules (D81) map onto them directly, which removes mapigrade's use of `mln_adapter_http_header_*`.
- `MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE` no longer exists (event values 9, 11, 12 and 22 are retired). mapigrade counts it in `render_update_available_events` and renders when it arrives; under #760 a frame demand with `MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` takes its place.
- The maximum cache size, the header transform and memory reduction become operations with completions.

## Complexity

Lines of the native code on `main` (commit `d71c9bc`), in `packages/flutter_mapigrade`:

| Area | Files | Lines on `main` | Lines on the branch |
|---|---|---|---|
| Core | `src/core/*` | 2,677 | 3,373 at `84b6244`, of which about 125 are temporary diagnostics |
| Apple target | `darwin/.../MapTextureMetal.mm` | 459 | 481 after task 3.3 |
| Android target | `android/src/main/cpp/map_texture_android.cpp` | 772 | 829 at `84b6244` |
| Native tests | `test/native/*` | 2,371 | not built (D172) |

Where the core's first 478 added lines went (tasks 3.1 and 3.2), with `map_texture.cpp` growing from 1,085 to 1,463 lines. Later tasks added about 95 lines for the waits and the re-attachment of Q6 and the stale-frame fix, and about 125 lines of temporary diagnostics:

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

macOS integration tests on the branch at `a87c69b` (task 3.4):

- `map_texture_test.dart`: 25 passed, 1 skipped, 2 failed. The failures are "idle map renders no frames for 10 seconds" and "idle copy-free map renders no frames for 10 seconds" (Q1, rendering without end). Pausing, resizing every frame, freeing replaced buffers, memory reduction, surface removal, the cache size, style failures and the selected-frame tests passed.
- `map_layer_test.dart`: 14 passed, 1 failed: "metrics stay the same while the map is at rest" (same cause).
- `engines_test.dart` (`flutter drive`): all passed.
- `resource_test.dart`: all passed, including the glyph failure test (Q4).

Pixel 4a (5G) at `3e5b263` (task 5.2): stopping and resuming the activity during a continuous pan worked (the map parked on the pbuffer, frames stopped for 3.9 s and resumed with the new window). `map_layer_test.dart` passed (15 tests). `map_texture_test.dart`: 27 passed, 2 skipped, 1 failed: "a maximum cache size set while a map exists" reported a `RenderError`, "received an image of unknown frame", which the test passes on the baseline. The cause was a frame rendered in a service call during a window replacement, without a frame id (Q5). With the frame id set before every service call, "resizing on every frame for 10 seconds" then failed on the Pixel, because the session lost its target (Q6); it had passed before only by timing. With both fixes and the re-attachment of a lost session, `map_texture_test.dart` passes on the Pixel (28 passed, 2 skipped).

iOS simulator (iPhone 17, iOS 26.5) at `3e5b263` (task 6.3): `map_layer_test.dart` passed (15 tests). `map_texture_test.dart`: 28 passed, 1 skipped, 1 failed: "resizing on every frame for 10 seconds" never displayed a frame of the final size. On the baseline the same test passes (551 frames rendered, final size displayed).

The cause was a defect of the port, not of #760. A state dump of the stalled map thread showed the session had rendered every map update (`rendered_update_generation` equal to `map_update_generation`, nothing pending), while the map thread held an armed demand with `MLN_FRAME_DEMAND_WAIT_FOR_UPDATE`. A demand armed before the last resize had rendered the final size's update into a frame that the port discarded, because the resize had reset the slots; the next demand then waited for an update that an idle map doesn't publish. Before #760 a resize set `render_pending_`, which forced a render. The port now makes the demand after a discarded result render unconditionally, and the test passes on the simulator (601 resizes, 576 frames rendered, final size displayed). The macOS run passed only by timing. A demand flag such as "render even if this update was rendered before into a target that was replaced" would make this explicit, but the host-side fix is simple, so it isn't an ask.

At `2c124a5`, with the fixes above, `map_texture_test.dart` passes on the Pixel (28 passed, 2 skipped), the iOS simulator (29 passed, 1 skipped) and macOS (29 passed, 1 skipped); macOS needed no lost-target recovery.

The benchmarks on the Mac and the iPhone ran at `c8a0321` and the Pixel's at `4173c68`, before these fixes. The fixes change only what happens after a resize, a window replacement or a failed render, not a steady pan, so the measurements weren't repeated.

## Conclusions

For each question of the design, the answer, whether it comes from #760 or from the port, and what a port that we would merge needs.

- **Q1. Display slots on Apple platforms.** From #760: a borrowed ring holds at most 3 textures, and a replacement resets the rendered update on purpose, so mapigrade's 4 slots render an idle map without end. With the local patch of D173 the slots work and the measurements match the released FFI. A merged port needs #760 to take ask 1 in some form (task 7.3); otherwise it falls back to a ring of 3 textures and 3 display slots, which changes D122 and wasn't measured.
- **Q2. Latency from camera to frame.** From #760's asynchronous camera command, made visible by how the port orders its calls: 3.5 ms more on the iPhone, 0.3 ms on the Mac and the Pixel. Waiting for the camera command's completion before servicing removes it. A merged port needs that wait, or better asks 2 and 3, and the iPhone alignment benchmark with the wait (not yet run) to confirm that the extra frame of lag goes away.
- **Q3. Synchronous execution.** Not needed, if #760 takes asks 1 and 2. Everything else the port needed was host-side work, though more than before (Complexity).
- **Q4. Glyph load failures.** Works unchanged with a caller-graphics-thread driver. A merged port that kept this driver needs nothing; a core-worker driver would need a map event for glyph failures.
- **Q5. Android hook before the swap.** Works, because the port sets the frame id before every service call, including those in its wait loops. Not promised by #760 (ask 5). A merged port needs that rule documented in its design.
- **Q6. Lifecycle.** From #760: ordered replacements, operations with completions, a lost target that only a new session leaves, and memory reduction that doesn't run while paused. From the port: discarding a stale frame left an idle map waiting (fixed). A merged port needs the waits and the re-attachment that the branch has, a decision about memory reduction while paused (ask 4), and tests for target loss and recovery.
- **Q7. Other API.** Native header rules, events through a handler, and operations with completions fit mapigrade without problems; the header rules are simpler than the adapter they replace.

Shortcuts of the branch (D172) that a merged port must undo:

- The native tests in `test/native/` fake the released C API and don't build. They need a fake of #760's asynchronous API (completions, frame demands, frame results, wakes), which is at least as large as the current 475 lines of `fake_mln.*`.
- The specs of `map-texture` describe the synchronous model in places (camera applied before render, `render_update`), and need updates; the design decisions D1, D2, D20, D122, D125 and D131 need revising.
- The branch carries temporary diagnostics: the `MLN760_STAGES` latency stages, the `MLN760_STALL` dump, the `MLN760_ACQUIRE` count and the `MLN760_WAIT_CAMERA` switch. A merged port keeps none of them; the camera wait becomes unconditional or is replaced by ask 2.
- `scripts/build_maplibre_ffi.sh` must delete the FFI's install directory before a build (Build).

## Feedback for #760

Issue drafts and the stacked pull request go here for review before anything is posted.

### Draft question for the maintainers (task 7.3, not posted)

> **Same-size borrowed texture replacement: opt-in to keep the rendered update?**
>
> mapigrade shows a map in Flutter through 4 display slots on macOS and iOS: Flutter displays the newest finished frame while the map renders the next one into a free slot. The slots are caller-owned Metal textures. On #760 at `3b56ef916` a borrowed ring holds at most 3 textures, so mapigrade attaches a ring of one texture and replaces it with the free slot's texture before each frame, with `mln_render_session_set_metal_borrowed_texture_target` and a caller-graphics-thread driver.
>
> Each replacement resets the session's record of the rendered update (`render_session_common.cpp`, `rendered_update_generation = 0`, `pending_changes = true`) and resumes demands that wait for an update. So a demand with `MLN_FRAME_DEMAND_IF_NEEDED | MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` renders after every replacement, and an idle map renders about 120 frames per second without end. maplibre-native-ffi#807 fixed the same behavior of the earlier `set_target`.
>
> We see that the reset is intended: `a_borrowed_retarget_renders_a_waiting_demand` tests it, for a host that reallocates its textures and wants the latest frame in the new texture at once. mapigrade needs the opposite, because it fills each texture only with its next frame. With a local patch that keeps the rendered update across a same-size borrowed replacement, the idle map stays idle and the frame rate, render time and overlay alignment on the Mac and an iPhone 15 Pro Max match the released FFI.
>
> Which would you prefer?
>
> 1. An opt-in on the replacement, for example a field of the borrowed texture descriptor, that keeps the rendered update when the extent and physical size don't change. The default and its test stay as they are.
> 2. Keeping the rendered update by default for a same-size replacement, with the current behavior as the opt-in.
> 3. A frame demand that names the ring slot to render into, with a ring of more than 3 textures, so that a host rotates slots without replacing textures.
>
> We're happy to open a stacked pull request against #760 for the one you prefer, with a C test next to the existing one.

1. Same-size replacement of a borrowed texture ring (Q1, D173): keep the record of the rendered update, as maplibre-native-ffi#807 did for the earlier `set_target`. Proposed as a stacked pull request with the patch above.
2. Report the render update generation of a map command in its completion, or in a way that can be compared with `mln_render_frame_result.map_update_generation` (Q2).
3. Run CPU-only driver work, such as `mln_render_session_reduce_memory_use`, without the GPU work queued with it, so that a paused caller-driver session can release memory (Q6).
4. Let a caller-driver host make the next render include a command it just submitted, for example a frame demand with a minimum render update generation (Q2, task 6.4). On the iPhone this is the whole difference between the port's camera latency (15 ms) and the baseline's (11 ms).
5. Make the per-frame hook before the swap explicit for surface targets, for example a frame token that the session attaches to the presented buffer (Q5).
6. Let a replacement recover a session whose target was lost, or document the recovery (Q6).

### Draft issues (task 7.2, not posted)

Ask 1 is the question of task 7.3 above. Asks 2 and 3 share one issue, which is also the issue on synchronous execution and frame latency promised in discussion #877.

#### Draft A: render the update that includes a command the host just submitted (asks 2 and 3)

> **Caller-graphics-thread driver: render the update that includes a just-submitted camera command**
>
> Following up on discussion #877: we ported mapigrade's render loop to #760 at `3b56ef916` with a caller-graphics-thread driver, to check whether it needs a synchronous executor. It mostly doesn't. One ordering question remains.
>
> mapigrade's map thread applies a predicted camera and renders the next frame right after. On #760 it submits `mln_map_update_camera` and then services the driver. On an iPhone 15 Pro Max the runtime thread applies the camera and publishes its render update in about 60 µs, but the service call that follows usually starts before that, renders the previous update, and the camera waits for the next render. The camera-to-frame latency rises from 11.4 ms (released FFI) to 15.0 ms, which in fast pans is one more 120 Hz frame of lag. On a Mac and a Pixel 4a (5G) the difference is about 0.3 ms.
>
> Waiting for the camera command's completion before servicing the driver brings the iPhone back to 11.0–11.3 ms, with no change in frame rate. That works, but it spins on a completion that runs on another thread. Would you consider one of these?
>
> 1. A frame demand that names a minimum render update generation, so that the demand waits until the update that includes the command is published.
> 2. A way to know that generation: the completion of a map command reports the map *snapshot* generation, while `mln_render_frame_result.map_update_generation` counts *render updates*, so a host can't compare them. Today we read `mln_map_get_snapshot` in the completion and take `latest_render_update_generation`, which can be later than the command's own update.
>
> With either, a caller-graphics-thread host gets the ordering that `jump_to` followed by `render_update` gave, without a separate synchronous executor. Measurements and the port are on mapigrade's branch `experiment-maplibre-pr-760-port`.

#### Draft B: release memory while a caller-driver session isn't serviced (ask 4)

> **`mln_render_session_reduce_memory_use` doesn't run while a caller-driver session is paused**
>
> mapigrade pauses rendering while an iOS app is in the background and releases the renderer's caches on a memory warning, which arrives at that time. With the released FFI, `mln_render_session_reduce_memory_use` ran at once. On #760 it is driver work, so with a caller-graphics-thread driver it runs only when the host services the driver. A paused host doesn't, because servicing would also run queued GPU work. Could CPU-only driver work, such as cache release, run without the GPU work queued with it, for example in a service call that skips frame demands?

#### Draft C: identify the frame a surface target presents (ask 5)

> **EGL surface target: tie a presented buffer to its frame**
>
> On Android, mapigrade renders through an EGL window surface on an ImageReader and needs to know which frame each image holds. It sets the frame id as `eglPresentationTimeANDROID` before the render. On #760 any service call can render an armed demand's frame, including one that services a target replacement, which resumes waiting demands. mapigrade now sets the id before every service call, and in practice no service call rendered more than one frame, but the C API doesn't promise either. A frame token that the session attaches to the presented buffer, or a host callback right before the swap, would make this explicit.

#### Draft D: recover a lost surface target (ask 6)

> **A surface session whose target is lost can't be recovered by a replacement**
>
> With the released FFI, a failed render on Android was reported, and the next `set_target` recovered. On #760 a failed render puts the session into `MLN_RENDER_SESSION_STATE_TARGET_LOST`; frame requests then return `MLN_STATUS_INVALID_STATE` because they require the attached state, and `mln_render_session_set_opengl_surface_target` doesn't restore it. On a Pixel 4a (5G) this happened several times while mapigrade replaced its ImageReader during fast resizes. mapigrade now detaches the session and attaches a new one, which rebuilds the renderer and its caches. Should a replacement of the surface bring a lost session back to attached, or is detaching and attaching again the intended recovery? Either way, documenting it in `render_session.h` would help.
