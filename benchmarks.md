# Benchmarks

## Frame rate during continuous pan

Measured over central London (see Path), in release builds, with the defaults: copy-free rendering (design D37 of the copy-free-default change) and rendering ahead (design D19). Both devices on 2026-10-11, 3 runs each, at MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3`; the Mac on AC power:

| Displayed map frames per second | macOS (MacBook Pro, M2 Max) | iPhone 15 Pro Max |
| --- | --- | --- |
| per-second p10 / p50 / p90 | 97–98 / 101–102 / 108–111 | 103–106 / 108–112 / 116–120 |
| lowest second | 93–95 | 99–104 |
| average over 30 s | 101.9–102.6 | 110.3–111.8 |
| map frame interval median / p95 / p99 | 8.34 / 16.69 / 16.75–16.77 ms | 8.34 / 16.51–16.64 / 16.74–16.81 ms |
| `render_update`, frame cycle | 7.53–7.59 ms, 9.06–9.18 ms | 7.37–7.91 ms, 8.20–8.26 ms |
| rendered frames not displayed | 6.5–7.2% | 7.6–9.6% |

Against the go/no-go values: both meet the 30 fps minimum and the 60 fps target. Rendering ahead is the default since 2026-10-10: while a frame takes longer than a refresh interval, the next frame renders without waiting until Flutter has taken the previous one. On both devices a frame cycle is longer than the 8.33 ms refresh interval, so both render ahead almost all the time.

Before copy-free rendering became the default, the same benchmark with the copy measured, at FFI commit `dd97d20f8fab6990cd87c13f091ce00e662707bd`: on macOS (2026-10-11, 3 runs) per-second p10 / p50 / p90 88–90 / 95–97 / 99–101, lowest second 83–84, average 94.0–95.0, frame cycle 9.8 ms (`render_update` 6.7 ms, copy 0.59 ms), with about 1,000 of 3,060 rendered frames per run rendered ahead; on the iPhone (2026-10-10) 87 / 99–100 / 105, lowest second 85, average 97. Both modes at the current commit are compared in "Copy-free with the upstream FFI fix" below.

The macOS numbers recorded before 2026-10-11 (per-second p10 / p50 / p90 116 / 117 / 119, lowest second 112, average 117.1, a frame of 5.7 ms) were measured with a smaller map than the Setup states. The macOS runner applied `MLT_WINDOW_SIZE` only in `awakeFromNib`, after which the window returned to the nib's 800x600 content size, and at the display's default resolution (1512x982 logical pixels) a 1600x1000 window doesn't fit anyway. Those runs therefore rendered about 1600x1200 physical pixels instead of 3200x2000. The same applies to every earlier macOS result in this file that is marked as measured before 2026-10-11. Since 2026-10-11 the runner applies the size again after launch, and the benchmark reports the size of the displayed map frames (`map_physical_size`).

Before rendering ahead, the iPhone map waited for Flutter to take each frame, the GPU idled between frames and stayed in its minimum performance state, and runs settled at about 40 or about 57 fps at the median second (`render_update` about 17 or about 11.7 ms). The first measurement over London (per-second p10 / p50 / p90 37 / 41 / 57, average 46.4) and the 5-minute run below were in the slower state.

#### iPhone variants (2026-10-10, 2 runs each, per-second p10 / p50 / p90)

| Variant | Frames per second | `render_update` | Copy | GPU performance state (Metal System Trace) |
| --- | --- | --- | --- | --- |
| paced, with copy (until D19) | 33–37 / 40 / 53–57 | 16.6–17.7 ms | 1.85 ms | minimum 100% of 13.7 s |
| rendering ahead, with copy (D19, default) | 87 / 99–100 / 105 | 8.4 ms | 1.55 ms | medium 59%, maximum 21%, minimum 20% |
| rendering ahead, copy-free (D20, experiment), before the hysteresis | 87–89 / 96–99 / 106–107 | 8.2–8.4 ms | — | not traced |
| rendering ahead with the hysteresis, with copy (default; separate session) | 86–89 / 102–103 / 109–110 | 8.2 ms | 1.54 ms | not traced |
| rendering ahead with the hysteresis, copy-free (D20, experiment; same session) | 105–106 / 109–111 / 116–117 | 7.8 ms | — | not traced |
| paced, copy-free (D20, experiment) | 58–59 / 60 / 64–69 | 11.2–11.5 ms | — | not traced |
| render thread, paced (D2 alternative, removed; 3 runs) | 33–40 / 40–52 / 51–58 | 13.7–17.9 ms | 1.85 ms | not traced |

The copy-free variants ran with a local FFI patch (design D20), which was merged upstream as maplibre-native-ffi#807 and has been in the pinned FFI commit since 2026-10-11. The first copy-free rendering-ahead runs predate the hysteresis in D19, and the map switched between rendering ahead and pacing in them. With the hysteresis, copy-free raised the lowest second from 84–86 to 102–103 fps; 8% of rendered frames weren't displayed, against 2.4% with the copy. The copy-free runs with the upstream fix are in the next section.

#### Copy-free with the upstream FFI fix (2026-10-11, 3 runs each)

Copy-free maps were an option on 2026-10-11 (`copyFree: true`, example define `COPY_FREE=true`) and became the default later that day; since then the example define `COPY=true` selects the copy. We ran the benchmark with and without it, alternating the variants, at MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3`, which includes maplibre-native-ffi#807. Upstream, a same-size `set_target` still resets the session's record of the rendered update; the local patch that the 2026-10-10 runs used did not. Rendering ahead with the hysteresis (the default) in all runs. "Not displayed" is the share of rendered frames that Flutter didn't display (1 − displayed / rendered). The benchmark doesn't report the thermal state, and it wasn't recorded.

iPhone 15 Pro Max, setup as above:

| Variant | per-second p10 / p50 / p90 | lowest second | average | `render_update` | copy | frame cycle | not displayed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| with copy | 87–91 / 98–101 / 110–113 | 83–88 | 98.4–99.8 | 7.84–8.27 ms | 1.52–1.53 ms | 9.48–9.86 ms | 3.0–5.4% |
| copy-free | 104–106 / 109–111 / 115–119 | 98–104 | 109.2–111.0 | 7.73–8.03 ms | — | 8.37–8.46 ms | 6.9–8.5% |

MacBook Pro (M2 Max), setup as above (window 1600x1000, map 3200x2000 physical pixels, display at 1800x1169), but on battery power (34% to 29% over the session; Low Power Mode off):

| Variant | per-second p10 / p50 / p90 | lowest second | average | `render_update` | copy | frame cycle | not displayed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| with copy | 88–91 / 97 / 101–103 | 86–88 | 95.8–96.8 | 6.81 ms | 0.53–0.54 ms | 9.54–9.63 ms | 7.2–8.7% |
| copy-free | 86–93 / 95–105 / 109–119 | 76–88 | 96.1–104.9 | 7.55–7.62 ms | — | 9.17–9.82 ms | 3.8–5.7% |

On the iPhone, copy-free didn't change `render_update`, so it shortened the frame cycle by about the copy, and raised the median second by about 10 fps and the lowest second by about 15 fps. It left more rendered frames undisplayed than the copy, as on 2026-10-10. On the Mac, copy-free made `render_update` 0.75 ms longer, more than the 0.54 ms copy it removed; we didn't trace it, and the depth and stencil textures that the Metal backend reallocates after each target change (design D20) are a likely cause. Two copy-free Mac runs averaged 103.6 and 104.9 fps, and the third 96.1 fps with the lowest second of the session (76), so on the Mac copy-free gave no consistent gain.

*Second session (2026-10-11, 3 runs each, same FFI commit).* The Mac was on AC power, otherwise as above. On each device the runs with the copy alternated with runs of an abandoned FFI change, and the copy-free runs followed in a second block of the same session.

| Device, variant | per-second p10 / p50 / p90 | lowest second | average | `render_update` | copy | frame cycle | not displayed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone, with copy | 87–88 / 99–102 / 109–111 | 84–86 | 98.4–99.1 | 8.07–8.20 ms | 1.53–1.54 ms | 9.67–9.83 ms | 2.9–4.3% |
| iPhone, copy-free | 103–104 / 109–111 / 116–120 | 98–101 | 109.4–110.7 | 7.53–7.97 ms | — | 8.31–8.47 ms | 7.2–8.6% |
| Mac, with copy | 91–98 / 100–102 / 105–108 | 88–96 | 99.8–101.9 | 6.81–6.90 ms | 0.49–0.54 ms | 9.05–9.43 ms | 5.9–7.9% |
| Mac, copy-free | 96–97 / 101–103 / 106–110 | 90–93 | 101.3–102.8 | 7.58–7.62 ms | — | 9.10–9.12 ms | 6.5–7.7% |

The second session repeated the first: on the iPhone copy-free raised the median second by about 10 fps and the lowest second by about 15, and on the Mac it made `render_update` about 0.7 ms longer and gave no consistent gain (1.5 fps on average, with overlapping ranges).

*Cost of the undisplayed frames.* Copy-free renders more frames that Flutter replaces before displaying them, because a copy-free frame costs about one refresh interval and the map renders ahead almost all the time (design D19). Counting those frames, the map thread's `render_update` plus copy time per displayed frame was:

| Device | with copy | copy-free |
| --- | --- | --- |
| iPhone (both sessions) | 9.91–10.10 ms | 8.24–8.62 ms |
| Mac (both sessions) | 7.76–8.07 ms | 7.85–8.25 ms |

On the iPhone the undisplayed frames cost less than the copy they replace, and the map thread spent 901–952 ms per second rendering with copy-free against 988–993 ms with the copy. This time includes the wait for the GPU but isn't an energy measurement; the 5-minute runs below showed no thermal difference. We accepted the undisplayed frames on 2026-10-11.

The per-second values count the displayed map frames in each whole second of the measured pass; p10 means that 10% of seconds had that many frames or fewer. An average over the pass hides the slow seconds, which is why the benchmark reports them.

### Path

The camera is set on every Flutter frame for 30 s, panning east at zoom 14 from 51.5115, -0.14 (Charing Cross) through Covent Garden, the City, Whitechapel and Limehouse, at 0.2 tile widths per second (0.0044 degrees of longitude per second, about 102 logical pixels per second). A first 30 s pass over the same path loads the area into the cache; the camera then goes back to the start, and the map reaches idle before the measured pass. The path has dense streets, buildings and labels throughout.

Before 2026-10-10 the benchmark panned east from San Francisco (37.7749, -122.4194), a path that runs from the city into the bay, where water renders cheaply. That path gave 119.0 fps on macOS (Stage 1) and 88.8 fps average on the iPhone, and overstated the frame rate; the earlier description of its speed as 0.2 viewport widths per second was wrong (it was 0.2 tile widths per second, as now).

### Setup

| | macOS | iPhone |
| --- | --- | --- |
| Device | MacBook Pro (Mac14,5), Apple M2 Max, 12 CPU cores (8 performance, 4 efficiency), built-in Liquid Retina XDR display, 120 Hz | iPhone 15 Pro Max (iPhone16,2), ProMotion display, 120 Hz (`CADisableMinimumFrameDurationOnPhone` is set) |
| OS | macOS 26.6.2 (25G83) | iOS 26.7.1 (23H30) |
| Map size | window 1600x1000 logical pixels, pixel ratio 2, 3200x2000 physical (since 2026-10-11; before, about 800x600 logical, see above); the display scaled to 1800x1169 logical pixels | full screen, portrait, 430x932 logical pixels, pixel ratio 3, 1290x2796 physical |
| Measured Flutter vsync interval | 8.333 ms | 8.335 ms |

Both: Xcode 26.6 (17F113); Flutter 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4, Impeller (Metal); MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3` for results measured from 2026-10-11 on, where the result names it, and `dd97d20f8fab6990cd87c13f091ce00e662707bd` before (presets `macos-arm64-metal` and `ios-arm64-metal`); style OpenFreeMap Liberty (`https://tiles.openfreemap.org/styles/liberty`); the example's Flutter control panel above the map. Thermal state on the iPhone was nominal at the start and end of every run until 2026-10-10; the 30 s benchmark doesn't report it, and it wasn't recorded for the 2026-10-11 runs.

Procedure (`example/lib/benchmark.dart`):

```sh
cd example
# macOS: open brings the window to the front. Keep the whole window visible during the
# run: a window behind others, or partly under another window, gets fewer frames or none.
flutter build macos --release --dart-define=BENCHMARK=true
open -W --env MLT_WINDOW_SIZE=1600x1000 --stdout result.txt \
  build/macos/Build/Products/Release/flutter_mapigrade_example.app

# iPhone: the result line is read from the console.
flutter build ios --release --dart-define=BENCHMARK=true
xcrun devicectl device install app --device <device> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <device> --console \
  -e '{"MLT_KEEP_AWAKE":"1"}' com.greensopinion.mapigradeExample

# 5-minute run: add --dart-define=BENCHMARK_SUSTAINED_S=300 to the iOS build.
```

The app prints one line starting with `BENCHMARK_RESULT` (or `BENCHMARK_SUSTAINED_RESULT`) and exits.

### Results (measured 30 s pass)

Displayed map frames: Dart counts each distinct frame id that Flutter took from the texture (the "frame displayed" event) and the time between them.

These tables are from the first London measurement, before rendering ahead (iPhone in the slower state), measured before 2026-10-11: the macOS column is for a map of about 1600x1200 physical pixels (see above).

| Metric (median / p95 / p99 / max) | macOS | iPhone |
| --- | --- | --- |
| Displayed map frame interval | 8.33 / 8.84 / 16.39 / 25.03 ms | 24.90 / 25.21 / 33.39 / 34.11 ms |
| Flutter frame interval (vsync to vsync) | 8.33 / 8.34 / 8.35 / 16.67 ms | 8.34 / 8.38 / 8.40 / 8.47 ms |
| Flutter frame total span (build start to raster end) | 0.78 / 2.19 / 2.81 / 7.07 ms | 0.84 / 2.78 / 3.96 / 7.66 ms |
| Flutter raster | 0.54 / 1.71 / 1.93 / 4.80 ms | 0.52 / 2.20 / 3.50 / 7.36 ms |

| Metric | macOS | iPhone |
| --- | --- | --- |
| Displayed map frames in 30 s | 3,513 | 1,391 |
| Map frames rendered | 3,513 | 1,391 |
| `render_update`, average (maximum) | 4.52 ms (21.8 ms) | 15.22 ms (27.8 ms) |
| GPU copy into the display buffer, average | 0.45 ms | 1.78 ms |
| Renders skipped because no buffer was free | 0 | 0 |
| Renders deferred until Flutter took the latest frame | 13,688 | 5,563 |

`render_update` returns only after MapLibre's command buffer completes (design, Context), so its duration is MapLibre's CPU encoding plus GPU execution on the map thread.

macOS at 3200x2000 physical pixels (2026-10-11, 3 runs, ranges over the runs):

| Metric | macOS |
| --- | --- |
| Displayed map frame interval, median / p95 / p99 / max | 8.36 / 16.72–16.77 / 16.89–16.91 / 19.5–25.7 ms |
| Flutter frame interval, median / p95 / p99 / max | 8.333 / 8.336 / 8.339–8.340 / 8.345–8.350 ms |
| Flutter frame total span, median / p95 / p99 / max | 0.42–0.43 / 1.20–1.23 / 1.36–1.39 / 3.3–5.7 ms |
| Flutter raster, median / p95 / p99 / max | 0.25 / 0.89–0.90 / 0.99–1.01 / 2.3–5.5 ms |
| Displayed map frames in 30 s | 2,821–2,849 |
| Map frames rendered | 3,061–3,070 |
| Frames rendered ahead (design D19) | 1,001–1,047 |
| `render_update`, average (maximum) | 6.69–6.72 ms (18.2–37.6 ms) |
| GPU copy into the display buffer, average | 0.58–0.60 ms |
| Renders skipped because no buffer was free | 0 |

Conditions: the Setup, with the built-in display as the only display, scaled to 1800x1169 logical pixels ("More Space") so that the 1600x1000 window fits, at 120 Hz.

### 5-minute run (iPhone, before rendering ahead)

The measured pass pans back and forth over the warm-up path for 300 s. Average displayed map frame rate per 30 s interval: 40.5, 39.5, 39.9, 39.5, 39.4, 39.5, 39.8, 39.8, 40.7, 39.8. Per second: p10 33, p50 39, p90 52, lowest 30. Thermal state: nominal at the start of every interval and at the end. Skipped renders: 0. The frame rate doesn't decrease over the 5 minutes.

### 5-minute run (iPhone, rendering ahead, copy-free and with copy)

Measured 2026-10-11 at MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3`, one run each, release builds with `--dart-define=BENCHMARK_SUSTAINED_S=300`; the run with the copy came first, then a 5-minute pause, then the copy-free run.

| Variant | per 30 s interval | per-second p10 / p50 / p90 | lowest second | displayed frames | thermal state |
| --- | --- | --- | --- | --- | --- |
| with copy | 97.5–98.9 | 86 / 99 / 109 | 84 | 29,422 | nominal at every interval start and at the end |
| copy-free | 109.7–111.6 | 104 / 110 / 119 | 100 | 33,180 | nominal at every interval start and at the end |

Skipped renders: 0 in both. Neither frame rate decreases over the 5 minutes. The thermal state has four levels, so a small difference in heat wouldn't show.

### Slower GPU (task 6.4)

Not run: the iPhone XR (iPhone11,8, A12, 60 Hz) intended as a slower-GPU data point was unavailable (`devicectl` listed it as unavailable on 2026-10-10).

### GPU time (macOS, Stage 1)

On 2026-10-09, with the earlier San Francisco path (see Path), a second run of the benchmark under Instruments' Metal System Trace (`xcrun xctrace record --template 'Metal System Trace'`) shows GPU work for the whole process: MapLibre's rendering, the per-frame copy and Flutter's compositing share one process and one GPU, and the trace doesn't attribute work to them separately. Over the traced run (warm-up and measured pass), the process's top-level GPU intervals summed to 4,117 ms on the vertex channel, 2,156 ms on the fragment channel and 680 ms on the compute channel (blits). Tracing reduced the displayed map frame rate to 97 frames per second (p95 interval 17.1 ms), so the untraced run's 119.0 fps was the result for that path.

Per frame, the best available bound for MapLibre's GPU time on that path was the `render_update` average of 2.74 ms, which includes CPU encoding; over central London it is 15.22 ms on the iPhone and 6.7 ms on macOS at 3200x2000 physical pixels (Results). The Stage 1 trace and the 2.74 ms were measured before 2026-10-11, with the smaller map.

## Alignment during camera changes (Stage 3)

The alignment benchmark (`example/lib/alignment_benchmark.dart`, flutter-map-layer change, designs D25, D26 and D28) shows the map as the base layer of a `FlutterMap` (`flutter_map` 8.3.2) and moves the `flutter_map` camera through its `MapController` on every Flutter frame. For each Flutter frame it records the map frame whose camera the layer's transform used (k_used) and the map frame that Flutter displayed (k_shown). From these it computes the alignment error: the largest distance, over the viewport corners and center, between where the displayed map frame draws a coordinate and where the overlays draw it. It computes the error both with the compensating transform (the last-reported-frame transform) and without it. All errors are in logical pixels.

### macOS (task 6.1)

Measured 2026-10-11, 3 runs, release build, 20 s per phase. Pans go back and forth over a 3,000 logical pixel path east of the Path's start at MapLibre zoom 14. Zoom goes between MapLibre zoom 13 and 15 at the Path's start, and rotation turns continuously. A warm-up runs every kind of camera change first.

| Phase | Builds matched | Frames with k_shown ≠ k_used | With transform p50 / p95 / max | Without transform p50 / p95 / max |
| --- | --- | --- | --- | --- |
| pan 100 px/s | 2,390–2,396 of 2,398–2,401 | 78.5–79.4% | 0.83 / 1.67 / 2.5–7.5 | 1.67 / 2.5 / 3.33–8.33 |
| pan 500 px/s | 2,401 of 2,401 | 77.6–79.0% | 4.17 / 8.33 / 12.5 | 8.33 / 12.5 / 12.5–16.67 |
| pan 1,000 px/s | 2,401 of 2,401 | 78.0–80.6% | 8.33 / 16.67 / 25.0 | 16.67 / 25.0 / 33.33 |
| pan 2,000 px/s | 2,401 of 2,401 | 78.5–80.7% | 16.67 / 33.33 / 50.0 | 33.33 / 50.0 / 66.67 |
| zoom 1 level/s | 2,401 of 2,401 | 94.0–94.9% | 5.46 / 10.84 / 16.49 | 5.46 / 10.96 / 21.55 |
| rotate 90°/s | 2,401 of 2,401 | 83.2–83.8% | 12.35 / 24.7 / 37.05 | 24.7 / 37.04 / 49.39 |

Where the three runs agree, the table gives one value; otherwise it gives the range.

- The measurement included 2,436 to 2,483 Flutter frames per phase. Of these, 35 to 82 were rasterized without a build (D25); they show the last build's camera and transform. A few builds at the start of the pan at 100 px/s had no displayed map frame yet (4, 8 and 5 builds). No display time fell outside a raster interval.
- In pans the errors are whole multiples of the camera movement in one Flutter frame (speed / 120 Hz, 0.83 px at 100 px/s). Without the transform, the displayed map frame is two Flutter frames behind the overlays at p50. With the transform it is one frame off, because in about 79% of frames Flutter displays a map frame that is newer than the one the transform was built for.
- In the zoom phase the transform doesn't reduce the p50 or p95 error.

Conditions: the Setup's macOS device, OS, Xcode, Flutter and MapLibre Native FFI versions and style. The built-in display was the only display, scaled to 1800x1169 logical pixels, at 120 Hz. The window had 1600x1000 logical pixels at pixel ratio 2, which is 3200x2000 physical pixels, and every phase reported a 1600x1000 viewport. Thermal state was nominal at the start and the end of every phase. There were no overlays apart from three 16 px markers.

Procedure:

```sh
cd example
flutter build macos --release --dart-define=ALIGNMENT_BENCHMARK=true
open -W --env MLT_WINDOW_SIZE=1600x1000 --stdout result.txt \
  build/macos/Build/Products/Release/flutter_mapigrade_example.app
```

The app prints one `ALIGNMENT_RESULT` line per phase and exits. Before 2026-10-11 the macOS runner applied `MLT_WINDOW_SIZE` only in `awakeFromNib`, and the window then returned to the nib's 800x600 content size. Runs on 2026-10-10 therefore measured at 800x600, where the map renders a quarter as many pixels. In those runs Flutter displayed a newer frame than the transform used in 90–99% of frames, and the p50 error with the transform equaled the p50 error without it in every phase.

### Screen capture check (macOS, task 6.3)

This check tests whether the computed error matches what the window server composites (design D29). The alignment benchmark's video mode draws a grid of red discs, 20 px in radius and 150 px apart, from a GeoJSON source in a JSON style, and a `CircleLayer` puts a blue dot of 3 px radius at each disc's center. The run is 5 s at rest followed by the pan at 1,000 px/s for 30 s. A capture tool (`example/tool/alignment_capture.swift`) records the window with ScreenCaptureKit at 120 Hz and 1 image pixel per logical pixel. In every captured frame it measures the distance between each fully visible disc's center and its dot, and the width of `flutter_map`'s gray background at the left and right edges. Frames before the first movement count as at rest; after that, only frames whose discs moved count as the pan.

Measured 2026-10-11, 1 run, release build:

| | Captured | Computed by the benchmark in the same run |
| --- | --- | --- |
| At rest: distance p50 / p95 / max | 0.03 / 0.05 / 0.05 px (105 frames, 45 discs each) | 0 / 0 / 0 px |
| Pan at 1,000 px/s: distance p50 / p95 / max | 8.40 / 8.53 / 9.13 px over all discs; 8.39 / 8.48 / 8.54 px for the per-frame median (3,311 frames that moved, 45–50 discs each) | with transform 8.33 / 8.33 / 8.34 px, without transform 8.33 / 8.33 / 8.34 px (3,604 Flutter frames, 3,601 of 3,601 builds matched) |
| Uncovered strip at an edge | 16 px in 3,295 of the 3,311 moving frames | — |

- The capture and the computation agree within 0.06 px at p50, well inside the 2 px limit of the task. So MapLibre renders at the camera it reports, the conversion and the transform are correct while the camera moves, and the map frame Flutter takes in a raster pass is composited with the overlays of the same Flutter frame.
- The strip is 16 px wide, which is two Flutter frames of movement at 1,000 px/s (16.7 px). It appears in almost every moving frame.
- In this run the map displayed 120 frames per second, and Flutter displayed a newer frame than the transform used in 99.9% of Flutter frames, so the errors with and without the transform were equal. The 1600x1000 runs above had 77.6–80.7% such frames in the pans. The check covers the computation in both cases, because it tests the inputs of the computation, not the frequency of new frames.

Conditions: the Setup's macOS device and versions. The built-in display was at its default resolution (1512x982 logical pixels), at 120 Hz. The window had 1400x880 logical pixels at pixel ratio 2. Thermal state was nominal at the end of both phases.

Procedure:

```sh
cd example
flutter build macos --release --dart-define=ALIGNMENT_BENCHMARK=true \
  --dart-define=ALIGNMENT_VIDEO=true --dart-define=ALIGNMENT_PHASE_S=30
swiftc -O -o /tmp/alignment_capture tool/alignment_capture.swift
open --env MLT_WINDOW_SIZE=1400x880 --stdout result.txt \
  build/macos/Build/Products/Release/flutter_mapigrade_example.app
/tmp/alignment_capture "$(pgrep -f flutter_mapigrade_example.app/Contents/MacOS)" 50
```

The capture tool needs the Screen Recording permission for the process that runs it, and prints one `ALIGNMENT_CAPTURE_RESULT` line.

### iPhone (task 6.2)

Measured 2026-10-11, 3 runs, release build, 20 s per phase, with the same phases as on macOS.

| Phase | Map frames per second (average) | Builds matched | Frames with k_shown ≠ k_used | With transform p50 / p95 / max | Without transform p50 / p95 / max |
| --- | --- | --- | --- | --- | --- |
| pan 100 px/s | 93.8–104.4 | 2,394–2,395 of 2,400 | 78.4–87.2% | 0.83 / 1.67 / 2.5–3.32 | 1.67 / 2.5–2.51 / 4.16–4.17 |
| pan 500 px/s | 96.0–97.0 | 2,400 of 2,400 | 80.6–81.4% | 4.17 / 8.35 / 12.52–12.54 | 8.34 / 12.52 / 16.7–20.86 |
| pan 1,000 px/s | 94.0–94.3 | 2,400 of 2,400 | 79.1–79.2% | 8.33 / 16.71 / 25.05–25.08 | 16.69 / 25.05 / 33.4–33.41 |
| pan 2,000 px/s | 94.2–94.7 | 2,400 of 2,400 | 79.2–79.6% | 16.66–16.67 / 33.41–33.42 / 50.1–50.13 | 33.37–33.38 / 50.1 / 66.79–66.8 |
| zoom 1 level/s | 108.4–109.9 | 2,400 of 2,400 | 90.5–91.7% | 2.96–2.97 / 5.96 / 9.0–11.72 | 5.92–5.95 / 8.97 / 15.04–15.05 |
| rotate 90°/s | 78.8–81.2 | 2,400 of 2,400 | 64.8–66.6% | 6.72 / 13.46 / 20.2–26.85 | 20.14–20.15 / 26.87–26.88 / 33.61–40.35 |

- The measurement included 2,402 to 2,485 Flutter frames per phase. Of these, 8 to 85 were rasterized without a build. 5 or 6 builds at the start of the pan at 100 px/s had no displayed map frame yet. No display time fell outside a raster interval.
- As on macOS, the transform halves the p50 error of pans: one Flutter frame of movement instead of two. It also halves the p50 error of zoom. For rotation it reduces the p50 error to a third (6.72 against 20.14). Rotation is also the phase with the lowest map frame rate and the fewest frames where k_shown ≠ k_used.
- Frame rate check: the same session's frame-rate benchmark without the layer (`benchmark.dart`, 3 runs, 1290x2796 physical pixels) displayed 98.0, 98.0 and 98.9 map frames per second on average, with per-second p10 / p50 / p90 84–87 / 100–102 / 107–111 and `render_update` 8.2–8.3 ms. The pan at 100 px/s with the layer displayed 104.4, 93.8 and 94.0 per second: in two of three runs about 4% fewer than without the layer. The two benchmarks pan differently (30 s east against 20 s back and forth over 3,000 px of the same area), so the comparison isn't exact. We accepted the difference as within run-to-run variation; its cause is unknown.

Conditions: the Setup's iPhone, OS, Xcode, Flutter and MapLibre Native FFI versions and style. Full screen, portrait, 430x932 logical pixels at pixel ratio 3, which is 1290x2796 physical pixels. Auto-Lock was off, and the app was launched with `MLT_KEEP_AWAKE=1`. Thermal state was nominal at the start of every run and at the end of every phase.

Procedure: as for `benchmark.dart` (Setup), with `--dart-define=ALIGNMENT_BENCHMARK=true` in the iOS build. The app prints one `ALIGNMENT_RESULT` line per phase and exits.

### Copy-free and with copy (2026-10-11)

Before copy-free maps became the default, we ran the alignment benchmark with and without them, at MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3`, 3 runs each, alternating, 20 s per phase, on the Mac (1600x1000 window, display at 1800x1169, AC power) and the iPhone at the same time. Errors in logical px; "newer" is the share of Flutter frames with k_shown ≠ k_used.

Mac:

| Phase | Variant | Map fps | Newer | With transform p50 / p95 / max | Without transform p50 / p95 / max |
| --- | --- | --- | --- | --- | --- |
| pan 100 px/s | with copy | 99.5–102.5 | 83.2–85.6% | 0.83 / 1.67 / 2.5–3.33 | 1.67 / 2.5 / 2.5–4.17 |
| | copy-free | 100.0–103.1 | 83.6–86.1% | 0.83 / 1.67 / 2.5–5.83 | 1.67 / 2.5 / 3.33–7.08 |
| pan 1,000 px/s | with copy | 102.5–105.1 | 85.7–86.8% | 8.33 / 16.67 / 25 | 8.33–16.67 / 25 / 33.33 |
| | copy-free | 100.0–103.2 | 83.8–86.3% | 8.33 / 16.67 / 25 | 16.67 / 25 / 33.33 |
| pan 2,000 px/s | with copy | 103.7–104.5 | 86.7–87.4% | 16.67 / 33.33 / 50 | 16.67–33.33 / 50 / 50.01–66.67 |
| | copy-free | 100.8–103.6 | 82.9–86.6% | 16.67 / 33.33 / 50–66.66 | 33.33 / 50 / 66.67 |
| zoom 1 level/s | with copy | 108.7–113.2 | 90.8–94.5% | 5.46 / 10.84 / 16.49 | 5.46 / 10.96 / 21.55–22.05 |
| | copy-free | 116.0–116.3 | 96.7–97.0% | 5.46 / 5.47 / 16.49 | 5.46 / 10.96 / 21.55–22.05 |
| rotate 90°/s | with copy | 98.0–100.2 | 82.3–84.0% | 12.35 / 24.7 / 37.05–49.39 | 24.7 / 37.04 / 49.39–74.08 |
| | copy-free | 96.4–97.3 | 78.3–81.4% | 12.35 / 24.7 / 37.04–37.05 | 24.7 / 37.04 / 49.39 |

iPhone:

| Phase | Variant | Map fps | Newer | With transform p50 / p95 / max | Without transform p50 / p95 / max |
| --- | --- | --- | --- | --- | --- |
| pan 100 px/s | with copy | 94.0–101.8 | 78.4–84.9% | 0.83 / 1.67 / 2.5–2.51 | 1.67 / 2.5 / 4.17 |
| | copy-free | 109.0–112.0 | 91.0–93.4% | 0.83 / 1.67 / 2.5–2.51 | 1.67 / 2.5 / 4.17 |
| pan 1,000 px/s | with copy | 94.8–95.5 | 79.5–80.3% | 8.33 / 16.7–16.71 / 25.06–33.41 | 16.68 / 25.05 / 33.4–33.41 |
| | copy-free | 107.1–108.1 | 89.6–90.4% | 8.33 / 16.7 / 25.05–25.06 | 16.67 / 25.01–25.02 / 25.1–33.34 |
| pan 2,000 px/s | with copy | 94.8–95.7 | 79.7–80.4% | 16.66–16.67 / 33.41–33.42 / 50.11–50.21 | 33.36–33.38 / 50.09–50.1 / 66.81–66.85 |
| | copy-free | 108.2–108.5 | 87.6–90.6% | 16.67 / 33.39–33.4 / 50.11–66.58 | 33.33–33.34 / 50.03–50.05 / 66.73–99.96 |
| zoom 1 level/s | with copy | 108.9–109.6 | 89.5–90.9% | 2.96 / 5.96 / 9 | 5.95 / 8.97 / 15.03–15.04 |
| | copy-free | 102.5–104.9 | 85.8–87.8% | 2.96 / 5.96–5.97 / 8.98–8.99 | 2.98–3 / 8.96–8.97 / 11.99–14.61 |
| rotate 90°/s | with copy | 82.3–83.5 | 69.0–70.0% | 6.72 / 13.47 / 20.18–20.2 | 20.14 / 26.87 / 33.66–40.29 |
| | copy-free | 103.0–103.8 | 86.3–86.9% | 6.72 / 13.46 / 20.19–20.2 | 13.44 / 20.18–20.19 / 20.24–26.91 |

The pan at 500 px/s gave the same p50 and p95 errors in both variants on both devices and is left out.

- With the transform, copy-free gave the same p50 and p95 errors as the copy in every phase on both devices, except a lower p95 in the Mac's zoom phase (5.47 against 10.84 px). The baseline that the camera-prediction change compares against (8.33 px at p50 at 1,000 px/s with the transform) holds for copy-free maps.
- On the iPhone, copy-free displayed 12–21 more map frames per second in the pans and the rotation, and Flutter showed a newer frame than the transform used more often (86–93% against 69–91%). Without the transform it reduced the p50 error in the zoom phase (3.0 against 5.95 px) and the rotation (13.44 against 20.14 px); in the pans it stayed two Flutter frames of movement.
- Every phase on the Mac and in the runs with the copy on the iPhone ended at the nominal thermal state. The third copy-free iPhone run, the last of six consecutive runs (about 18 minutes), ended its phases from the pan at 500 px/s on at the fair thermal state; its errors match the other two copy-free runs.

## No CPU readback on the frame path

### macOS (Stage 1, task 7.3)

Source: a search of the plugin and the example (`src/`, `macos/` (now `darwin/`), `lib/`, `example/lib/`) for `mln_texture_read_premultiplied_rgba8`, `getBytes`, `CVPixelBufferLockBaseAddress`, `CVPixelBufferGetBaseAddress`, `IOSurfaceLock` and `replaceRegion` found no matches. The frame path is `mln_render_session_render_update` into a private `MTLTexture`, an `MTLBlitCommandEncoder` copy into an IOSurface-backed `CVPixelBuffer`, and `-[FlutterTexture copyPixelBuffer]` returning that pixel buffer.

Trace: in the Metal System Trace of the benchmark run (about 100 s, including the 60 s of continuous pan), the process's encoders were 13,872 render encoders and 6,577 blit encoders, with no compute encoders. In the trace's 33,477 time-profile samples, the frame-path functions appear (`MapTexture::MaybeRender`, `CopyToBuffer`, `mln_render_session_render_update`, `copyPixelBuffer`), while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes` and `mln_texture_read_premultiplied_rgba8` appear 0 times.

### iPhone (iOS slice, task 5.7)

A 20 s Metal System Trace on the iPhone 15 Pro Max (`xcrun xctrace record --device <id> --template 'Metal System Trace' --attach <pid>`, 2026-10-10), attached to a release build of the example panning continuously (`--dart-define=CONTINUOUS_PAN=true`): the app's encoders were 4,966 render encoders and 2,050 blit encoders, with no compute encoders; 4,100 were encoded on the map thread and 2,916 on Flutter's raster thread. Of the 12,808 time-profile samples, `mln_render_session_render_update` appears in 6,032, the plugin's blit (`-[IOGPUMetalBlitCommandEncoder copyFromTexture:toTexture:]` from `MetalRenderTarget::CopyToBuffer`) in 121 and `copyPixelBuffer` in 77, while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes`, `replaceRegion` and `mln_texture_read_premultiplied_rgba8` appear 0 times. Two samples are in `IOSurfaceClientGetBaseAddressOfPlane`; both are called by the Metal driver's `getGPUVirtualAddress` while it encodes the plugin's blit, which computes a GPU address, not a CPU read.
