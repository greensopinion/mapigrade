## Context

See proposal.md, "Why", for the trace results that motivate this change.

Dart chooses frames in the build of `MapigradeLayer` (`map_texture_layer.dart`) and of `MapTextureView` when the view chooses its own slot. Both read `MapTextureController.readyFrame`, the frame of the last finished-frame report (`MAP_TEXTURE_EVENT_FRAME_READY`), and call `select(frame)`, which calls `map_texture_select(handle, slot, frame_id)`. The native side records the choice in `BufferState::Select` only if the slot still holds that frame; otherwise it returns `MAP_TEXTURE_NOT_SELECTED`, and Dart keeps the frame it chose before (design D123 of layer-children-alignment).

Finished-frame reports reach Dart through a `NativeCallable.listener`, as messages on the platform thread. On Android, Flutter runs the frame's build before a message that arrives shortly before the vsync, so Dart can build with a report that is one frame old. `BufferState` keeps at most one ready slot: publishing a frame frees the slot of an older ready frame (`Publish`, `PublishLocked`). Dart's choice runs on the platform thread, under the `BufferState` lock, in the same build that displays the slot's texture.

## Goals / Non-Goals

**Goals:**
- In each build, Dart chooses the frame that the map holds as finished at that time, not the frame of the last report Dart has handled.
- A choice can't be refused because a newer frame replaced the chosen one. Dart learns the camera of the chosen frame from the choice itself.
- macOS and iOS keep their benchmark results.

**Non-Goals:**
- Changing when the map renders, the release rules of held slots (D124, D133), or the slot counts.
- Changing the finished-frame and frame-displayed reports, which the spec requires and the metrics count.

## Decisions

### D139. `BufferState` chooses its ready slot

`BufferState` gets `SelectNewest(on_selected)`. Under the state lock, it finds the ready slot. If there is none, it records nothing and returns false. Otherwise it records the choice as `Select` does today: it marks the slot held, frees held slots by the `kLaterChoices` rule, and runs `on_selected(info)` under the lock, so the Android target pushes the slot's image and the Darwin target releases the resize fallback (D126) as they do now. It returns the slot and its `FrameInfo`.

A ready slot always holds a frame newer than every held slot, because a slot becomes held only through a choice and a ready frame is published after it. So "newest" needs no comparison of frame ids. Choosing again while the frame chosen last is still the newest finds no ready slot and returns false; Dart then keeps displaying the frame it chose before, as when `Select` is called with the slot chosen last today.

Alternatives:
- Keep `Select(index, frame_id)` and have Dart read the newest finished frame through a separate call first. The two calls aren't atomic, so the map could replace the frame between them, and the refusal would remain.
- Choose the newest frame, ready or queued, on Android. A queued frame's image hasn't arrived, so Flutter has nothing to display for it.

### D140. `map_texture_select_newest` replaces `map_texture_select`

The C ABI gets `int32_t map_texture_select_newest(int64_t handle, map_texture_frame* out)`. `map_texture_frame` holds the fields of a frame that `map_texture_event` already carries: frame id, slot, camera, physical size, scale factor and camera sequence number. The function returns `MAP_TEXTURE_OK` and fills `out` when it recorded a choice, `MAP_TEXTURE_NOT_SELECTED` when no frame is finished that Dart hasn't chosen, and the existing errors otherwise. On Android, a recorded choice still sends the frame-displayed report (D132). The function keeps the statistics that `Select` keeps (`presented_frames`, `pickup_wait_*`), and wakes the map thread as `Select` does when a render waits for a free slot (D124).

`map_texture_select` and `MAP_TEXTURE_NOT_SELECTED`'s meaning of "the slot no longer holds the frame" are removed. The C ABI is internal to the plugin, so no application sees the change.

Alternative: keep `map_texture_select` next to the new function. Nothing in the package would call it except tests, and two ways to choose a frame would need two sets of rules in the spec.

### D141. Dart chooses with `selectNewest()` in each build

`MapTextureController.select(frame)` becomes `FrameCamera? selectNewest()`. It returns the chosen frame, or null when nothing new was chosen; in both cases `selectedFrame` is the frame to display. The controller allocates one `map_texture_frame` when it is created and reuses it, so a choice allocates only the returned `FrameCamera`.

`MapigradeLayer` and `MapTextureView` call `selectNewest()` in each build, without first comparing `readyFrame` with `selectedFrame`. They keep listening to `readyFrames` and call `setState` on each report, so that a frame that finishes while nothing else changes still starts a build. A frame that finishes after a build started is chosen in the next build, which its report starts. `readyFrame` stays for tests.

The layer looks up the camera of the chosen frame in `_sentCameras` by the returned sequence number, as today. A frame rendered before the first `setCamera` keeps falling back to the live camera.

Alternative: choose in a `SchedulerBinding` frame callback instead of in build. The layer's children need the chosen frame's camera in the same build, so the choice has to happen there.

### D142. All platforms choose the same way

macOS and iOS use `selectNewest()` too, so Dart keeps no platform branch (D138 of android-layer-children-alignment). On macOS and iOS, finished-frame reports reach Dart through the same listener, so a build can also run with a report that is one frame old there; the change can only make Dart choose a newer frame than before, never an older one. Renders on macOS and iOS wait for Dart's choice (D124), and a choice in an earlier build starts the next render earlier.

The user decided on 2026-10-19 that if the benchmark shows a lower frame rate on iOS, we revisit this decision (see Risks).

Alternative: Android only, with `select(frame)` kept on macOS and iOS. Then the C ABI and the controller need both ways to choose, and the layer needs a platform branch.

### D143. Measurement, and the cause recorded in the documentation

The frame-rate benchmark runs 3 times on the Pixel 4a (5G), the Mac and the iPhone, before and after the change, with the setup in `docs/benchmarks.md`. On the Pixel, one more run records an atrace trace (`gfx`, `view`, profile build with `--ez trace-systrace true`), and the trace is checked for builds that keep the previous frame while a finished frame existed when the build started. The trace from 2026-10-19 predicted about 54 displayed map frames per second and a maximum displayed frame interval of about 35 ms.

The documentation that gives clock drift as the cause of the Android stutter (`docs/limitations.md`, `docs/benchmarks.md`, `docs/camera-alignment-options.md`, `docs/platform-view-comparison.md`) is corrected with the trace results and the new measurements. The trace results are recorded in `docs/benchmarks.md`. The explanation in D134 of the archived android-layer-children-alignment change stays as written; this decision supersedes it. `docs/limitations.md` no longer names `AChoreographer` pacing as the planned alternative.

## Risks / Trade-offs

- [The iOS frame rate decreases with the new choice, for example because choosing a frame earlier changes when renders wait (D124).] → The benchmark compares iOS before and after the change. If it decreases, we revisit D142 with the user; the fallback is D142's alternative.
- [Builds that run before the newest frame finishes still show the previous frame. The 2026-10-19 trace predicts about 54 of 58 frames per second on the Pixel, not 58.] → Accepted for this change. Delaying the render start (proposal, not in this change) could add about 3 frames per second, at about 8 ms of latency.
- [The prediction comes from a simulation that assumes the GPU timing stays the same.] → The Pixel benchmark and trace after the change measure it.
- [Dart reads the frame through FFI in every build.] → The call takes the `BufferState` lock once and copies one struct, as `map_texture_select` does today.

## Migration Plan

The public Dart API doesn't change. Rollback is a revert of the change.
