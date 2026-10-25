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

Procedure (`packages/test_harness/lib/benchmark.dart`):

```sh
cd packages/test_harness
# macOS: open brings the window to the front. Keep the whole window visible during the
# run: a window behind others, or partly under another window, gets fewer frames or none.
flutter build macos --release --dart-define=BENCHMARK=true
open -W --env MLT_WINDOW_SIZE=1600x1000 --stdout result.txt \
  build/macos/Build/Products/Release/test_harness.app

# iPhone (add --dart-define=BENCHMARK_SUSTAINED_S=300 for the 5-minute run)
flutter build ios --release --dart-define=BENCHMARK=true
xcrun devicectl device install app --device <device> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <device> --console \
  -e '{"MLT_KEEP_AWAKE":"1"}' com.greensopinion.mapigradeTestHarness

# Memory and color measurements (any device)
flutter drive -d <device> --driver=test_driver/integration_test.dart \
  --target=integration_test/memory_measurement.dart
flutter drive -d <device> --driver=test_driver/integration_test.dart \
  --target=integration_test/color_measurement.dart
```

The app prints one line starting with `BENCHMARK_RESULT` (or `BENCHMARK_SUSTAINED_RESULT`) and exits.

Instruments' `xctrace` launches an app by its bundle identifier, which the Debug and Release builds share. Delete `build/macos/Build/Products/Debug/test_harness.app` before tracing the Release build, or `xctrace` starts the Debug build.

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

### Android (Pixel 4a (5G), android-texture-vertical-slice task 7.2)

Measured 2026-10-16 over central London (see Path), with the defaults (copy-free; rendering ahead doesn't apply on Android, design D53). On Android the benchmark counts the frames the map queued for display, because Android reports no display time (design D52). The map renders at most one frame per display refresh interval (design D53).

Setup:

| | Android |
| --- | --- |
| Device | Pixel 4a (5G) (`bramble`), Qualcomm SM7250 (Snapdragon 765G), Adreno 620, 60 Hz display (its only mode), 4 KB pages |
| OS | Android 14 (API 34, UP1A.231105.001.B2) |
| Map size | full screen, portrait, 411x867 logical pixels, pixel ratio 2.625, 1080x2277 physical |
| Measured Flutter vsync interval | 16.71 ms (median Flutter frame interval) |
| Renderer | Impeller (OpenGL ES). Flutter tried Impeller's Vulkan backend on the Adreno 620 and then used OpenGL ES (`flutter run` log). MapLibre renders with EGL (FFI preset `android-arm64-egl`, design D51). |

Flutter 3.47.5 stable (framework `6a19cca564`); MapLibre Native FFI commit `677a1cfdf1ab2b914f633d4abc790b7136d3a321`; release builds; style OpenFreeMap Liberty; the test harness's Flutter control panel above the map; the phone on USB power with the screen kept on. Thermal status 0 (none) at the start and end of every run.

Procedure:

```sh
cd packages/test_harness
# add --dart-define=BENCHMARK_SUSTAINED_S=300 for the 5-minute run
flutter build apk --release --dart-define=BENCHMARK=true
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -S -n com.greensopinion.mapigrade_test_harness/.MainActivity
adb logcat -s flutter | grep BENCHMARK_
```

Keep the screen on and unlocked during a run. When the screen turns off, the activity stops and the plugin pauses rendering (design D55), and the run doesn't finish.

30 s continuous pan, 3 runs (ranges over the runs):

| Metric | Pixel 4a (5G) |
| --- | --- |
| Queued map frames per second, per-second min / p10 / p50 / p90 | 55–56 / 57 / 58–59 / 59 |
| Queued map frames per second, average over 30 s | 58.2–58.3 |
| Queued map frame interval, median / p95 / p99 / max | 16.96–16.97 / 27.6–28.1 / 36.2–36.7 / 49.6–53.3 ms |
| Map frames rendered | 1,745–1,748 |
| Flutter frames rasterized | 1,702–1,735 |
| Flutter frame interval, median / p95 / p99 / max | 16.71 / 33.34–33.40 / 33.47–33.51 / 50.1–83.5 ms |
| Flutter frame total span, median / p95 / p99 / max | 10.8–10.9 / 21.7–27.0 / 31.2–32.9 / 50.3–57.4 ms |
| Flutter raster, median / p95 / p99 / max | 3.9–5.9 / 14.0–16.7 / 17.0–18.6 / 32.1–35.0 ms |
| `render_update`, average (maximum) | 8.97–9.20 ms (39.7–151.9 ms) |
| Frame cycle, average | 17.16–17.20 ms |
| Renders deferred to the next refresh interval (`interval_waits`) | 1,680–1,692 |
| Skipped renders | 0 |

Against the go/no-go values: the Pixel meets the 30 fps minimum and is close to the 60 fps target (the display's refresh rate). `render_update` takes about 9 ms of the 16.7 ms interval, so the refresh interval limits the frame rate, not the map thread. Flutter rasterized fewer frames than the map queued (1,702–1,735 against 1,745–1,748), and more than 5% of Flutter frame intervals were two refresh intervals long, so Flutter didn't display at least 13–44 of the queued map frames. The plugin can't count the frames Flutter displays on Android (design D52).

5-minute run (one run, `BENCHMARK_SUSTAINED_S=300`): queued map frames per second per 30 s interval 58.4, 58.2, 58.3, 58.2, 58.4, 57.9, 58.0, 57.9, 58.3, 58.1; per second p10 57, p50 58, p90 59, lowest 46; 17,449 queued frames; skipped renders 0; thermal state nominal at every interval start and at the end. The frame rate doesn't decrease over the 5 minutes.

Memory (`integration_test/memory_measurement.dart`, debug build, PSS from `/proc/self/smaps_rollup`, design D58): 223 MiB before the map was created, 346 MiB before the memory reduction, 341 MiB 2 s and 342 MiB 7 s after it. During 300 resizes PSS stayed between 280 and 298 MiB, and it was 265 MiB 2 s after dispose.

### Android display slots (android-layer-children-alignment change, tasks 1.1 and 5.1)

Measured 2026-10-17 on the Pixel 4a (5G), with the setup and procedure above, 3 runs each. "One slot" is a build of commit `e345d67`, before the change; "six slots" is the change with six display slots, renders paced by the display refresh interval (design D134), and Dart choosing the newest ready frame in each Flutter frame. With one slot, a frame counts as displayed when the map queued it; with six slots, when Dart chose it.

| Metric | One slot | Six slots |
| --- | --- | --- |
| Displayed map frames per second, average over 30 s | 57.7–58.3 | 50.8–51.7 |
| Displayed map frames per second, per-second min / p10 / p50 / p90 | 44–56 / 56–57 / 58–59 / 59–60 | 36–42 / 45–47 / 51–52 / 56–58 |
| Displayed map frame interval, median / p95 / p99 / max | 16.91–16.95 / 27.3–30.5 / 36.5–40.7 / 52.2–67.4 ms | 16.79–16.81 / 35.1–35.8 / 66.0–68.0 / 189.5–206.5 ms |
| Map frames rendered | 1,730–1,748 | 1,735–1,746 |
| Map frames displayed | 1,730–1,748 | 1,523–1,552 |
| Flutter frames rasterized | 1,641–1,713 | 1,762–1,826 |
| Flutter frame interval, p95 / p99 / max | 33.38–33.40 / 33.49–50.07 / 66.8–100.2 ms | 16.76 / 16.78–16.79 / 33.4–50.1 ms |
| `render_update`, average (maximum) | 8.96–9.58 ms (39.4–56.9 ms) | 8.65–8.77 ms (38.3–54.2 ms) |
| Skipped renders | 0 | 0 |

With one slot, Flutter rasterized fewer Flutter frames than the map queued, so it showed at most 55 to 57 map frames per second. With six slots, about 12% of rendered frames were replaced before Dart chose them, and some Flutter frames showed the frame of the previous Flutter frame again. Flutter itself rasterized a frame on almost every refresh. We first attributed this to the map's render clock drifting against the display refresh (design D134); a trace on 2026-10-19 showed that this was wrong ("Choice of the newest finished frame" below).

Two other configurations of the change, one run set each, were rejected: renders paced by Dart's choice displayed 25.7–27.4 map frames per second, and five slots with interval pacing displayed 48.3–50.1 with 203–266 skipped renders per run (design corrections of D133 and D134).

Memory (`integration_test/memory_measurement.dart`, profile build because `flutter drive` doesn't run release builds, PSS from `/proc/self/smaps_rollup`, 3 runs):

| PSS | One slot | Six slots |
| --- | --- | --- |
| Before the map was created | 97–102 MiB | 86–88 MiB |
| Before the memory reduction | 231–235 MiB | 219–222 MiB |
| 7 s after the memory reduction | 222–226 MiB | 210–221 MiB |
| At the start of the resizes / after 300 resizes | 179–180 / 162–163 MiB | 161–164 / 145–147 MiB |
| 2 s after dispose | 144–147 MiB | 123–129 MiB |

This PSS doesn't include the graphics buffers. `dumpsys meminfo` 10 s into the measured pan of the benchmark (release build, one run each) reported Graphics 215 MB with one slot and 203 MB with six slots, of which EGL mtrack 108 MB and 98 MB: the six slots use one buffer fewer than Flutter's `SurfaceProducer` did.

The app size increase is in `limitations.md`.

### Choice of the newest finished frame (synchronous-frame-choice change, tasks 1.1, 5.1 and 5.2)

Measured 2026-10-19, with the setups and procedures above, 3 runs per device, release builds of commit `f3a80bb`. Before the change, Dart chose the frame of the last finished-frame report that it had handled (design D123 of the layer-children-alignment change). The Mac display was scaled to 1800x1169 logical pixels, and the iPhone's auto-lock was off.

| Metric | Pixel 4a (5G) | Mac | iPhone |
| --- | --- | --- | --- |
| Displayed map frames per second, average over 30 s | 49.9–50.8 | 106.3–107.7 | 108.5–111.0 |
| Displayed map frames per second, per-second min / p10 / p50 / p90 | 38–42 / 41–46 / 50–52 / 56–57 | 91–93 / 98–99 / 103–108 / 116–117 | 97–98 / 104–107 / 108–111 / 116–117 |
| Displayed map frame interval, median / p95 / p99 / max | 16.80–16.82 / 34.69–38.82 / 67.44–69.95 / 137.2–202.6 ms | 8.34 / 16.69–16.70 / 16.77–16.79 / 18.4–25.6 ms | 8.34 / 16.60–16.67 / 17.00–17.10 / 33.7–41.8 ms |
| Map frames rendered | 1,738–1,744 | 3,337–3,355 | 3,570–3,675 |
| Map frames displayed | 1,498–1,523 | 3,189–3,230 | 3,254–3,331 |

A trace of the benchmark on the Pixel before the change (2026-10-19, atrace `gfx` and `view`; the second run a profile build with `--ez trace-systrace true`) showed the cause of the frames that Dart didn't choose:

- Renders started at a fixed point after each vsync: Dart's `setCamera` call, about 0.4 ms after the vsync callback, starts each render, and the map's swap followed 2 to 3 ms after the vsync. The render start didn't drift against the vsync.
- The listener thread's `ImageReader.acquireNextImage` waited on each frame's GPU fence (`waitForever`): 10.7 ms after the swap at the median (p10 8.9 ms, p90 13.3 ms). A frame became finished only then, 10 to 16 ms after a vsync, and the time moved with the GPU load along the path.
- Of the 403 frames that finished in the last 1.7 ms before a vsync callback, 254 had their finished-frame report handled by Dart only after `Animator::BeginFrame`. Before the next build the map replaced that frame, Dart chose the frame it had been told about, the map refused the choice, and Dart displayed the previous frame again, often for several Flutter frames in a row.
- A simulation of the choice from the trace's timestamps gave 1,459 displayed frames and a p99 interval of 84.1 ms, against 1,449 and 84.0 ms measured. With the map choosing its newest finished frame at each build, it gave 54.3 displayed frames per second and a longest interval of 34.5 ms.

After the change, measured the same day with release builds of the change: in each Flutter frame that Dart builds, the map chooses its newest finished frame and returns its camera (design D141).

| Metric | Pixel 4a (5G) | Mac | iPhone |
| --- | --- | --- | --- |
| Displayed map frames per second, average over 30 s | 52.7–53.2 | 106.8–107.5 | 109.3–111.0 |
| Displayed map frames per second, per-second min / p10 / p50 / p90 | 45–47 / 48–49 / 53–54 / 56–58 | 93–96 / 98–100 / 107 / 115–116 | 101–103 / 104–106 / 109–111 / 117–120 |
| Displayed map frame interval, median / p95 / p99 / max | 16.80–16.82 / 33.95–34.09 / 37.03–38.35 / 44.7–47.0 ms | 8.34 / 16.70 / 16.77–16.80 / 18.1–25.0 ms | 8.34 / 16.49–16.59 / 16.77–16.78 / 19.1–19.3 ms |
| Map frames rendered | 1,741–1,748 | 3,357–3,378 | 3,544–3,619 |
| Map frames displayed | 1,582–1,597 | 3,203–3,226 | 3,280–3,330 |
| Rendered frames that Dart didn't choose | 8.5–9.2% (before: 12.4–14.0%) | 4.1–5.2% | 7.4–8.1% |

On the Pixel the displayed frame rate increased by about 3 frames per second, and the longest displayed frame interval decreased from 137–203 ms to 45–47 ms. On the Mac and the iPhone the frame rate didn't change; on the iPhone the slowest second increased from 97–98 to 101–103 frames, and the longest interval decreased from 34–42 ms to 19 ms.

An atrace trace of one more Pixel run (profile build, `gfx` and `view`, `--ez trace-systrace true`; 52.8 displayed map frames per second) had 73 Flutter frames in 30 s that kept the previous map frame although a frame had finished before the frame started (`Animator::BeginFrame`), against 272 in the trace before the change. In 71 of them Dart built no widget (no `BUILD` slice), so the layer didn't choose: each of these frames finished 0 to 2 ms before the vsync, and its finished-frame report, which starts the layer's build, reached Dart after the Flutter frame had started.

### Slower GPU (task 6.4)

Not run: the iPhone XR (iPhone11,8, A12, 60 Hz) intended as a slower-GPU data point was unavailable (`devicectl` listed it as unavailable on 2026-10-10).

### GPU time (macOS, Stage 1)

On 2026-10-09, with the earlier San Francisco path (see Path), a second run of the benchmark under Instruments' Metal System Trace (`xcrun xctrace record --template 'Metal System Trace'`) shows GPU work for the whole process: MapLibre's rendering, the per-frame copy and Flutter's compositing share one process and one GPU, and the trace doesn't attribute work to them separately. Over the traced run (warm-up and measured pass), the process's top-level GPU intervals summed to 4,117 ms on the vertex channel, 2,156 ms on the fragment channel and 680 ms on the compute channel (blits). Tracing reduced the displayed map frame rate to 97 frames per second (p95 interval 17.1 ms), so the untraced run's 119.0 fps was the result for that path.

Per frame, the best available bound for MapLibre's GPU time on that path was the `render_update` average of 2.74 ms, which includes CPU encoding; over central London it is 15.22 ms on the iPhone and 6.7 ms on macOS at 3200x2000 physical pixels (Results). The Stage 1 trace and the 2.74 ms were measured before 2026-10-11, with the smaller map.

## Alignment during camera changes (Stage 3)

The remove-camera-transform change (2026-10-12) removed the compensating transform and the benchmark's `transform` mode. Since then the benchmark reports only the error of the drawn map (`error_drawn_px`), no longer reports `error_with_transform_px`, `error_without_transform_px` and `mismatch_fraction`, and runs `predict1` when `ALIGNMENT_MODE` isn't set. The results below were measured before that change.

The alignment benchmark (`packages/test_harness/lib/alignment_benchmark.dart`, flutter-map-layer change, designs D25, D26 and D28) shows the map as the base layer of a `FlutterMap` (`flutter_map` 8.3.2) and moves the `flutter_map` camera through its `MapController` on every Flutter frame. For each Flutter frame it records the map frame whose camera the layer's transform used (k_used) and the map frame that Flutter displayed (k_shown). From these it computes the alignment error: the largest distance, over the viewport corners and center, between where the displayed map frame draws a coordinate and where the overlays draw it. It computes the error both with the compensating transform (the last-reported-frame transform) and without it. All errors are in logical pixels.

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

This check tests whether the computed error matches what the window server composites (design D29). The alignment benchmark's video mode draws a grid of red discs, 20 px in radius and 150 px apart, from a GeoJSON source in a JSON style, and a `CircleLayer` puts a blue dot of 3 px radius at each disc's center. The run is 5 s at rest followed by the pan at 1,000 px/s for 30 s. A capture tool (`packages/test_harness/tool/alignment_capture.swift`) records the window with ScreenCaptureKit at 120 Hz and 1 image pixel per logical pixel. In every captured frame it measures the distance between each fully visible disc's center and its dot, and the width of `flutter_map`'s gray background at the left and right edges. Frames before the first movement count as at rest; after that, only frames whose discs moved count as the pan.

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

## Alignment with camera prediction (camera-prediction change)

The alignment benchmark (Stage 3, above) measures the layer in five configurations, selected with `--dart-define=ALIGNMENT_MODE=` (camera-prediction change, design D34):
- `transform` was the default until the remove-camera-transform change: the compensating transform, without prediction. The mode no longer exists.
- `none` uses neither the transform nor prediction.
- `predict1`, `predict2` and `predict3` set the camera predicted 1, 2 or 3 refresh intervals ahead, without the transform.

The drawn error is the alignment error of what the layer draws: with the transform in `transform` mode, without it in the other modes. In pan phases, the mean offset along the pan is the mean signed distance at the viewport center between the drawn map and the overlays: positive when the map shows a camera further along the pan than the overlays, negative when it lags behind them.

Three phases pan at 1,000 px/s and change the motion (design D35):
- `stop` pans for 1 s, then rests for 1 s: 10 stops in 20 s.
- `fling` pans for 1 s, then moves as `flutter_map`'s fling after a release at 1,000 px/s, then rests until the 3 s cycle ends: 10 flings in 30 s. At 1600x1000 the fling starts at 1,000 px/s, reaches 3,079 px/s after 13.6 ms, and stops after 1.447 s and 1,000 px.
- `reverse` reverses the direction every 1 s: 19 reversals in 20 s.

For each change, the overshoot is the largest drawn error over the Flutter frames from the change until 0.5 s after the camera is at rest or at constant speed again. The overshoot ahead is the largest distance at the viewport center by which the map is ahead of the overlays in the direction of motion before the change, or 0 if the map isn't ahead in any of those frames. The tables give p50 / p95 / max over the changes in the phase.

### macOS (task 4.1)

Measured 2026-10-11, release builds, 2 runs per mode. All five modes ran once, then all five again. The phases were 20 s, the fling 30 s.

| Phase | Mode | Drawn error p50 / p95 / max | Mean offset along the pan | Map fps |
| --- | --- | --- | --- | --- |
| pan 100 px/s | `transform` | 0.83 / 1.67 / 2.5–4.17 | 0.85 | 100.0–101.9 |
| pan 100 px/s | `none` | 1.67 / 2.5 / 3.33–4.17 | −1.41 to −1.39 | 101.4–101.6 |
| pan 100 px/s | `predict1` | 0.83 / 1.67 / 3.33–6.67 | −0.6 to −0.56 | 101.2–101.5 |
| pan 100 px/s | `predict2` | 0.83 / 0.83 / 2.5–3.33 | 0.23–0.3 | 101.3–101.8 |
| pan 100 px/s | `predict3` | 0.83 / 1.67 / 1.67–2.5 | 1.06–1.12 | 101.6–102.0 |
| pan 500 px/s | `transform` | 4.17 / 8.33 / 12.5 | 4.24 | 103.0–105.7 |
| pan 500 px/s | `none` | 4.17–8.33 / 12.5 / 16.59–16.67 | −6.9 to −6.29 | 102.1–104.9 |
| pan 500 px/s | `predict1` | 0–4.17 / 8.33 / 12.56–16.59 | −2.75 to −2.61 | 102.0–104.5 |
| pan 500 px/s | `predict2` | 4.17 / 4.17 / 12.62–16.63 | 1.64–1.9 | 103.3–105.5 |
| pan 500 px/s | `predict3` | 4.17–8.33 / 8.33 / 20.75–20.79 | 5.64–6.05 | 103.7–105.0 |
| pan 1,000 px/s | `transform` | 8.33 / 16.67 / 25 | 8.04–8.47 | 102.9–105.5 |
| pan 1,000 px/s | `none` | 16.67 / 25 / 33.33 | −14.26 to −14.07 | 100.4–103.5 |
| pan 1,000 px/s | `predict1` | 0–8.33 / 16.67 / 24.84–33.29 | −5.51 to −4.17 | 102.9–105.2 |
| pan 1,000 px/s | `predict2` | 8.33 / 8.33 / 33.29–41.59 | 2.43–4.14 | 102.3–105.8 |
| pan 1,000 px/s | `predict3` | 8.33 / 16.67 / 41.63 | 10.45–10.72 | 101.4–102.5 |
| pan 2,000 px/s | `transform` | 16.67 / 33.33 / 50–66.67 | 16.33–16.35 | 102.0–104.8 |
| pan 2,000 px/s | `none` | 16.67–33.33 / 50 / 66.67 | −27.73 to −26.55 | 101.7–102.0 |
| pan 2,000 px/s | `predict1` | 0–16.67 / 33.33 / 50–66.63 | −12.25 to −8.73 | 102.2–105.2 |
| pan 2,000 px/s | `predict2` | 16.67 / 16.67 / 66.25–66.51 | 3.89–6.83 | 101.4–104.3 |
| pan 2,000 px/s | `predict3` | 16.67 / 33.33 / 99.96 | 18.68–19.82 | 100.7–102.2 |
| zoom 1 level/s | `transform` | 5.46 / 5.47 / 16.21–16.49 | — | 115.8–116.6 |
| zoom 1 level/s | `none` | 5.46 / 10.96 / 16.49–21.55 | — | 114.7–115.0 |
| zoom 1 level/s | `predict1` | 0 / 5.47 / 16.11–16.21 | — | 114.5–115.3 |
| zoom 1 level/s | `predict2` | 5.43 / 5.47 / 16.48 | — | 115.3–115.8 |
| zoom 1 level/s | `predict3` | 10.84 / 10.96 / 22.04–37.33 | — | 114.5–115.6 |
| rotate 90°/s | `transform` | 12.35 / 24.7 / 37.04 | — | 97.1–97.8 |
| rotate 90°/s | `none` | 24.7 / 37.04 / 37.05–49.39 | — | 96.8–97.5 |
| rotate 90°/s | `predict1` | 12.35 / 24.7 / 24.7–37.04 | — | 96.7–97.6 |
| rotate 90°/s | `predict2` | 0 / 12.35 / 24.7 | — | 95.7–98.0 |
| rotate 90°/s | `predict3` | 12.35 / 24.7 / 24.7 | — | 96.5–98.5 |

| Phase | Mode | Changes | Overshoot ahead p50 / p95 / max | Overshoot p50 / p95 / max | Drawn error p50 / p95 / max | Map fps |
| --- | --- | --- | --- | --- | --- | --- |
| stop | `transform` | 10 | 8.35–8.41 / 16.67 / 16.67 | 8.35–8.41 / 16.67 / 16.67 | 0 / 16.67 / 25 | 81.3–84.2 |
| stop | `none` | 10 | 0 / 0 / 0 | 8.4–8.41 / 16.78 / 16.78 | 0.02–0.03 / 25 / 41.67 | 82.1–82.2 |
| stop | `predict1` | 10 | 8.25–8.27 / 8.33 / 8.33 | 8.25–8.33 / 8.35–8.46 / 8.35–8.46 | 0 / 16.67 / 33.33 | 81.0–83.2 |
| stop | `predict2` | 10 | 16.58–16.59 / 16.66 / 16.66 | 16.58–16.59 / 16.66 / 16.66 | 0 / 8.33 / 33.33 | 82.1–83.0 |
| stop | `predict3` | 10 | 24.92–24.94 / 24.99–25 / 24.99–25 | 24.92–24.94 / 24.99–25 / 24.99–25 | 0 / 16.67 / 33.33 | 80.5–80.8 |
| fling | `transform` | 10 | 49.98–49.99 / 50.83–75.5 / 50.83–75.5 | 49.98–49.99 / 50.83–75.5 / 50.83–75.5 | 1.59–1.68 / 17.46–18.68 / 50.83–75.5 | 93.0–95.7 |
| fling | `none` | 10 | 0 / 0 / 0 | 72.1–74.03 / 75.51 / 75.51 | 8.17–8.19 / 29.18–31.81 / 75.51 | 93.5–94.2 |
| fling | `predict1` | 10 | 0.84–0.96 / 0.96 / 0.96 | 37.51–61.42 / 61.33–62.5 / 61.33–62.5 | 0.42–0.62 / 16.67–16.73 / 61.33–62.5 | 94.8–95.3 |
| fling | `predict2` | 10 | 25.95 / 26.16 / 26.16 | 28.79–47.41 / 53.92–54.17 / 53.92–54.17 | 0.38–0.49 / 12.18–14.47 / 53.92–54.17 | 95.9–97.8 |
| fling | `predict3` | 10 | 48.35–49.68 / 51.57 / 51.57 | 48.35–49.68 / 51.57 / 51.57 | 4.06–4.41 / 23.57 / 51.57 | 96.2–98.1 |
| reverse | `transform` | 19 | 8.33–16.67 / 16.67 / 16.67–25 | 16.67 / 25 / 25 | 8.33 / 16.67 / 25 | 98.1–98.8 |
| reverse | `none` | 19 | 25 / 25 / 25–33.33 | 25 / 25 / 25–33.33 | 16.67 / 25 / 33.33 | 98.5–99.0 |
| reverse | `predict1` | 19 | 24.85–24.95 / 25.13–33.17 / 33.27–33.28 | 24.85–24.95 / 25.13–33.17 / 33.27–33.28 | 8.33 / 16.67 / 33.27–33.28 | 97.5–99.3 |
| reverse | `predict2` | 19 | 33.18–33.2 / 41.42–41.56 / 41.46–41.6 | 33.18–33.2 / 41.42–41.56 / 41.46–41.6 | 0–8.33 / 8.33 / 41.46–41.6 | 97.5–99.1 |
| reverse | `predict3` | 19 | 41.43–41.53 / 41.63–49.9 / 49.75–49.97 | 41.43–41.53 / 41.63–49.9 / 49.75–49.97 | 8.33 / 16.67 / 49.75–49.97 | 97.8–100.0 |

Where the two runs agree, the tables give one value; otherwise they give the range.

- In pans and in the stop and reverse phases, the errors are whole multiples of one Flutter frame's movement (speed / 120 Hz, 8.33 px at 1,000 px/s), so a p50 is either 0 or a multiple of 8.33 px. In pan1000, `predict1` had p50 0 in one run and 8.33 px in the other, so about half of its frames were exact.
- The mean offset along the pan increases with the lead: in pan1000, from about −14 px with `none`, through −4 to −6 px with `predict1`, to +2 to +4 px with `predict2` and +10.5 px with `predict3`. The transform is +8 px, ahead: Flutter often displays a newer map frame than the one the transform was built for, and the transform then moves the map too far.
- Without the transform, the map is behind the overlays after a stop or a fling (overshoot ahead 0). Prediction runs ahead after a change by about the lead: after a stop, 8.3, 16.6 and 24.9 px at p50 for leads 1, 2 and 3. In the fling, `predict1` was ahead by at most 0.96 px, `predict2` by 26 px and `predict3` by 52 px.
- In the fling, the transform's overshoot ahead (50 px at p50) comes from its movement during the fling's peak speed, not from prediction.
- The map frame rate didn't depend on the mode.

Conditions: the Setup's macOS device, OS, Xcode and Flutter versions and style; MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3` (`scripts/maplibre_ffi.lock`); copy-free rendering; AC power. The built-in display was the only display, scaled to 1800x1169 logical pixels ("More Space"), at 120 Hz. The window had 1600x1000 logical pixels, and all 90 result lines reported a 1600x1000 viewport. The thermal state was nominal at the start of every run and at the end of every phase. Each phase included 2,432 to 3,643 Flutter frames. Every build was matched to a frame timing and had a displayed map frame, and no display time fell outside a raster interval. Between 31 and 87 frames per phase were rasterized without a build.

Procedure, per mode:

```sh
cd example
flutter build macos --release --dart-define=ALIGNMENT_BENCHMARK=true --dart-define=ALIGNMENT_MODE=predict2
MLT_WINDOW_SIZE=1600x1000 \
  build/macos/Build/Products/Release/flutter_mapigrade_example.app/Contents/MacOS/flutter_mapigrade_example
```

### iPhone (task 4.2)

Measured 2026-10-11, release builds, 2 runs per mode, with the same phases as on macOS. Task 4.2 called for `transform`, `none` and the best lead from macOS (`predict1`); at the user's request `predict2` was also measured. The order was `transform`, `none`, `predict1`, then the same again, then `predict2` twice. The viewport was 430 px wide, so the fling started at 430 px/s, reached 1,324 px/s after 13.6 ms and stopped after 430 px.

| Phase | Mode | Drawn error p50 / p95 / max | Mean offset along the pan | Map fps |
| --- | --- | --- | --- | --- |
| pan 100 px/s | `transform` | 0.83 / 1.67 / 2.5–2.51 | 0.83 | 110.8–111.7 |
| pan 100 px/s | `none` | 1.67 / 2.5 / 4.17–5 | −1.65 to −1.6 | 108.0–108.4 |
| pan 100 px/s | `predict1` | 0.83 / 1.67 / 4.17 | −0.85 to −0.74 | 108.8–110.3 |
| pan 100 px/s | `predict2` | 0 / 0.84 / 4.16–4.17 | 0.08–0.13 | 109.8–111.7 |
| pan 500 px/s | `transform` | 4.17 / 8.35 / 12.53–12.54 | 4.04–4.16 | 108.6–109.3 |
| pan 500 px/s | `none` | 8.33 / 12.51 / 16.68–16.69 | −7.98 to −7.46 | 107.0–108.5 |
| pan 500 px/s | `predict1` | 4.17 / 8.34–8.35 / 12.52–12.53 | −3.77 to −3.71 | 109.2–110.1 |
| pan 500 px/s | `predict2` | 0.01 / 4.19 / 13.98–14.09 | 0.32–0.49 | 109.9–110.5 |
| pan 1,000 px/s | `transform` | 8.33 / 16.7 / 25.05–25.06 | 8.28–8.53 | 106.7–107.2 |
| pan 1,000 px/s | `none` | 16.67 / 25.02 / 25.08–33.37 | −16.45 to −15.55 | 107.2–107.4 |
| pan 1,000 px/s | `predict1` | 8.33 / 16.69 / 25.03–32.17 | −7.93 to −7.86 | 106.7–107.9 |
| pan 1,000 px/s | `predict2` | 0.02 / 8.37 / 33.7–36.41 | 0.35–0.58 | 107.3–109.0 |
| pan 2,000 px/s | `transform` | 16.67 / 33.39–33.4 / 50.12–50.14 | 16.87–16.97 | 108.5–109.0 |
| pan 2,000 px/s | `none` | 33.33 / 50.05–50.06 / 66.74–66.78 | −31.78 to −30.19 | 106.9–109.2 |
| pan 2,000 px/s | `predict1` | 16.67 / 33.39 / 61.53–62.78 | −16.37 to −14.85 | 107.8–108.5 |
| pan 2,000 px/s | `predict2` | 0.05 / 16.74–16.75 / 64.06–80.7 | 1.08–2.32 | 109.0–109.5 |
| zoom 1 level/s | `transform` | 2.96 / 5.96–5.98 / 8.99 | — | 102.5–103.5 |
| zoom 1 level/s | `none` | 2.98–2.99 / 8.97 / 14.6–14.62 | — | 102.7–103.2 |
| zoom 1 level/s | `predict1` | 0.02 / 5.96 / 11.71–11.92 | — | 102.8–103.3 |
| zoom 1 level/s | `predict2` | 2.95–2.96 / 2.99 / 11.17–13.54 | — | 102.8–104.2 |
| rotate 90°/s | `transform` | 6.72 / 13.46 / 20.19 | — | 102.5–102.8 |
| rotate 90°/s | `none` | 13.44 / 20.18 / 26.89–26.9 | — | 103.6 |
| rotate 90°/s | `predict1` | 6.72 / 13.47 / 20.16–20.18 | — | 101.8–103.7 |
| rotate 90°/s | `predict2` | 0.02 / 6.75 / 13.45–13.46 | — | 103.2–104.3 |

| Phase | Mode | Changes | Overshoot ahead p50 / p95 / max | Overshoot p50 / p95 / max | Drawn error p50 / p95 / max | Map fps |
| --- | --- | --- | --- | --- | --- | --- |
| stop | `transform` | 10 | 8.34–8.35 / 16.7–16.71 / 16.7–16.71 | 8.34–8.35 / 16.7–16.71 / 16.7–16.71 | 0 / 16.68 / 25.04–25.05 | 84.7–85.5 |
| stop | `none` | 10 | 0 / 0 / 0 | 14.67–14.71 / 16.49–22.58 / 16.49–22.58 | 2.67–3.16 / 25.02–25.03 / 41.68–41.7 | 83.3–85.0 |
| stop | `predict1` | 10 | 6.69–6.9 / 7.99–8.03 / 7.99–8.03 | 7.12–7.36 / 8.18–16.01 / 8.18–16.01 | 0.01–0.03 / 16.7 / 41.68–41.7 | 83.0–84.3 |
| stop | `predict2` | 10 | 14.67–14.7 / 16.5–16.52 / 16.5–16.52 | 14.67–14.7 / 16.5–16.52 / 16.5–16.52 | 0 / 8.37 / 41.71–41.74 | 81.8–85.9 |
| fling | `transform` | 10 | 21.2–21.25 / 30.68–31.23 / 30.68–31.23 | 21.2–21.25 / 30.68–31.23 / 30.68–31.23 | 1.11–1.15 / 16.65 / 30.68–31.23 | 105.1–105.8 |
| fling | `none` | 10 | 0 / 0 / 0 | 21.79–31.86 / 32.47 / 32.47 | 4.16–4.63 / 19.63–25.01 / 33.39–41.69 | 106.2–107.6 |
| fling | `predict1` | 10 | 0.12 / 0.43–0.46 / 0.43–0.46 | 21.38 / 24.3–24.31 / 24.3–24.31 | 1.67–1.94 / 16.67–16.68 / 32.67–33.32 | 104.2–106.2 |
| fling | `predict2` | 10 | 4.04–5.49 / 11.04–11.32 / 11.04–11.32 | 11.32–13.06 / 16.29–24.93 / 16.29–24.93 | 0.04 / 8.36 / 33.34–33.35 | 104.5–105.4 |
| reverse | `transform` | 19 | 8.34–12.77 / 16.71 / 16.72–25.01 | 16.73–25 / 25.04 / 25.04 | 8.33 / 16.7 / 25.05–25.09 | 107.5–108.5 |
| reverse | `none` | 19 | 25.03–25.06 / 25.06–25.09 / 25.07–25.1 | 25.03–25.06 / 25.06–25.09 / 25.07–25.1 | 16.67 / 25–25.04 / 33.31–33.36 | 107.9–108.0 |
| reverse | `predict1` | 19 | 22.33–22.58 / 24.59–25.06 / 25.22–30.59 | 22.33–22.58 / 24.59–25.06 / 25.22–30.59 | 8.34 / 16.71 / 25.22–30.59 | 107.2–107.8 |
| reverse | `predict2` | 19 | 27.99–29.31 / 36.41–38.31 / 38.91–39.93 | 27.99–29.31 / 36.41–38.31 / 38.91–39.93 | 0.02 / 8.38 / 38.91–39.93 | 106.9–109.0 |

Where the two runs agree, the tables give one value; otherwise they give the range.

- Unlike on macOS, `predict2` was closest to the overlays on the iPhone. In pan1000 its drawn error was 0.02 / 8.37 px (p50 / p95), and its mean offset along the pan was +0.35 to +0.58 px. `predict1` stayed about one frame behind, at −7.9 px, and its p50 of 8.33 px equaled the transform's.
- `predict2` was ahead after stops (14.7 px at p50), flings (4.0 to 5.5 px) and reversals (28 to 29 px).
- The transform's fling overshoot ahead was 21.2 px at p50, against 50 px on macOS, because the iPhone's fling is slower.
- The map frame rate didn't depend on the mode.

Conditions: the Setup's iPhone, OS, Xcode and Flutter versions and style; MapLibre Native FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3`; copy-free rendering. The phone was connected over Wi-Fi. Full screen, portrait, 430x932 logical pixels at pixel ratio 3; all 72 result lines reported a 430x932 viewport. Auto-Lock was off, and the app was launched with `MLT_KEEP_AWAKE=1`. The thermal state was nominal at the start of the `transform`, `none` and `predict1` runs, and at the end of each of their phases, except the fling and reverse phases of the second `predict1` run, which ended at fair. Both `predict2` runs started right after it and were at fair at their start and at the end of every phase. Their map frame rates matched the other modes. Each phase included 2,405 to 3,651 Flutter frames. Every build was matched to a frame timing and had a displayed map frame, and no display time fell outside a raster interval. Between 5 and 81 frames per phase were rasterized without a build.

Procedure: as for `benchmark.dart` (Setup), with `--dart-define=ALIGNMENT_BENCHMARK=true --dart-define=ALIGNMENT_MODE=<mode>` in the iOS build.

## Alignment with children (layer-children-alignment change)

With the overlays as children of the layer, the layer draws them at the `flutter_map` camera of the map frame it chose for the Flutter frame (designs D122 to D129 of the layer-children-alignment change). The alignment benchmark measures this configuration with `--dart-define=ALIGNMENT_CHILDREN=1` (design D129). It still finds the displayed map frame of each Flutter frame from the display times and Flutter's frame timings, and computes the error against the camera that the layer reports for its children (`onChildCamera`), so an error above 1 px would reveal a fault in the display slots. The lag is the distance at the viewport center between where the displayed map frame draws a coordinate and where the live `flutter_map` camera places it. With children the overshoot ahead is measured against the live camera. All errors and lags are in logical pixels; the phases are those of the camera-prediction change above.

The result lines also give the map thread's counters over each phase: the share of rendered frames that Flutter never displayed, the skipped renders per second (renders that found no free slot), and the most slots in use (rendering, ready or held) at once since the map was created.

Measured 2026-10-16 (macOS) and 2026-10-17 (both), release builds, 3 runs per mode, 20 s per phase, the fling 30 s. Where the runs agree, the tables give one value; otherwise they give the range.

### Frame rate before and after slots (task 5.3)

The frame-rate benchmark (`benchmark.dart`, Setup above) at the commit before this change (`2f092c2`) and with the change, alternating, 3 runs each. With the change, the benchmark's `MapTextureView` chooses the newest ready frame in each build.

| macOS | Before | After |
| --- | --- | --- |
| average map fps over 30 s | 103.8–105.4 | 103.8–105.9 |
| per-second p10 / p50 / p90 | 98–99 / 103–106 / 109–116 | 99–100 / 103–105 / 110–112 |
| lowest second | 94–96 | 94–98 |
| `render_update`, frame cycle | 7.57–7.62 ms, 8.99–9.07 ms | 7.60–7.63 ms, 8.97–9.01 ms |
| rendered frames not displayed | 4.9–6.0% | 5.0–6.5% |
| skipped renders | 0 | 0 |

| iPhone | Before | After |
| --- | --- | --- |
| average map fps over 30 s | 110.0–112.2 | 109.9–111.2 |
| per-second p10 / p50 / p90 | 104–105 / 108–113 / 117–119 | 105–106 / 110–111 / 115–117 |
| lowest second | 98–104 | 100–105 |
| `render_update`, frame cycle | 7.62–8.10 ms, 8.22–8.48 ms | 7.81–8.05 ms, 8.21–8.39 ms |
| rendered frames not displayed | 6.8–8.0% | 7.5–8.8% |
| skipped renders | 0 | 0 |

The slots changed neither frame rate beyond the variation between runs. On macOS the two builds alternated, before first. On the iPhone, which ran over Wi-Fi, unplugged and out of its case after cooling, the order was before, after, after, before, after, before; the first install failed, and its before run was repeated last. An earlier series on 2026-10-17, while the iPhone was charging in its case, fell from 112.8 to 90.9 fps over six runs on both builds as the phone heated (`render_update` from 7.7 to 10.2 ms); we discarded it.

### macOS

| Phase | Mode | Frames over 1 px | Error p50 / p95 / max | Lag p50 / p95 / max | Overshoot ahead p50 / max | Map fps | Rendered frames not displayed | Skipped renders per s | Most slots in use |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pan 100 px/s | `predict1` | 0 of 7363 | 0 / 0 / 0 | 0.83 / 1.67 / 3.33 | – | 101.7–102.2 | 6.8–7.1% | 0 | 4 |
| pan 500 px/s | `predict1` | 0 of 7398 | 0 / 0 / 0 | 4.17 / 8.33 / 12.53–16.67 | – | 102.8–103.3 | 6.8–7.3% | 0 | 4 |
| pan 1,000 px/s | `predict1` | 0 of 7394 | 0 / 0 / 0 | 8.33 / 16.67 / 25.01–116.67 | – | 100.5–102.5 | 7.3–7.9% | 0–0.1 | 4 |
| stop | `predict1` | 0 of 7318 | 0 / 0 / 0 | 0 / 16.67 / 33.33 | 8.27–8.31 / 8.33 | 80.9–81.7 | 7.7–8% | 0 | 4 |
| fling | `predict1` | 0 of 10940 | 0 / 0 / 0 | 0.81–1 / 16.67–17.64 / 56.37–87.19 | 0.69–0.95 / 0.88–0.96 | 96.3–96.7 | 7.1–7.8% | 0 | 4 |
| reverse | `predict1` | 0 of 7371 | 0 / 0 / 0 | 8.33 / 16.67 / 33.24–33.32 | 24.85–24.99 / 33.24–33.32 | 98.2–99.2 | 7.9–8% | 0 | 4 |
| pan 100 px/s | `none` | 0 of 7366 | 0 / 0 / 0 | 1.67 / 2.5 / 3.33–4.17 | – | 101.2–102.4 | 6.7–7.4% | 0 | 4 |
| pan 500 px/s | `none` | 0 of 7397 | 0 / 0 / 0 | 8.33 / 12.5 / 16.67–20.83 | – | 100.8–104.8 | 6.3–7.2% | 0 | 4 |
| pan 1,000 px/s | `none` | 0 of 7405 | 0 / 0 / 0 | 16.67 / 25 / 33.33 | – | 101.3–102.2 | 7.2–7.7% | 0 | 4 |
| stop | `none` | 0 of 7317 | 0 / 0 / 0 | 0.02–0.07 / 25 / 33.33–58.33 | 0 / 0 | 81.2–82.7 | 7.1–7.5% | 0 | 4 |
| fling | `none` | 0 of 10942 | 0 / 0 / 0 | 8.33 / 27.66–33.33 / 69.24–99.53 | 0 / 0 | 93.9–96.5 | 7.3–7.4% | 0 | 4 |
| reverse | `none` | 0 of 7373 | 0 / 0 / 0 | 16.67 / 25 / 33.33–41.67 | 25 / 33.33 | 99.1–99.6 | 7.7–8.1% | 0 | 4 |

- No Flutter frame had an error over 1 px: the children were drawn at the camera of the displayed map frame in every frame. Camera prediction changes only the lag: with `predict1` the children trail the live camera by one Flutter frame of movement at p50 in pans (8.33 px at 1,000 px/s), with `none` by two (16.67 px).
- In one phase, pan 1,000 px/s of the second `predict1` run, the map skipped 2 renders while Flutter presented frames, and the lag reached 116.67 px, a stall of about 117 ms. Every other phase had no skipped render. Every phase used all four slots at some time.
- Before the fix of design D123, in which Dart keeps the frame it chose before when the map refuses a choice, 10 s runs on 2026-10-16 had 1 frame over 1 px (8.33 px) in each of the fling and reverse phases.

Conditions: the Setup's Mac, OS, Xcode and Flutter versions and style; copy-free rendering; AC power; the display scaled to "More Space"; window 1600x1000, which gave a 1600x917 map viewport. The Android emulator and the iOS simulator were shut down, and `caffeinate -d` kept the display on for the runs on 2026-10-17. Three runs on 2026-10-16 were repeated because the display turned off during them. The thermal state was nominal at the end of every phase.

### iPhone

| Phase | Mode | Frames over 1 px | Error p50 / p95 / max | Lag p50 / p95 / max | Overshoot ahead p50 / max | Map fps | Rendered frames not displayed | Skipped renders per s | Most slots in use |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pan 100 px/s | `predict1` | 0 of 7224 | 0 / 0 / 0 | 0.83 / 1.67 / 3.34–4.17 | – | 108.7–110.2 | 6.1–10.7% | 0 | 4 |
| pan 500 px/s | `predict1` | 0 of 7435 | 0 / 0 / 0 | 4.16–4.17 / 8.33–8.35 / 12.57–16.68 | – | 106.6–109.1 | 9.4–10.5% | 0 | 4 |
| pan 1,000 px/s | `predict1` | 0 of 7473 | 0 / 0 / 0 | 8.32–8.34 / 16.67–16.7 / 33.3–33.38 | – | 105.3–106.7 | 8.3–10.4% | 0 | 4 |
| stop | `predict1` | 0 of 7314 | 0 / 0 / 0 | 0–0.03 / 16.63–16.7 / 41.67–41.73 | 3.32–6.43 / 7.57–8.01 | 82.4–84.7 | 2.7–9.2% | 0 | 4 |
| fling | `predict1` | 0 of 10968 | 0 / 0 / 0 | 0.71–1.87 / 13.06–16.67 / 33.36–41.73 | 0.14–0.44 / 0.45–0.7 | 106.2–107.3 | 6.3–11.1% | 0 | 4 |
| reverse | `predict1` | 0 of 7391 | 0 / 0 / 0 | 8.34 / 16.68–16.69 / 33.36–41.63 | 21.47–24.4 / 25.06–39.03 | 108–109.8 | 8.5–10.6% | 0 | 4 |
| pan 100 px/s | `none` | 0 of 7292 | 0 / 0 / 0 | 1.67 / 2.5 / 3.34–4.18 | – | 106.2–111.5 | 7.1–8.6% | 0 | 4 |
| pan 500 px/s | `none` | 0 of 7434 | 0 / 0 / 0 | 8.33 / 12.51 / 16.7–20.85 | – | 106.8–109.2 | 9.7–11% | 0 | 4 |
| pan 1,000 px/s | `none` | 0 of 7474 | 0 / 0 / 0 | 16.67 / 25–25.02 / 33.4–41.68 | – | 106.7–107.7 | 10.1–10.4% | 0 | 4 |
| stop | `none` | 0 of 7313 | 0 / 0 / 0 | 0.87–2.64 / 25–25.01 / 41.68–41.72 | 0 / 0 | 85.8–86.9 | 7.3–8.4% | 0 | 4 |
| fling | `none` | 0 of 10971 | 0 / 0 / 0 | 4.41–4.58 / 21.01–24.98 / 40.35–49.99 | 0 / 0 | 107.1–107.8 | 7.3–8.5% | 0 | 4 |
| reverse | `none` | 0 of 7396 | 0 / 0 / 0 | 16.67 / 25.03–25.04 / 33.42–33.45 | 25.07–33.33 / 33.42–33.45 | 105.2–109.3 | 6.4–8.4% | 0 | 4 |

- As on macOS, no Flutter frame had an error over 1 px, no phase skipped a render, and every phase used all four slots at some time.

Conditions: the Setup's iPhone, OS, Xcode and Flutter versions and style; copy-free rendering; full screen, portrait, 430x932 logical pixels at pixel ratio 3; connected by cable and charging, in its case, launched with `MLT_KEEP_AWAKE=1`. The thermal state was fair at the start of the first run and serious at the end of every phase, so the map frame rates are lower than at nominal; the errors don't depend on the frame rate.

Procedure: as for the alignment benchmark above, with `--dart-define=ALIGNMENT_CHILDREN=1 --dart-define=ALIGNMENT_MODE=<mode> --dart-define=ALIGNMENT_PHASES=pan100,pan500,pan1000,stop,fling,reverse`.

### Pitched map (macOS, add-pitch change, task 4.3)

The benchmark with children at a `flutter_map` pitch of 45 degrees (`--dart-define=ALIGNMENT_PITCH=45`), which the layer passes to MapLibre. The error and the lag are computed with the pitched projection. Measured 2026-10-24, release build, one run, `flutter_map` from the fork (`8.4.0-dev.1`, commit `04c3e14` on its `map-pitch` branch).

| Phase | Mode | Frames over 1 px | Error p50 / p95 / max | Lag p50 / p95 / max | Map fps | Rendered frames not displayed | Skipped renders per s | Most slots in use |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pan 1,000 px/s | `predict1` | 0 of 2401 | 0 / 0 / 0 | 8.33 / 16.67 / 41.71 | 107.1 | 5.2% | 0 | 3 |

- As unpitched, no Flutter frame had an error over 1 px: the children were drawn at the camera, pitch included, of the displayed map frame in every frame. The lag matches the unpitched `predict1` pan at 1,000 px/s.

Conditions: the Setup's Mac, OS, Xcode and Flutter versions; the Liberty style; copy-free rendering; window 1600x1000, which gave a 1600x1000 map viewport; `caffeinate -dims` kept the display on. The thermal state was nominal at the end of the phase.

Procedure: as for the alignment benchmark above, with `--dart-define=ALIGNMENT_CHILDREN=1 --dart-define=ALIGNMENT_PITCH=45 --dart-define=ALIGNMENT_PHASES=pan1000`.

## The port to the FFI core executor (adopt-ffi-core-executor change, task 8.2)

Measured 2026-10-22: `main` at `d71c9bc` (MapLibre Native FFI 0.202610.1) against the change (FFI 0.202610.2, maplibre-native-ffi#760), 3 runs each, alternating, release builds, copy-free, rendering ahead with the hysteresis (the default). Mac: MacBook Pro (M2 Max), window 1600x1000 on the built-in display at 120 Hz, AC power. iPhone 15 Pro Max over Wi-Fi on battery; iPhone 13 and Pixel 4a (5G) on cable. The thermal state was nominal throughout, except on the iPhone 15 Pro Max, where it was fair at the end of some alignment runs of both builds. `main`'s harness got two changes that don't touch the map: the window placement of `MLT_WINDOW_SCREEN=builtin` on the Mac, and the short `BENCHMARK_KEY` line on Android, whose log truncates the full result line. `main` has no camera latency statistic (design D189).

Frame-rate benchmark (30 s pan):

| Device | Displayed map fps, `main` | change | Service call or `render_update` (ms), `main` | change | Camera latency avg (ms), change |
| --- | --- | --- | --- | --- | --- |
| Mac | 108.5–112.0 | 113.3–116.8 | 7.24–7.42 | 6.21–6.43 | 6.38–6.54 |
| iPhone 15 Pro Max | 109.9–110.8 | 107.5–108.4 | 7.83–7.93 | 8.18–8.21 | 10.89–10.94 |
| iPhone 13 (60 Hz) | 55.3–55.5 | 54.4–54.9 | 13.85–14.04 | 13.49–13.65 | 15.5–16.0 |
| Pixel 4a (5G) (60 Hz) | 51.9–53.4 | 51.9–52.6 | 7.72–7.95 | 7.68–7.86 | 30.1–30.4 |

Alignment benchmark with children (`ALIGNMENT_CHILDREN=1`, mode `predict1`, the phases of the camera-prediction change, 20 s per phase). The drawn error was 0 px at max in every phase of every run on all three devices and both builds. Ranges over 3 runs:

| Phase | Mac: service (ms), `main` | change | Mac: lag p50 / p95 (px), `main` | change |
| --- | --- | --- | --- | --- |
| pan100 | 7.47–7.49 | 6.88–7.02 | 0 / 1.29–1.67 | 0 / 0.83–0.84 |
| pan500 | 7.30–7.39 | 6.67–6.77 | 0 / 4.17–8.33 | 0 / 4.17 |
| pan1000 | 7.29–7.46 | 6.74–6.84 | 0 / 8.34–16.67 | 0 / 8.33–8.34 |
| stop | 7.57–7.67 | 7.06–7.19 | 0 / 8.34–16.66 | 0 / 8.33–16.56 |
| fling | 7.53–7.63 | 7.07–7.16 | 0.06–0.13 / 16.67 | 0.03–0.05 / 11.48–15.04 |
| reverse | 7.57–7.61 | 7.12–7.23 | 0–8.33 / 16.67 | 0 / 16.55–16.67 |

| Phase | iPhone 15 Pro Max: service (ms), `main` | change | lag p50 (px), `main` | change | iPhone 13: service (ms), `main` | change | lag p50 (px), `main` | change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pan100 | 7.26–8.51 | 8.38–8.57 | 0.83 | 0.83 | 15.06–15.23 | 15.00–15.27 | 1.66 | 1.66–1.67 |
| pan500 | 7.80–7.88 | 8.30–8.50 | 4.17 | 4.17 | 14.15–14.24 | 13.77–13.95 | 0.02–0.03 | 0.02 |
| pan1000 | 8.10–8.19 | 8.36–8.62 | 8.33 | 8.34 | 14.67–14.76 | 14.20–14.27 | 0.18–16.54 | 0.05–0.06 |
| stop | 9.05–9.35 | 9.24–9.63 | 0.01–0.02 | 0.04–1.35 | 15.57–15.79 | 15.23–15.41 | 0.01–0.02 | 0.01 |
| fling | 8.42–8.77 | 8.65–8.89 | 1.74–1.96 | 1.98–2.07 | 16.03–16.19 | 15.57–15.91 | 1.40–1.97 | 0.25–0.91 |
| reverse | 8.63–8.98 | 8.86–9.31 | 8.34 | 8.34 | 15.94–16.03 | 15.72–15.74 | 16.71 | 16.71–16.72 |

The change's camera latency in the alignment benchmark was 6.8–8.5 ms on the Mac, 11.5–14.0 ms on the iPhone 15 Pro Max and 15.6–23.3 ms on the iPhone 13.

On the Mac and the iPhone 13 a frame renders faster with the change than with the FFI before #760, and the lag is the same or lower. On the iPhone 15 Pro Max a frame renders 0.1 to 0.6 ms slower and the displayed map frame rate is about 2% lower, because iOS runs the map thread mostly on the efficiency cores once no per-frame allocation happens (design D188, `maplibre-pr-760-port-findings.md`); the lag is the same in every phase but stop and fling, where its median is up to 1.3 px larger. On the Pixel the change and `main` don't differ beyond the variation between runs.

## No CPU readback on the frame path

### macOS (Stage 1, task 7.3)

Source: a search of the plugin and the example (`src/`, `macos/` (now `darwin/`), `lib/`, `example/lib/` (now `packages/test_harness/lib/`)) for `mln_texture_read_premultiplied_rgba8`, `getBytes`, `CVPixelBufferLockBaseAddress`, `CVPixelBufferGetBaseAddress`, `IOSurfaceLock` and `replaceRegion` found no matches. The frame path is `mln_render_session_render_update` into a private `MTLTexture`, an `MTLBlitCommandEncoder` copy into an IOSurface-backed `CVPixelBuffer`, and `-[FlutterTexture copyPixelBuffer]` returning that pixel buffer.

Trace: in the Metal System Trace of the benchmark run (about 100 s, including the 60 s of continuous pan), the process's encoders were 13,872 render encoders and 6,577 blit encoders, with no compute encoders. In the trace's 33,477 time-profile samples, the frame-path functions appear (`MapTexture::MaybeRender`, `CopyToBuffer`, `mln_render_session_render_update`, `copyPixelBuffer`), while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes` and `mln_texture_read_premultiplied_rgba8` appear 0 times.

### iPhone (iOS slice, task 5.7)

A 20 s Metal System Trace on the iPhone 15 Pro Max (`xcrun xctrace record --device <id> --template 'Metal System Trace' --attach <pid>`, 2026-10-10), attached to a release build of the example panning continuously (`--dart-define=CONTINUOUS_PAN=true`): the app's encoders were 4,966 render encoders and 2,050 blit encoders, with no compute encoders; 4,100 were encoded on the map thread and 2,916 on Flutter's raster thread. Of the 12,808 time-profile samples, `mln_render_session_render_update` appears in 6,032, the plugin's blit (`-[IOGPUMetalBlitCommandEncoder copyFromTexture:toTexture:]` from `MetalRenderTarget::CopyToBuffer`) in 121 and `copyPixelBuffer` in 77, while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes`, `replaceRegion` and `mln_texture_read_premultiplied_rgba8` appear 0 times. Two samples are in `IOSurfaceClientGetBaseAddressOfPlane`; both are called by the Metal driver's `getGPUVirtualAddress` while it encodes the plugin's blit, which computes a GPU address, not a CPU read.

## Color check

`packages/test_harness/lib/color_check.dart` (`flutter run -d macos -t lib/color_check.dart`) shows a map whose style has a `#3366CC` background and a `#E6B31A` fill, and Flutter swatches of the same colors below it. In a window screenshot (Display P3, 2026-10-09) the map and the swatches measured:

| Color | Map | Flutter swatch | Largest channel difference |
| --- | --- | --- | --- |
| fill `#E6B31A` | 222, 181, 67 | 222, 181, 67 | 0 |
| background `#3366CC` | 64, 101, 197 | 64, 100, 197 | 1 |

Both are within the 2/255 tolerance, so the IOSurface buffers need no explicit color space. On the iPhone, `packages/test_harness/integration_test/color_measurement.dart` renders the same screen to an image with `RepaintBoundary.toImage` and compares the pixels: the map and the swatches had identical values (fill 230, 179, 26; background 51, 102, 204; 2026-10-10).
