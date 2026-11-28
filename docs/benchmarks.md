# Benchmarks

## Summary

On 2026-11-27 we measured `MapigradeMap` in release builds, panning for 10 s over central London at 500 logical pixels per second with the OpenFreeMap Liberty style. The table gives the average number of map frames that MapLibre rendered per second over the pan, from one run per device and pitch. The map rendered at or near the display's refresh rate on every device, except on the Pixel at pitch 60:

| Device (display refresh rate) | Pitch 0 | Pitch 60 |
| --- | --- | --- |
| MacBook Pro, M2 Max (120 Hz) | 118 | 113 |
| iPhone 15 Pro Max (120 Hz) | 120 | 119 |
| iPhone 13 (60 Hz) | 59 | 56 |
| Pixel 4a (5G) (60 Hz) | 57 | 25 |

All the benchmarks below also used release builds and the OpenFreeMap Liberty style over central London.

Other `MapigradeMap` results (2026-11-27, at pitch 0 and at pitch 60):

- On the Mac and both iPhones, markers and children were drawn within 0.03 logical pixels of the position the displayed map frame draws them at, in every Flutter frame. Android reports no display times, so we couldn't measure this on the Pixel.
- On the Mac and both iPhones, Flutter displayed frames at the display's refresh rate during pans, with 0, 100 or 1,000 markers. The map rendered at least 111 frames per second on the 120 Hz devices and at least 55 on the iPhone 13. 1,000 markers added about 1 ms to the build time of a Flutter frame.
- On the Pixel at pitch 0, the map rendered 53 to 57 frames per second. At pitch 60 it rendered 25 to 35, and Flutter displayed 39 to 43.
- From Flutter's dispatch of a pointer move until the first displayed map frame that includes the move took, at the median, 16.5 to 26.2 ms on the Mac and the iPhone 15 Pro Max, 23.3 to 36.5 ms on the iPhone 13, and 44.6 ms at pitch 0 and 97.8 ms at pitch 60 on the Pixel.

Frame rate and `MapigradeLayer`:

- During a continuous 30 s pan of a map without `flutter_map`, the map displayed 99 to 100 frames per second on the Mac, 108 on the iPhone 15 Pro Max, 54 to 55 on the iPhone 13, and 52 to 54 on the Pixel. Our go/no-go values are a 30 fps minimum and a 60 fps target. Each device meets the minimum, and the Mac and the iPhone 15 Pro Max meet the target. The iPhone 13 and the Pixel, whose displays refresh at 60 Hz, miss the target.
- Over a 5-minute pan, the frame rate didn't decrease on the iPhone 15 Pro Max or the Pixel, and their thermal state stayed nominal.
- With the overlays as children of the layer, the drawn error was 0 logical pixels in every Flutter frame on the Mac and both iPhones. The map and the children together lag behind the live `flutter_map` camera. With the default alignment (prediction with a lead of 1), during a pan at 1,000 logical pixels per second, the median lag was 0 to 8.33 logical pixels on the Mac, 8.34 on the iPhone 15 Pro Max and 0.05 on the iPhone 13. 8.33 logical pixels is the camera movement in one Flutter frame at 120 Hz.
- These results are from MapLibre Native FFI 0.202610.2 and 0.202610.3, except one Pixel frame rate run (54 frames per second) with the mln-rs-based FFI that Mapigrade uses now. On the Mac, the mln-rs-based FFI rendered faster: the map displayed 119.3 to 119.5 frames per second against 100.7 to 112.0 with 0.202610.3, the drawn error stayed 0 px, and the lag of the children at p95 decreased from up to 16.67 px to under 1 px (2026-11-27, "`MapigradeLayer` with the mln-rs-based FFI"). We haven't run these benchmarks with that FFI on the iPhones or the Pixel.

Checks of the frame path:

- The frame path has no CPU readback: the plugin's sources contain no readback call, and Metal System Traces on the Mac and the iPhone 15 Pro Max recorded none.
- On the Mac, the iPhone 15 Pro Max and the Pixel, map colors matched Flutter's within 1/255 per channel.

## Terms

- A *map frame* is a frame that MapLibre rendered. A map frame *finishes* when its GPU work has completed.
- A *displayed map frame* is a map frame that Flutter displayed. On macOS and iOS the benchmarks count each distinct map frame that Flutter took from the texture. Android reports no display times (design D52), so on Android the benchmarks count each map frame that Dart chose for a Flutter frame.
- The *drawn error* of a Flutter frame is the largest distance, over a set of positions on the map, between where the displayed map frame draws a coordinate and where Flutter draws the overlays, markers or children at that coordinate.
- The *lag* is the distance at the viewport center between where the displayed map frame draws a coordinate and where the live camera places it.
- *Per-second* values count the displayed map frames in each whole second of the measured pass. p10 means that 10% of seconds had that many frames or fewer.
- Distances are in logical pixels (px).

## Devices

| | Mac | iPhone 15 Pro Max | iPhone 13 | Pixel 4a (5G) |
| --- | --- | --- | --- | --- |
| Model | MacBook Pro (Mac14,5), Apple M2 Max, 12 CPU cores (8 performance, 4 efficiency) | iPhone16,2 | iPhone14,5 | `bramble`, Qualcomm SM7250 (Snapdragon 765G), Adreno 620 |
| Display | built-in Liquid Retina XDR, 120 Hz | ProMotion, 120 Hz (`CADisableMinimumFrameDurationOnPhone` is set) | 60 Hz | 60 Hz (its only mode) |
| Map size | window 1600x1000 logical pixels at pixel ratio 2, 3200x2000 physical pixels; the built-in display as the only display, scaled to 1800x1169 logical pixels ("More Space") so that the window fits | full screen, portrait, 430x932 logical pixels at pixel ratio 3, 1290x2796 physical pixels | full screen, portrait, 390x844 logical pixels | full screen, portrait, 411x867 logical pixels at pixel ratio 2.625, 1080x2277 physical pixels |
| Renderer | Impeller (Metal) | Impeller (Metal) | Impeller (Metal) | Impeller (OpenGL ES): Flutter tried Impeller's Vulkan backend on the Adreno 620 and then used OpenGL ES. MapLibre renders with EGL (FFI preset `android-arm64-egl`). |

The Mac ran on AC power. On the iPhones, Auto-Lock was off, and the apps were launched with `MLT_KEEP_AWAKE=1`. The Pixel's screen was kept on and unlocked. Except where a section states otherwise, maps were copy-free (the default): MapLibre rendered each frame directly into the buffer that Flutter displays.

## `MapigradeMap`

`packages/test_harness/lib/map_benchmark.dart` measures `MapigradeMap` in three phases. The map shows central London at zoom 14, at pitch 0 or 60. A warm-up first eases along the path from 51.5115, -0.14 to 51.5115, -0.06 over 12 s and runs the motion of the alignment phase once, so that the cache contains every view that the phases show.

- Alignment: the camera controller eases back and forth along the path twice (4 s each way, the bearing turning to 30 degrees and back) and flies out and back (zoom 14 to 13, 4 s each way). The drawn error is measured over a grid of 9 positions in the lower 60% of the map, between the map frame that the map chose in the build, which is where its children and markers are placed, and the map frame that Flutter displayed. The phase finds the displayed map frame from the display times, so it doesn't measure the drawn error on Android.
- Latency: 20 steps of a drag of synthetic pointer events, 8 px each and 600 ms apart, after the drag has passed the pan slop. For each step, the latency is the time from Flutter's dispatch of the move until the report of the first displayed map frame whose camera moved reaches Dart. It doesn't include the time from the touch until Flutter's dispatch.
- Markers: the camera controller moves the camera east at 500 px/s on every Flutter frame for 10 s, with 0, 100 and 1,000 upright markers of 12x18 px on a grid around the path. The phase reports Flutter frames per second, map frames per second (finished map frames), and the build and raster times of the Flutter frames.

Measured 2026-11-27, one run per device and pitch, at commit `6145097` with the uncommitted changes of add-mapigrade-map. Flutter 3.47.9 stable (framework `c197ca5199`), Dart 3.13.7, Xcode 27.2 (27B52), MapLibre Native FFI commit `4371ff607e0bd22115d390de27d72a54987cc6c7`. macOS 26.7.3 (25G342), iOS 27.2.1 (24B156) on the iPhone 15 Pro Max, iOS 26.2 (23C55) on the iPhone 13, Android 14 (API 34) on the Pixel. The thermal state was nominal at the start and at the end of every run.

### Pitch 0

| | Mac | iPhone 15 Pro Max | iPhone 13 | Pixel 4a (5G) |
| --- | --- | --- | --- | --- |
| Drawn error, p50 / p90 / max | 0 / 0 / 0.00 px | 0 / 0 / 0.00 px | 0 / 0 / 0.02 px | not measured |
| Flutter frames with a drawn error over 1 px | 0 | 0 | 0 | not measured |
| Eases and flights: Flutter / map frames per second | 118 / 123 | 106 / 118 | 60 / 61 | 59 / 53 |
| Latency, p50 / p90 / max | 16.5 / 20.3 / 21.0 ms | 16.8 / 20.7 / 21.0 ms | 23.3 / 30.9 / 32.3 ms | 44.6 / 63.8 / 69.3 ms |
| Pan, 0 markers: Flutter / map frames per second | 119.9 / 117.8 | 119.9 / 119.6 | 59.9 / 59.4 | 59.7 / 56.6 |
| Pan, 100 markers: Flutter / map frames per second | 120.0 / 119.3 | 119.9 / 119.2 | 59.9 / 59.2 | 59.3 / 56.4 |
| Pan, 1,000 markers: Flutter / map frames per second | 120.0 / 118.8 | 119.9 / 118.2 | 59.9 / 59.1 | 58.7 / 56.5 |
| Build p50 / p90, 0 markers | 0.11 / 0.16 ms | 0.19 / 0.23 ms | 0.32 / 0.41 ms | 0.69 / 7.54 ms |
| Build p50 / p90, 1,000 markers | 0.85 / 1.46 ms | 1.03 / 1.55 ms | 1.68 / 2.37 ms | 2.66 / 9.46 ms |

### Pitch 60

| | Mac | iPhone 15 Pro Max | iPhone 13 | Pixel 4a (5G) |
| --- | --- | --- | --- | --- |
| Drawn error, p50 / p90 / max | 0 / 0 / 0.01 px | 0 / 0 / 0.03 px | 0 / 0 / 0.03 px | not measured |
| Flutter frames with a drawn error over 1 px | 0 of 2,625 | 0 of 2,625 | 0 of 1,317 | not measured |
| Eases and flights: Flutter / map frames per second | 109 / 123 | 109 / 120 | 55 / 60 | 42 / 35 |
| Latency, p50 / p90 / max | 22.0 / 29.4 / 36.5 ms | 26.2 / 33.7 / 36.2 ms | 36.5 / 42.8 / 48.8 ms | 97.8 / 141.9 / 161.8 ms |
| Pan, 0 markers: Flutter / map frames per second | 120.0 / 113.0 | 119.9 / 119.3 | 59.9 / 55.7 | 42.6 / 24.9 |
| Pan, 100 markers: Flutter / map frames per second | 120.0 / 111.5 | 119.9 / 119.8 | 59.9 / 58.4 | 41.8 / 24.6 |
| Pan, 1,000 markers: Flutter / map frames per second | 120.0 / 116.3 | 119.9 / 114.9 | 59.9 / 57.0 | 38.8 / 25.5 |
| Build p50 / p90, 0 markers | 0.09 / 0.13 ms | 0.07 / 0.12 ms | 0.12 / 0.32 ms | 0.81 / 26.65 ms |
| Build p50 / p90, 1,000 markers | 0.66 / 1.08 ms | 0.59 / 0.91 ms | 0.83 / 1.52 ms | 4.03 / 29.14 ms |
| Raster p50 / p90, 0 markers | 0.18 / 0.27 ms | 0.11 / 0.16 ms | 0.18 / 0.38 ms | 11.18 / 32.81 ms |

On the Pixel, the pitch lowers the frame rates. At pitch 0 the map renders 53 to 57 frames per second, as in the 30 s pan of `benchmark.dart` on the same phone on the same day (54 displayed map frames per second). At pitch 60 it renders 25 to 35. A pitched view shows many more tiles toward the horizon, and Flutter's raster times increase with the map's GPU work, because Flutter and the map use the same GPU.

### Procedure

```sh
cd packages/test_harness
# --dart-define=MAP_BENCHMARK_PITCH=0 for pitch 0; the default is 60
flutter build macos --release --dart-define=MAP_BENCHMARK=true
open -W --env MLT_WINDOW_SIZE=1600x1000 --stdout result.txt \
  build/macos/Build/Products/Release/test_harness.app
flutter build ios --release --dart-define=MAP_BENCHMARK=true
xcrun devicectl device install app --device <device> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <device> --console \
  -e '{"MLT_KEEP_AWAKE":"1"}' com.greensopinion.mapigradeTestHarness
flutter build apk --release --dart-define=MAP_BENCHMARK=true
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -S -n com.greensopinion.mapigrade_test_harness/.MainActivity
adb logcat -s flutter | grep MAP_BENCHMARK
```

The app prints one line starting with `MAP_BENCHMARK_RESULT` per phase, then exits.

## Frame rate during a continuous pan

`packages/test_harness/lib/benchmark.dart` shows the map in the internal `MapTextureView` widget, without `flutter_map`, and sets the camera on every Flutter frame for 30 s. The camera pans east at zoom 14 from 51.5115, -0.14 (Charing Cross) through Covent Garden, the City, Whitechapel and Limehouse, at 0.2 tile widths per second (0.0044 degrees of longitude per second, about 102 px per second). The path has dense streets, buildings and labels throughout. A first 30 s pass over the same path loads the area into the cache. The camera then goes back to the start, and the map reaches idle before the measured pass.

On macOS and iOS the map renders ahead (design D19): while a frame takes longer than a refresh interval, the next frame renders without waiting until Flutter has taken the previous one. On Android the map renders at most one frame per display refresh interval (design D53).

### Results

| | Mac | iPhone 15 Pro Max | iPhone 13 | Pixel 4a (5G) |
| --- | --- | --- | --- | --- |
| Measured | 2026-11-01 | 2026-10-22 | 2026-10-22 | 2026-10-22 |
| MapLibre Native FFI | 0.202610.3 | 0.202610.2 | 0.202610.2 | 0.202610.2 |
| Displayed map frames per second, average over 30 s | 99.2–100.1 | 107.5–108.4 | 54.4–54.9 | 51.9–52.6 |
| `render_update`, average | 6.89–6.97 ms | 8.18–8.21 ms | 13.49–13.65 ms | 7.68–7.86 ms |
| Camera latency, average | 7.23–7.43 ms | 10.89–10.94 ms | 15.5–16.0 ms | 30.1–30.4 ms |

Each value is the range over 3 runs. `render_update` is the map thread's call that renders a frame. The camera latency is the time from the call that sets a camera until the first map frame rendered with that camera finishes.

On 2026-11-27, one run on the Pixel at commit `6145097` with the mln-rs-based FFI (commit `4371ff607e0bd22115d390de27d72a54987cc6c7`) displayed 54 map frames per second.

Conditions:

- Mac: macOS 26.6.2, Flutter 3.47.7, window placed on the built-in display (`MLT_WINDOW_SCREEN=builtin`), `caffeinate -dims` running. The Android emulator and the iOS simulator were shut down. Skipped renders: 0. The longest `render_update` was 15.3–18.2 ms.
- iPhone 15 Pro Max over Wi-Fi on battery; iPhone 13 and Pixel on cable. The thermal state was nominal throughout.

### 5-minute pan

The measured pass pans back and forth over the warm-up path for 300 s (`--dart-define=BENCHMARK_SUSTAINED_S=300`), one run per device.

| | iPhone 15 Pro Max | Pixel 4a (5G) |
| --- | --- | --- |
| Measured | 2026-10-11, FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3` | 2026-10-16, commit `2f092c2`, FFI commit `677a1cfdf1ab2b914f633d4abc790b7136d3a321` |
| Map frames per second, per 30 s interval | 109.7–111.6 | 57.9–58.4 |
| Per-second p10 / p50 / p90 | 104 / 110 / 119 | 57 / 58 / 59 |
| Lowest second | 100 | 46 |
| Map frames counted | 33,180 | 17,449 |
| Skipped renders | 0 | 0 |
| Thermal state | nominal at every interval start and at the end | nominal at every interval start and at the end |

The Pixel's build counted the map frames that the map queued for display, not the frames that Dart chose. On neither device did the frame rate decrease over the 5 minutes. The thermal state has four levels, so a small difference in heat wouldn't show.

### Copy-free and with copy

With `copyFree: false`, MapLibre renders each frame into a separate texture, and each frame is copied on the GPU into the buffer that Flutter displays. Measured 2026-10-11, FFI commit `6f5a662093873a5a690de34fe21f6329b58e77e3`, 3 runs each, the Mac on AC power:

| Device, mode | Per-second p10 / p50 / p90 | Lowest second | Average | `render_update` | Copy | Rendered frames not displayed |
| --- | --- | --- | --- | --- | --- | --- |
| iPhone 15 Pro Max, with copy | 87–88 / 99–102 / 109–111 | 84–86 | 98.4–99.1 | 8.07–8.20 ms | 1.53–1.54 ms | 2.9–4.3% |
| iPhone 15 Pro Max, copy-free | 103–104 / 109–111 / 116–120 | 98–101 | 109.4–110.7 | 7.53–7.97 ms | — | 7.2–8.6% |
| Mac, with copy | 91–98 / 100–102 / 105–108 | 88–96 | 99.8–101.9 | 6.81–6.90 ms | 0.49–0.54 ms | 5.9–7.9% |
| Mac, copy-free | 96–97 / 101–103 / 106–110 | 90–93 | 101.3–102.8 | 7.58–7.62 ms | — | 6.5–7.7% |

On the iPhone, copy-free increased the median second by about 10 frames per second and the lowest second by about 15. It also left more rendered frames undisplayed, because a copy-free frame takes about one refresh interval and the map renders ahead almost all the time. Counting those frames, the map thread spent 8.24–8.62 ms of `render_update` and copy per displayed frame copy-free, against 9.91–10.10 ms with the copy. On the Mac, copy-free made `render_update` about 0.7 ms longer, more than the copy it removed, and the frame rates of the two modes overlapped.

### Procedure

```sh
cd packages/test_harness
# macOS: open brings the window to the front. Keep the whole window visible during the
# run: a window behind others, or partly under another window, gets fewer frames or none.
flutter build macos --release --dart-define=BENCHMARK=true
open -W --env MLT_WINDOW_SIZE=1600x1000 --env MLT_WINDOW_SCREEN=builtin \
  --stdout result.txt build/macos/Build/Products/Release/test_harness.app

# iPhone (add --dart-define=BENCHMARK_SUSTAINED_S=300 for the 5-minute pan,
# and --dart-define=COPY=true for the copy)
flutter build ios --release --dart-define=BENCHMARK=true
xcrun devicectl device install app --device <device> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <device> --console \
  -e '{"MLT_KEEP_AWAKE":"1"}' com.greensopinion.mapigradeTestHarness

# Android
flutter build apk --release --dart-define=BENCHMARK=true
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -S -n com.greensopinion.mapigrade_test_harness/.MainActivity
adb logcat -s flutter | grep BENCHMARK_
```

The app prints one line starting with `BENCHMARK_RESULT` (or `BENCHMARK_SUSTAINED_RESULT`) and exits. Android's log truncates long lines, so the app also prints the main values in a line starting with `BENCHMARK_KEY`. On Android, keep the screen on and unlocked: when the screen turns off, the activity stops, the plugin pauses rendering, and the run doesn't finish.

## `MapigradeLayer` alignment with children

`packages/test_harness/lib/alignment_benchmark.dart` shows the map as the base layer of a `FlutterMap` (`flutter_map` 8.3.2) and moves the `flutter_map` camera through its `MapController` on every Flutter frame. With `--dart-define=ALIGNMENT_CHILDREN=1`, the overlays are children of the layer, which draws them at the `flutter_map` camera of the map frame it chose for the Flutter frame. For each Flutter frame, the benchmark finds the displayed map frame from the display times and Flutter's frame timings, and computes the drawn error over the viewport corners and center against the camera that the layer reports for its children. A drawn error over 1 px would show a fault in the choice of map frames. The benchmark also reports the lag against the live `flutter_map` camera.

A screen capture of the window on the Mac (2026-10-11) confirmed that the computed error matches the composited window: at rest within 0.05 px, and during a pan at 1,000 px/s within 0.06 px at p50.

The phases run for 20 s each, the fling phase for 30 s, after a warm-up that runs every phase's motion:

- `pan100`, `pan500` and `pan1000` pan back and forth over a 3,000 px path east of 51.5115, -0.14 at zoom 14, at 100, 500 and 1,000 px/s.
- `stop` pans at 1,000 px/s for 1 s, then rests for 1 s: 10 stops.
- `fling` pans at 1,000 px/s for 1 s, then moves as `flutter_map`'s fling after a release at 1,000 px/s, then rests until the 3 s cycle ends: 10 flings. On the Mac (1600 px viewport width) the fling starts at 1,000 px/s and stops after 1,000 px; on the iPhone 15 Pro Max (430 px) it starts at 430 px/s and stops after 430 px.
- `reverse` reverses the direction of a pan at 1,000 px/s every 1 s: 19 reversals.

### Results

Mode `predict1` (prediction with a lead of 1, the default), 3 runs per device. The drawn error was 0 px at max in every phase of every run on all three devices. Each value is the range over 3 runs.

Mac, measured 2026-11-01, FFI 0.202610.3, conditions as for the Mac frame rate above, viewport 1600x1000. No phase skipped a render, and at most 3 display slots were in use. The camera latency was 7.82–8.67 ms.

| Phase | `render_update` | Lag p50 / p95 | Displayed map frames per second |
| --- | --- | --- | --- |
| `pan100` | 7.14–7.21 ms | 0.83 / 1.67 px | 90.7–94.3 |
| `pan500` | 6.90–7.00 ms | 0 / 8.33 px | 98.0–99.5 |
| `pan1000` | 6.93–7.16 ms | 0–8.33 / 16.67 px | 94.9–99.0 |
| `stop` | 7.18–7.22 ms | 0 / 16.67 px | 74.0–74.8 |
| `fling` | 7.18–7.27 ms | 0.22–0.39 / 16.67 px | 86.4–89.2 |
| `reverse` | 7.23–7.26 ms | 8.33 / 16.67 px | 89.2–90.5 |

iPhones, measured 2026-10-22, FFI 0.202610.2, conditions as for the iPhone frame rates above. The camera latency was 11.5–14.0 ms on the iPhone 15 Pro Max and 15.6–23.3 ms on the iPhone 13. The thermal state on the iPhone 15 Pro Max was fair at the end of some runs.

| Phase | iPhone 15 Pro Max: `render_update` | lag p50 | iPhone 13: `render_update` | lag p50 |
| --- | --- | --- | --- | --- |
| `pan100` | 8.38–8.57 ms | 0.83 px | 15.00–15.27 ms | 1.66–1.67 px |
| `pan500` | 8.30–8.50 ms | 4.17 px | 13.77–13.95 ms | 0.02 px |
| `pan1000` | 8.36–8.62 ms | 8.34 px | 14.20–14.27 ms | 0.05–0.06 px |
| `stop` | 9.24–9.63 ms | 0.04–1.35 px | 15.23–15.41 ms | 0.01 px |
| `fling` | 8.65–8.89 ms | 1.98–2.07 px | 15.57–15.91 ms | 0.25–0.91 px |
| `reverse` | 8.86–9.31 ms | 8.34 px | 15.72–15.74 ms | 16.71–16.72 px |

In pans, the lag is a whole multiple of the camera movement in one Flutter frame (speed / refresh rate, 8.33 px at 1,000 px/s and 120 Hz), so a p50 is either about 0 or a multiple of that movement.

### Procedure

```sh
cd packages/test_harness
flutter build macos --release --dart-define=ALIGNMENT_BENCHMARK=true \
  --dart-define=ALIGNMENT_CHILDREN=1 --dart-define=ALIGNMENT_MODE=predict1 \
  --dart-define=ALIGNMENT_PHASES=pan100,pan500,pan1000,stop,fling,reverse
open -W --env MLT_WINDOW_SIZE=1600x1000 --env MLT_WINDOW_SCREEN=builtin \
  --stdout result.txt build/macos/Build/Products/Release/test_harness.app
```

On the iPhone, build with the same defines and install and launch the app as for `benchmark.dart`. The app prints one `ALIGNMENT_RESULT` line per phase and exits. `ALIGNMENT_MODE` also accepts `none`, `predict2` and `predict3`.

## `MapigradeLayer` with the mln-rs-based FFI

On 2026-11-27 we ran the frame rate benchmark (`benchmark.dart`) and the `MapigradeLayer` alignment benchmark (`alignment_benchmark.dart`, mode `predict1`, with children) on the Mac with two builds, alternating them, 3 runs of each benchmark per build:

- `main`: commit `bd1f066` (release 0.1.0), MapLibre Native FFI 0.202610.3.
- This branch: commit `6145097` with the uncommitted changes of the add-mapigrade-map change, the mln-rs-based FFI at commit `4371ff607e0bd22115d390de27d72a54987cc6c7`. The changes don't touch the layer's render path.

Conditions: macOS 26.7.3, Flutter 3.47.9, release builds, window 1600x1000 logical pixels placed on the built-in display (`MLT_WINDOW_SCREEN=builtin`), AC power, `caffeinate -dims` running, the iOS simulator and the Android emulator shut down. Each value is the range over 3 runs.

Frame rate during a continuous pan:

| | `main` | This branch |
| --- | --- | --- |
| Displayed map frames per second, average over 30 s | 100.7–112.0 | 119.3–119.5 |
| Per-second p10 / p50 / p90 | 87–106 / 101–113 / 115–116 | 118 / 120 / 120 |
| Lowest second | 81–100 | 117–118 |
| `render_update`, average | 6.81–7.03 ms | 5.38–5.44 ms |
| Camera latency, average | 7.28–7.59 ms | 5.45–5.53 ms |
| Skipped renders | 0 | 0 |

Alignment with children: the drawn error was 0 px at max in every phase of every run of both builds, and every Flutter frame was matched to a displayed map frame. No phase skipped a render. At most 3 display slots were in use with `main` and 2 with this branch.

| Phase | `render_update`, `main` / branch | Lag p50 / p95, `main` | Lag p50 / p95, branch | Displayed map frames per second, `main` / branch |
| --- | --- | --- | --- | --- |
| `pan100` | 7.24–7.37 / 5.56–5.57 ms | 0 / 0.83 px | 0 / 0 px | 106.8–107.5 / 119.2–119.3 |
| `pan500` | 6.96–7.13 / 5.48–5.51 ms | 0 / 4.17–8.33 px | 0 / 0 px | 110.2–110.3 / 118.3–119.0 |
| `pan1000` | 7.05–7.16 / 5.53–5.56 ms | 0 / 8.33–16.56 px | 0 / 0 px | 108.5–109.6 / 117.7–118.0 |
| `stop` | 7.44–7.51 / 5.67–5.69 ms | 0 / 16.60–16.67 px | 0 / 0 px | 85.8–87.4 / 96.0–96.7 |
| `fling` | 7.32–7.38 / 5.59–5.62 ms | 0.05–0.11 / 16.67 px | 0–0.01 / 0.86 px | 101.1–102.6 / 112.4–114.3 |
| `reverse` | 7.43–7.54 / 5.60–5.61 ms | 8.33 / 16.67 px | 0 / 0.04–0.08 px | 102.7–103.7 / 118.0–118.2 |

The camera latency of the alignment phases was 7.65–9.82 ms with `main` and 5.56–5.82 ms with this branch. With this branch, the children lagged the `flutter_map` camera by less than 1 px at p95 in every phase. We didn't find out why the lag decreased.

The procedures are those of the frame rate and alignment sections above. To run both builds, build each in its own worktree and copy each app bundle before the next build.

## Memory on Android

`packages/test_harness/integration_test/memory_measurement.dart` on the Pixel, measured 2026-10-17 with the changes of commit `96a4ad7`, 3 runs. The test uses a profile build, because `flutter drive` doesn't run release builds. It reports PSS from `/proc/self/smaps_rollup`:

| PSS | Pixel 4a (5G) |
| --- | --- |
| Before the map was created | 86–88 MiB |
| Before the memory reduction | 219–222 MiB |
| 7 s after the memory reduction | 210–221 MiB |
| At the start of the resizes / after 300 resizes | 161–164 / 145–147 MiB |
| 2 s after dispose | 123–129 MiB |

This PSS doesn't include the graphics buffers. `dumpsys meminfo` 10 s into the measured pass of `benchmark.dart` (release build, one run) reported 203 MB of graphics memory, of which 98 MB EGL mtrack.

```sh
cd packages/test_harness
flutter drive -d <device> --driver=test_driver/integration_test.dart \
  --target=integration_test/memory_measurement.dart
```

## No CPU readback on the frame path

On 2026-11-27 we searched the sources of `packages/mapigrade` and `packages/flutter_mapigrade` for the CPU readback calls `mln_texture_read_premultiplied_rgba8`, `getBytes`, `CVPixelBufferLockBaseAddress`, `CVPixelBufferGetBaseAddress`, `IOSurfaceLock`, `replaceRegion` and `glReadPixels`, and found none. We also traced builds that copied each frame (`copyFree: false`) with Instruments' Metal System Trace:

- Mac (2026-10-09, about 100 s including 60 s of continuous pan): 13,872 render encoders and 6,577 blit encoders, no compute encoders. In 33,477 time-profile samples, `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes` and `mln_texture_read_premultiplied_rgba8` appear 0 times.
- iPhone 15 Pro Max (2026-10-10, 20 s of continuous pan, `--dart-define=CONTINUOUS_PAN=true`): 4,966 render encoders and 2,050 blit encoders, no compute encoders. In 12,808 time-profile samples, `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes`, `replaceRegion` and `mln_texture_read_premultiplied_rgba8` appear 0 times. Two samples are in `IOSurfaceClientGetBaseAddressOfPlane`, called by the Metal driver's `getGPUVirtualAddress` while it encodes the plugin's blit, which computes a GPU address, not a CPU read.

On Android, MapLibre renders into the buffers that Flutter displays. We didn't trace it.

```sh
xcrun xctrace record --device <id> --template 'Metal System Trace' --attach <pid>
```

`xctrace` launches an app by its bundle identifier, which the Debug and Release builds share. Delete `build/macos/Build/Products/Debug/test_harness.app` before tracing the Release build on the Mac, or `xctrace` starts the Debug build.

## Color check

A map whose style has a `#3366CC` background and a `#E6B31A` fill is shown next to Flutter swatches of the same colors.

On the Mac, `packages/test_harness/lib/color_check.dart` (`flutter run -d macos -t lib/color_check.dart`) shows the screen, and we measured a window screenshot (Display P3, 2026-10-09):

| Color | Map | Flutter swatch | Largest channel difference |
| --- | --- | --- | --- |
| fill `#E6B31A` | 222, 181, 67 | 222, 181, 67 | 0 |
| background `#3366CC` | 64, 101, 197 | 64, 100, 197 | 1 |

Both are within the 2/255 tolerance, so the IOSurface buffers need no explicit color space.

On the iPhone (2026-10-10) and the Pixel (2026-10-16), `packages/test_harness/integration_test/color_measurement.dart` renders the same screen to an image with `RepaintBoundary.toImage` and compares the pixels. The map and the swatches had identical values: fill 230, 179, 26, background 51, 102, 204.

```sh
cd packages/test_harness
flutter drive -d <device> --driver=test_driver/integration_test.dart \
  --target=integration_test/color_measurement.dart
```
