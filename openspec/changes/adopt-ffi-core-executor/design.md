## Context

See proposal.md, "Why", for the motivation.

On `main`, each map has a map thread that mapigrade owns (designs D1 and D2). It pumps the runtime, applies the camera with `mln_map_jump_to`, makes a free display slot the session's target, and renders with `mln_render_session_render_update`, all synchronously and in that order. #760 replaces these calls; the table in design.md of the change `experiment-maplibre-pr-760-port` maps each call to its replacement.

The experiment `experiment-maplibre-pr-760-port` (branch of the same name, draft PR greensopinion/mapigrade#5, findings in `docs/maplibre-pr-760-port-findings.md` on that branch at commit `a7be839`) ported mapigrade to #760 at FFI `main` (`6d9058bf6`) and passed `map_texture_test.dart` and `map_layer_test.dart` on macOS, the iOS simulator and the Pixel 4a (5G), and `engines_test.dart` on macOS. The decisions below are those of the experiment that held, restated as final ones; each cites the experiment's decision or finding. The experiment's code is the reference for the implementation, not its starting point (D179).

The FFI C API changed only in comments and by one added field (`pixel_format`) between `6d9058bf6` and FFI `main` on 2026-10-22, so the snapshot that this change builds against (D186) serves the same API as the experiment's pin.

## Goals / Non-Goals

**Goals:**
- Native code on #760's API that a merge to `main` can keep: no temporary diagnostics, no experiment switches, and native tests that build.
- Behavior as the specs state it, with the modifications of this change's delta specs.

**Non-Goals:**
- The pacing of rendering ahead (designs D19 and D124). Renders that cost between 3/4 of and one refresh interval miss refreshes on `main` today, on the Mac at 120 Hz and on the iPhone 13 at 60 Hz; a separate change addresses it.
- Placing the map thread on the performance cores on iOS (D188).
- Pinning the FFI release; a follow-up change does it when the release exists.
- Requests to #760 that the experiment drafted (CPU-only driver work, an explicit hook before a surface swap, recovery of a lost surface target). This change works with #760 as it is.

## Decisions

### D179. A new change from `main`, with the experiment as the reference

The change starts from `main` and ports each part of the native code again, with the experiment's code as the reference. The experiment's branch carries code written to measure: about 20 `MLN760_*` diagnostic sites, a stall dump to a file, five experiment switches, and native tests that don't build. Removing those from the branch and auditing what remains would cost about as much as porting again, and would bring the experiment's history to `main`.

The findings document is the evidence that this design cites. It moves to `main` as `docs/maplibre-pr-760-port-findings.md`; the result lines in `docs/maplibre-pr-760-port-results/` stay on the branch, which stays until this change is archived.

Alternatives:
- Merge the experiment's branch after a cleanup. Faster to start, but `main` gets 33 experiment commits and 77 result files, and every diagnostic must be found and removed by hand.
- Leave the findings on the branch only. The design's citations then depend on the branch, which a later cleanup could delete.

### D180. The map thread drives the session with the caller-graphics-thread driver

The map thread stays (D1, D2). It creates the runtime and the map, and attaches the session with `MLN_RENDER_DRIVER_CALLER_GRAPHICS_THREAD`, so that rendering, target replacement and the platform's work before a render run on a thread that mapigrade owns. The thread waits on its command queue, which the session's `frame_wake` and `driver_work_wake`, the completions, and Dart's commands signal. Each render is a frame demand, a service call and a drain of the frame results (experiment D167). Glyph load failures keep their attribution to a map, because the renderer reports them on the map thread (findings Q4).

Alternatives:
- The core-worker driver. The session would render on an FFI thread; mapigrade couldn't set a frame's presentation time on Android before the swap or replace a target on its own thread, and log records would lose their map (findings Q3, Q4).

### D181. Cameras are commands, and the map thread waits for each one before it renders

The map thread applies each camera with `mln_map_update_camera`, records the camera's `seq` with the `render_update_generation` that the command's completion reports (FFI #906), and gives a rendered frame the `seq` of the newest camera whose generation is at most the frame's `map_update_generation` (experiment D169, D175). Before it services the session, the map thread waits on its command queue until the completion of every camera command it submitted has run; the completion signals the queue, a dispose ends the wait, and the wait has no deadline, because every command completes (experiment D176).

Without the wait, the service call that followed a camera command rendered the previous camera on the iPhone, which cost 3.5 ms of camera latency and one more frame of lag in fast pans. With it, the camera latency on the iPhone 15 Pro Max and the iPhone 13 is that of the released FFI or lower (findings Q2).

Alternatives:
- A deadline for the wait. A camera that misses it renders a frame at the previous camera, which costs a frame of lag; every command completes, so the deadline guards against nothing that occurs.
- Read the map's snapshot in the completion, as the experiment did before #906. The snapshot can already include a later command's update.

### D182. Apple slots: one borrowed ring of the 4 display buffers, with acquire and release

A copy-free map attaches a borrowed Metal ring of the current buffer set's 4 textures, in slot order, so that ring slot n is display slot n (experiment D174). After each rendered result the map thread acquires the frame, reads its slot with `mln_acquired_frame_get_metal_texture`, and publishes the frame into that display slot. It holds the acquired frame while the display slot isn't free, releases the frames of freed slots before it requests the next frame, and releases at once a rendered frame that it doesn't publish. The session renders only into slots that no acquired frame holds, so the session, not mapigrade, chooses the slot of each frame. A release passes `mln_gpu_sync_default()`, which frees the slot at once, because Flutter samples the IOSurface without a fence (findings Q1).

`maxSlotsInUse` in the internal statistics counts a slot from the acquisition of its frame, so it no longer includes the slot that the session renders into. The statistic stays internal; the alignment benchmark reports it as before.

The map with the copy keeps a borrowed ring of its one render texture and copies each frame into a free display buffer, as on `main`.

Alternatives:
- A ring of one texture replaced before each frame (experiment D168). It made an idle map render without end unless FFI was patched, and FFI's maintainer considers a replacement before every frame not the intended use (findings Q1, D173).
- A ring of 3 textures and 3 display slots. FFI #905 raised the ring limit to 8, so the 4 slots of D122 stay.

### D183. A resize ends outstanding demands, then releases the frames, then replaces the ring

On a resize, when a frame demand is outstanding, the map thread ends it with `mln_render_session_barrier` and services the session until the barrier completes. It then releases every acquired frame, which #760 requires before a replacement, swaps the buffer sets (the outgoing set's chosen buffer stays as the fallback of D126), and replaces the ring with `mln_render_session_set_metal_borrowed_texture_target`, servicing the session until the replacement completes. It requests no frame from the barrier to the replacement. Without the barrier, a demand armed before the resize rendered into freed textures and crashed in MapLibre's render pass; with it, no acquired frame was in a replaced set in 834 frames over the resize tests (experiment D174, findings Q1).

### D184. Android keeps its surface target and recovers a lost target with a new session

The session attaches to the EGL window surface and switches surfaces with `mln_render_session_set_opengl_surface_target` on replacement and park, as on `main` (experiment D170). The map thread sets the presentation time of the next frame and applies the scissor workaround before every service call, including the service calls in its waits, because any service call can present the armed frame (findings Q5). When the session reports `MLN_RENDER_SESSION_STATE_TARGET_LOST`, the map thread detaches it and attaches a new one to the current surface, because no replacement leaves that state (findings Q6).

### D185. Lifecycle under ordered operations

- Pausing (D13): the map thread doesn't service the session while paused, so no GPU work is submitted; demands and replacements wait in the session.
- Memory reduction: `mln_render_session_reduce_memory_use` is driver work, so while paused it waits and runs in the first service call after rendering resumes, before that call's render. The `map-texture` delta spec states this.
- Teardown: the map thread releases its acquired frames, detaches the session and services it until the detach completes, then releases the map and the runtime and waits for each completion, so that no completion or event callback reaches the map's object afterwards.
- Every operation that the map thread waits for is serviced in a loop that also sets the Android frame's presentation time (D184).

Alternatives:
- Service the session while paused to run memory reduction at once. The service call would also run a queued render, which breaks "No rendering while the application is in the background".

### D186. Snapshot mode for the FFI until its release

`maplibre_ffi.lock` states either a release, as today, or the snapshot (`MAPLIBRE_FFI_VERSION=snapshot`). In snapshot mode:

- iOS and macOS: `scripts/fetch_ffi_snapshot.sh` downloads `MaplibreNativeC.xcframework.zip` of FFI's `unstable-native-snapshot` release into `third_party/` and makes `Frameworks/MaplibreNativeC.xcframework` resolve to it, so `Package.swift` uses its local-path binary target, which takes no checksum. The script prints the commit that the snapshot release states.
- Android: `build.gradle.kts` depends on `org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android:0.1.0-SNAPSHOT` from `https://central.sonatype.com/repository/maven-snapshots/`, and states the snapshot in its output.
- The package's `pubspec.yaml` sets `publish_to: none`, so `flutter pub publish` refuses. `scripts/consumer_build.sh` removes `publish_to` in a temporary copy before the dry run that lists the files, and runs the snapshot fetch into its copy of the package for the iOS and macOS builds.
- `ffi_pins_test.dart` checks, in snapshot mode, that the lock, `Package.swift`'s remote target and `publish_to: none` agree, in place of the release pins.
- The notices stay those of the last release, and their comparison test is skipped.
- A local FFI build (`scripts/build_maplibre_ffi.sh`) still takes precedence on every platform it installed.

The follow-up change that pins the release removes the snapshot from the lock, `publish_to: none` from the pubspec, and the snapshot repository from `build.gradle.kts`.

Alternatives:
- Build the FFI from source for `main` and in CI. Every build of `main` would need mise, the NDK and a cold MapLibre build.
- Mirror one snapshot's artifacts at a fixed URL with a checksum. Reproducible, but mapigrade would host FFI binaries, and the pin is temporary.
- Point `Package.swift` at the snapshot URL with a checksum. FFI republishes the snapshot about daily under the same URL, so the checksum breaks every build until a commit updates it.

### D187. Native tests run against a headless FFI target, or a fake of the asynchronous API

The native tests in `test/native/` fake the synchronous API (`fake_mln.*`) and test the core's map thread, commands and buffer states. They move to the real FFI with a headless target, if one runs on the macOS host and in CI: a session-owned Metal texture ring on macOS gives real completions, frame demands and frame results without a Flutter engine. If no headless target serves the tests (for example, CI has no GPU for it), the tests move to a fake of the asynchronous API: completions, frame demands, frame results and wakes. The first task decides, from a test of the map thread's create, render and dispose against the headless target.

Alternatives:
- Rewrite the fake first. It needs a model of #760's ordering of completions and frame results, which the real FFI provides.

### D188. iOS keeps the map thread's default placement

On the iPhone 15 Pro Max the port's service call took about 0.3 ms longer than `render_update` with the released FFI, and the displayed map frame rate was 2% to 3% lower on cable power, because iOS runs the map thread on the efficiency cores once no per-frame allocation happens (findings, "The iPhone's longer service call on FFI main"). On the iPhone 13 the frame rate was at most 2% lower, and renders and camera latency were faster than with the released FFI. The change accepts this and documents it in `docs/benchmarks.md`. It sets no QoS class, work interval or thread policy on the map thread: the QoS class and a time-constraint policy didn't change the placement, and the only public way to create a work interval is an audio API (findings, tasks 8.11 and 8.12 of the experiment).

### D189. Statistics and benchmarks

The camera-to-frame latency that the experiment added to the internal statistics (`map_texture_stats`, experiment D171) and to the benchmarks' output stays: it measures the effect of D181. The `MLN760_*` diagnostics, the stall dump and the experiment switches don't come to `main`.

## Risks / Trade-offs

- [A daily snapshot breaks `main`'s build with an FFI API change] → FFI is prerelease and makes breaking changes on purpose. The snapshot fetch prints the snapshot's commit, so a break can be traced to an FFI commit; the follow-up change ends snapshot mode at the release.
- [A failed snapshot run leaves the Apple and Android artifacts at different commits] → The build outputs state the snapshot; a mismatch shows as a difference between platforms that the commit lines explain.
- [Snapshot mode leaves the notices of an older release in the package] → The package can't be published in snapshot mode, so no application ships them.
- [A headless target doesn't run in CI] → D187 falls back to a fake; the first task decides before the tests are written.
- [Older iOS devices than the iPhone 13 lose more frame rate to the map thread's placement] → Measured on two devices only; `docs/benchmarks.md` states the devices, and a later change can revisit D188 with data from another device.
- [The FFI release changes the API from the snapshot] → The follow-up change ports the difference; the API changed only in comments between `6d9058bf6` and the snapshot of 2026-10-22.

## Migration Plan

1. Merge this change to `main` in snapshot mode. `main` can't be published until step 2; version 0.0.1 is already published.
2. When an FFI release includes #760, a follow-up change pins it, which ends snapshot mode, and `support-ios-15-0` follows it or joins it.
3. Rollback: revert the merge; `main` returns to the released FFI 0.202610.1 and the synchronous API.
