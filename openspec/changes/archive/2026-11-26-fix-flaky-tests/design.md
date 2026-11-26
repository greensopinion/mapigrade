## Context

See proposal.md for the three failures. The facts the design depends on:

- The map thread knows, at the end of each `RunOnce()` iteration, everything that decides whether another frame is due: the command queue, the pending camera, whether the last frame needed a repaint (`repaint_wanted_`), the generation of the last rendered update (`rendered_update_generation_`), and why `RenderWanted()` returns false.
- `mln_map_get_snapshot()` copies the map's latest published state on any thread. The snapshot reports `fully_loaded` (every requested style and tile resource has loaded), `transition_in_progress`, and `latest_render_update_generation`. A frame whose `map_update_generation` is at or past that value draws every change the snapshot observes.
- MapLibre emits its idle event only after a frame that is fully loaded, needs no repaint and isn't in a camera transition (maplibre-native `src/mln/map/map_impl.cpp`). That is the condition this change checks, but the idle event arrives on the runtime's event thread, so a test can't tell which frame it belongs to.
- `Settled()` is called 38 times from 30 test functions. 13 of those functions don't run `SurfaceDart`; with the check of D1, each of their maps also reaches rest, because it renders every pending update before it stops.
- A map adds about 12 threads. On an iPhone, threads the test doesn't control changed the process's count by −2 to +2 between runs; on Android the count drifted by 1.
- MapLibre's resource loader delivers a usable cached copy of a style and then requests the style from the network; a network response with data is parsed again and reports another style load (maplibre-native `platform/default/src/mln/storage/main_resource_loader.cpp`). `asset://` URLs go through the asset file source instead, with one response.

## Goals / Non-Goals

**Goals:**

- Make every wait in the native tests depend on a state the map thread reports, not on a period without frames.
- Make the engine test's thread count tolerate the drift of threads that neither MapLibre nor the plugin owns, and still detect a leaked map.
- Make the `onStyleLoaded` test load its style once, and state the reload behavior in the spec and the docs.

**Non-Goals:**

- Change when MapLibre reloads a style, or have the layer report only the first load of a style URL.
- Change the iPhone 13 failures caused by its 390-point width.

## Decisions

### D1. The map thread answers a rest probe

`MapTexture::AtRestForTesting()` queues a probe command and waits up to one second for the answer; `map_texture_at_rest_for_testing(handle)` exposes it to the tests. The map thread records the probe when it takes it from the queue, and answers at the end of that `RunOnce()` iteration, after it has applied every command it took, serviced the session and armed any frame demand. The map is at rest when:

- no command, camera, query, feature-state change or overlay change is queued or waiting for its completion;
- the snapshot reports `fully_loaded` and no `transition_in_progress`;
- `rendered_update_generation_` is at or past the snapshot's `latest_render_update_generation`, and the last frame didn't need a repaint.

Without new input, a map at rest renders no other frame. The probe doesn't change rendering: unlike a target task, it doesn't set `repaint_wanted_` or release queued frames.

Alternative considered: read the snapshot and the core's counters on the test thread. The map thread can take a command from the queue before it has applied it, so for a moment the queue is empty and the snapshot is unchanged, and the test would see a map at rest that isn't.

Alternative considered: wait for MapLibre's idle event. The test can't tell whether an idle event belongs to the last frame or to an earlier one.

Alternative considered: a third state, "blocked", for a map whose due frame waits for a resume, a slot or Dart's choice, and a second helper that accepts it. Every native test passed with the strict check, so we dropped both.

### D2. `Settled()` waits until the map is at rest

`Settled(handle, frames)` waits until the map has rendered `frames` frames, then probes until the map is at rest, and fails the test after 10 seconds.

A native test makes one render sleep 400 ms in the fake surface target and checks that `Settled()` returns after that frame. Without D1 the same test fails every time, as our experiment showed.

### D3. The engine test allows four more threads

The engine test expects at most four more threads after the engine is destroyed than before, on every platform. That is twice the drift we measured, and a third of the threads a leaked map leaves.

Alternative considered: count only MapLibre's and the plugin's threads, by name. MapLibre names its threads `org.maplibre.mbgl.<name>` on Darwin, and with the plugin's map thread named, the count was exact: 10 runs in a row on an iPhone gave the same numbers. It needed a Darwin hook that lists thread names, a Dart binding and the thread name, about 85 lines for one test, and on Android the names don't help, because threads that attach to the JVM are renamed `Thread-N`. We chose the margin.

### D4. The `onStyleLoaded` test loads an asset style

The test loads `asset://assets/polyline_style.json`, which the test harness already uses and which has only GeoJSON sources, and keeps its check that events after the load, such as the map becoming idle, don't call the handler. The scenario "Style loaded" in the `map-layer` spec and the documentation of `onStyleLoaded` state that the handler is called each time the map loads a style, which for a style URL can be twice: once from the cache and once from the network.

## Risks / Trade-offs

- [A test settles a map whose due frame waits for the test, for example while paused] → `Settled()` fails after 10 seconds instead of returning early, which shows the problem instead of hiding it. `RendersArePacedByRefreshInterval` did this once in 20 runs: it paces renders by a fake clock that only it advances, and when the style loaded after the first frame, the frame that draws the style waited for the clock. That test now advances its clock until the map is at rest, and then renders one more frame to start the interval it measures.
- [The probe's "at rest" misses a condition that later renders a frame without input] → The 400 ms test covers slow frames; a repeat run of the whole native suite (task 4.2) looks for others.
- [The drift exceeds four threads on another device] → The engine test fails as before, and the margin needs revisiting. A leak of fewer than five threads goes unnoticed by this test; the 50-cycle tests, which multiply a leak by 50, still catch it.
- [Apps see `onStyleLoaded` twice for one style URL] → Unchanged behavior, now documented.
