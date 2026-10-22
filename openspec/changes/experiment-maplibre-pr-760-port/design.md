## Context

See proposal.md, "Why", for the motivation and discussion #877.

Today each map has a map thread that mapigrade owns (design D1 and D2). On that thread, in this order, `MapTexture` pumps the runtime with `mln_runtime_pump`, applies the predicted camera with `mln_map_jump_to` and records its `seq` (D125), makes a free display slot the session's target, renders with `mln_render_session_render_update`, and reads the frame's camera with `mln_render_session_projection_create`. Because all of this runs on one thread in order, the camera that the map thread applied is the camera of the next frame.

- macOS and iOS: a borrowed Metal texture target with 4 display slots, one Flutter texture each (D122). A copy-free map makes the free slot's texture the target with `mln_metal_borrowed_texture_set_target` before each render (D20). The copy path (D3b) renders into one texture and copies it into a slot.
- Android: an OpenGL surface target on an EGL window surface on the Surface of an ImageReader with 6 images (D130 to D135). The session switches surfaces only when the window is replaced or the map parks on a pbuffer (`SwitchSession` in `map_texture_android.cpp`), not per frame. Before each render, `WillRender` sets the frame id as the presentation time and works around the FFI's assumed scissor state.
- Glyph load failures reach Dart through the process-global log callback, which attributes a record to the map whose thread logged it, through a `thread_local` owner.
- `test/native/fake_mln.cpp` fakes the current C API for the native tests.

#760 at commit `3b56ef916` (2026-10-21) changes this:

```
+--------------------------------+          +---------------------------------+
| mapigrade map thread           |          | FFI core worker (owns the map)  |
| (caller-graphics-thread driver)|          |                                 |
|                                |  command |                                 |
|  mln_map_update_camera --------+--------->|  applies the camera, publishes  |
|                                |          |  a render update (generation N) |
|  driver_work_wake <------------+----------+                                 |
|  request_frame(token)          |          +---------------------------------+
|  service_driver_work  (renders on this thread)
|  drain_frame_results
|    -> {token, map_update_generation, view}
|    -> mln_map_projection_create(view) -> the frame's camera
+--------------------------------+
```

| Today | #760 |
|---|---|
| `mln_runtime_pump`, runtime wake source | The core worker runs the runtime; `frame_wake` and `driver_work_wake` in `mln_render_session_attach_options` |
| `mln_map_create` | `mln_runtime_create_map` |
| `mln_map_jump_to` | `mln_map_update_camera`, a command with a completion that reports the snapshot generation it published |
| `mln_render_session_render_update` | `mln_render_session_request_frame`, `mln_render_session_service_driver_work`, `mln_render_session_drain_frame_results` |
| `mln_render_session_projection_create` | `mln_map_projection_create` from `mln_render_frame_result.view` |
| `mln_runtime_drain_events` | `mln_runtime_set_event_handler` (callback or delivery queue) |
| `mln_adapter_http_header_*` | `mln_http_header_rule` in `runtime.h` |
| `mln_runtime_set_maximum_ambient_cache_size_start` | `mln_runtime_set_maximum_ambient_cache_size` |
| `mln_metal_borrowed_texture_set_target` | `mln_render_session_set_metal_borrowed_texture_target`: an ordered operation with a completion; it fails while a frame is acquired, and frames published before it can't be acquired. A borrowed ring has 1 to 3 textures, and a replacement keeps the count. #905 raised the maximum to 8 (`MLN_TEXTURE_RING_MAX_DEPTH`). |
| `mln_opengl_surface_set_target` | `mln_render_session_set_opengl_surface_target`, an ordered operation with a completion |
| `mln_render_session_reduce_memory_use` | the same name, an operation with a completion |
| `mln_render_session_destroy` | `detach`, `abandon`, `release` and `dispose` |

## Goals / Non-Goals

**Goals:**
- Answer the questions in "Questions the experiment answers" with evidence from a running port, and record the answers in `docs/maplibre-pr-760-port-findings.md`.
- Keep mapigrade's pipeline: Flutter chooses the newest finished frame from the display slots (D139, D140), and the layer draws its children at the camera of the displayed frame (D122 to D129).
- Measure the port against the baseline commit (D171) with the existing benchmarks.
- Write feedback for #760 that we can post while the PR is open.

**Non-Goals:**
- A port that we would merge. The branch takes the shortcuts in D172.
- Changes to the Dart code or the public API of `flutter_mapigrade`.
- Using #760's generated Dart bindings. mapigrade keeps calling the C API from its own native code.
- Other #760 targets (Vulkan, WebGPU, the core-worker driver), except where a finding needs a comparison.

## Questions the experiment answers

The questions are ordered by how much an answer could change #760's API, which matters only until #760 merges.

- **Q1. Display slots on Apple platforms.** Can mapigrade keep 4 copy-free display slots with a borrowed ring of at most 3 textures? See D168.
- **Q2. Latency from camera to frame.** How much later does a predicted camera reach a rendered frame when the camera goes to the core worker as a command, compared with `jump_to` on the map thread? Does camera prediction (D125 and the camera-prediction change) still reduce the lag?
- **Q3. Synchronous execution.** Given Q1 and Q2, does mapigrade need a synchronous or immediate executor, or does the core executor with a caller-graphics-thread driver serve it?
- **Q4. Glyph load failures.** Log records in #760 carry no map identity, and the core worker, not the map thread, emits them. How can mapigrade attribute a glyph load failure to a map?
- **Q5. Android hook before the swap.** Can mapigrade set the presentation time of each frame and apply the scissor workaround immediately before the session swaps buffers?
- **Q6. Lifecycle.** Do detach, abandon and dispose support pausing (D13), parking on a pbuffer, resizing (D126) and disposing an engine's maps (D157)?
- **Q7. Everything else.** HTTP header rules, the cache size, events and style loading.

## Decisions

### D166. The branch builds #760 from source at a pinned commit

`maplibre_ffi.lock` on the branch sets `MAPLIBRE_FFI_COMMIT` to `3b56ef916` and `MAPLIBRE_FFI_REPO` to the upstream repository, the build applies `scripts/patches/maplibre-native-ffi-760-same-size-retarget.patch` on top (D173), and `scripts/build_maplibre_ffi.sh` builds the presets `macos-arm64-metal`, `ios-arm64-metal`, `ios-simulator-arm64-metal` and `android-arm64-egl`, which #760 still has. `Package.swift` uses the local xcframework. We move the pin only on purpose, and record each move and the reason in the findings document, because #760 changes daily.

After #760 merged, the pin moves to FFI `main` at `6d9058bf6` (#760, #905 and #906), and the branch carries no local patch.

Alternatives:
- Track the PR's head. Every rebuild could change the API under the port, and measurements would not be comparable.

### D167. One map thread as the caller-graphics-thread driver

The map thread stays. It creates the runtime and map, and attaches the session with `MLN_RENDER_DRIVER_CALLER_GRAPHICS_THREAD`, so that rendering, target replacement and the platform's work before a render stay on a thread that mapigrade owns. The thread waits on its command queue, which `driver_work_wake`, `frame_wake` and Dart's commands signal, in place of `mln_runtime_pump`. Each render is: request a frame, service the driver, drain the frame results.

Alternatives:
- The core-worker driver. The session would render on an FFI thread, and mapigrade couldn't change the Metal target or set the Android presentation time per frame on its own thread. It would answer Q3 only for a model we can't use.

### D168. Apple slots: a borrowed ring of one texture, replaced before each render

D174 replaces this decision on FFI `main`. The measurements at `3b56ef916` used it.

The session attaches a borrowed Metal ring of one texture. Before each render, the map thread replaces it with the free display slot's texture with `mln_render_session_set_metal_borrowed_texture_target`, then requests a frame and services the driver, which runs the replacement and the render in that order. The display slots, their Flutter textures and Dart's choice of a frame don't change (D122, D139). The experiment measures the cost of a replacement per frame and finds out whether a frame that the host never acquires keeps its slot from being reused.

Alternatives:
- A borrowed ring of 3 textures, with 3 display slots. Each displayed frame is acquired and released when Flutter no longer displays it. Flutter samples the IOSurface without a fence that the release can wait on. It changes D122 from 4 slots to 3. We try it if D168 fails.
- The copy path (D3b): a ring owned by the session and a GPU copy into 4 slots. It works within the limit, but costs the copy that copy-free maps removed (benchmarks.md, "Copy-free with the upstream FFI fix").

### D173. A local patch keeps the rendered update across a same-size replacement

D174 replaces this decision on FFI `main`. In discussion #877, the maintainer of #760 considered a replacement before every frame "a hack, not the intended use", and didn't consider the reset a regression, so we dropped the patch.

Task 3.4 showed that D168 alone renders without end: #760's target replacement resets the session's record of the rendered update and resumes waiting demands, so each replacement makes the next demand render (findings Q1). maplibre-native-ffi#807 fixed the same behavior of the earlier `set_target`. The branch carries a patch to #760 (`scripts/patches/maplibre-native-ffi-760-same-size-retarget.patch`) with the same semantic: a replacement of a borrowed texture ring with the same extent and physical size keeps `rendered_update_generation` and `pending_changes`, marks the new target as holding the rendered update, and doesn't resume waiting demands. The generation still increases, so frames published before the replacement still can't be acquired.

Every measurement of the copy-free path on the branch is of #760 with this patch. The patch is the first change we propose for #760. Because #760 resets the rendered update on purpose (findings Q1), we first ask its maintainers whether they prefer an opt-in or a changed default (task 7.3), and then prepare a stacked pull request (task 7.4).

Alternatives:
- A ring of 3 textures and 3 display slots, which #760 supports without a patch. It changes D122 and measures the ring limit instead; kept as the fallback if #760 rejects the patch.
- Benchmarking D168 without the patch. Phases where the map should be idle would render continuously, so the numbers would describe a defect, not #760.

### D169. The frame's camera comes from the frame result

D175 replaces the snapshot read of this decision on FFI `main`.

After `drain_frame_results`, each result with `MLN_RENDER_RESULT_RENDERED` gives the frame's camera through `mln_map_projection_create(result.view)` and `mln_map_projection_get_camera`. To keep `FrameInfo.seq` (D125), the map thread records the generation that each `update_camera` completion reports together with the camera's `seq`, and a frame's `seq` is that of the newest camera whose generation is at most the frame's `map_update_generation`. The demand uses `MLN_FRAME_DEMAND_IF_NEEDED | MLN_FRAME_DEMAND_WAIT_FOR_UPDATE`, so that a camera that reaches the core worker after the request is still rendered without another round trip.

Alternatives:
- Drop `seq` and match frames by camera. That would change the Dart code, which this experiment leaves alone.

### D174. Apple slots: a borrowed ring of 4 textures with acquire and release

The session attaches a borrowed Metal ring of the current set's 4 buffers, in slot order, so ring slot n is display slot n. After each result with `MLN_RENDER_RESULT_RENDERED`, the map thread acquires the frame with `mln_render_session_acquire_frame`, and the frame's `slot` is the display slot it publishes into. The map thread holds the acquired frame while the display slot holds the frame, and releases it with `mln_acquired_frame_release` when the slot is freed. It releases a rendered frame that it doesn't publish at once. Because the session renders only into a slot that no acquired frame holds, the session chooses the slot, not mapigrade. The map thread still requests a frame only when a display slot is free. The release passes no consumer synchronization, as the copy-free path does today, because Flutter samples the IOSurface without a fence.

On a resize (D126), #760 refuses a replacement while any frame is acquired. A demand armed before the resize could render into the old set after mapigrade frees its buffers, so when a demand is outstanding the map thread first ends it with `mln_render_session_barrier` and services the session until the barrier completes. It then releases every acquired frame, frees the old set except the fallback buffer, and replaces the ring with the new set with `mln_render_session_set_metal_borrowed_texture_target`. It requests no frame from the barrier to the replacement. After the replacement the session never renders into the old set, so the fallback buffer that Flutter still displays stays valid; mapigrade keeps it allocated as before.

Alternatives:
- A borrowed ring of 3 textures and 3 display slots. It changes D122.
- The copy path (D3b). It costs the copy that copy-free maps removed.

### D175. A frame's `seq` comes from #906's render update generation

The camera completion records `mln_completion_result.render_update_generation` with the camera's `seq`, and no longer reads `mln_map_get_snapshot`. A snapshot read after the completion could return a later command's update, so the recorded generation could be too new; #906 reports the update that includes the command. A frame's `seq` is still that of the newest camera whose generation is at most the frame's `map_update_generation` (D169).

### D176. The map thread waits for the camera's completion before it requests a frame

After `mln_map_update_camera`, the map thread requests no frame until the camera's completion has run. It waits on its command queue as it does for other work, and the completion signals the queue. The wait has no deadline: every command completes with a terminal status, and stop and dispose also signal the queue. The switch `MLN760_WAIT_CAMERA` and its yield loop are removed.

Task 6.4 found that the iPhone's extra camera latency (15.0 ms against 11.4 ms) came from the port's ordering: it rendered before the camera command's update was published. Waiting for the completion with `MLN760_WAIT_CAMERA=1` gave 11.0 to 11.3 ms.

Alternatives:
- A deadline, for example one display interval. A late camera would then render a frame at the previous camera, which the frame's `seq` reports correctly, but which adds a frame of lag.

### D170. Android keeps one window surface and switches it only on replacement and park

The session attaches to the EGL window surface with `mln_map_attach_opengl_surface` and a dedicated context, and `SwitchSession` calls `mln_render_session_set_opengl_surface_target`. The per-frame work of `WillRender` runs before `service_driver_work`, which is correct only if one service call renders at most one frame. The experiment checks this and records whether #760 needs a hook before the swap (Q5).

### D171. Camera-to-frame latency is measured on the map thread

The map thread records, for each `seq`, when `SetCamera` queued it and when the first frame with that `seq` finished, and reports the difference in `map_texture_stats`. The statistic is the branch's first commit, which still uses the released FFI, so that commit is the baseline that the port is measured against. The alignment benchmark with `ALIGNMENT_CHILDREN=1` reports the lag that results from it. Together they answer Q2.

### D172. Deliberate shortcuts

The branch:
- doesn't build or update the native tests in `test/native/`;
- leaves the specs, the README and `docs/` other than the findings document unchanged;
- doesn't keep the copy path (D3b) unless D168 fails;
- keeps the diagnostics `MLN760_STAGES`, `MLN760_STALL`, `MLN760_ACQUIRE` and `MLN760_RECOVERED` on FFI `main`.

iOS isn't a shortcut. It shares the Metal target with macOS, so it needs no port of its own, but phones are mapigrade's main platforms, and the iPhone's thermal limits and 120 Hz frame budget (a `render_update` of about 8.2 ms against an 8.3 ms refresh interval) show per-frame overhead that the Mac's headroom hides. The branch measures it on the iPhone as well as on the Pixel.

For each shortcut, the findings document states what the real port would need.

### D177. Experiment: the map thread joins a work interval on Apple platforms

Task 8.10 found that iOS keeps the port's map thread on the efficiency cores once no per-frame allocation happens, and that `QOS_CLASS_USER_INTERACTIVE` doesn't change that. A work interval tells the system the deadline of each cycle of a thread's work. The only public way for an app to create an interval workgroup is `AudioWorkIntervalCreate` (AudioToolbox, iOS 14); `<os/workgroup_interval.h>` says that interval workgroups are only for audio workloads so far, and AudioToolbox describes them for threads with real-time priority. With `MLN760_WORKGROUP=1`, the map thread creates a work interval with `AudioWorkIntervalCreate` on `OS_CLOCK_MACH_ABSOLUTE_TIME`, joins it, and brackets each service call that renders with `os_workgroup_interval_start` and `os_workgroup_interval_finish`, with the end of the display refresh interval as the deadline. The experiment measures whether the map thread then runs on the performance cores, and the frame rate; it doesn't decide whether a merged port may use an audio API for rendering.

Alternatives:
- A time-constraint (real-time) thread policy (`THREAD_TIME_CONSTRAINT_POLICY`). It is likely to place the thread on the performance cores, but the system demotes a real-time thread that exceeds its computation budget, and a render can take longer than a refresh interval. Tried only if the work interval doesn't change the placement.
- An allocation per frame, as the released FFI's `set_target` did. It keeps the thread on the performance cores by a side effect.

## Risks / Trade-offs

- [A demand renders into a released slot of the old set before the replacement of D174 runs] → The barrier of D174 ends an outstanding demand before the release, and the map thread requests no frame between the release and the replacement; task 8.3 checks that no frame of the old set is rendered after a resize starts. Without the barrier, the first run of task 8.2 crashed in MapLibre's render pass, in a texture of the freed set.
- [#760 doesn't build for mapigrade's presets at the pinned commit] → Record the failure as a finding, and move the pin or patch locally under `scripts/patches/`, recording which.
- [A replacement per frame (D168) is refused or slow] → Try the ring of 3 textures, then the copy path, and record the numbers of each.
- [Results on the branch reflect the experiment's shortcuts, not #760] → For each finding, state whether it comes from #760 or from the port.
- [#760 changes after we post feedback] → Name the commit in every finding and issue draft.
- [Without native tests, regressions in the port go unnoticed] → Run the integration tests in `packages/test_harness` on each platform that the branch ports.

## Open Questions

- Whether `MLN_RUNTIME_EVENT_MAP_TILE_ACTION` or a resource transform can report glyph load failures per map (Q4).
- Whether a borrowed Metal ring renders into a slot whose frame the host never acquired (D168), which only the code or a test can answer.
