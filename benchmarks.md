# Benchmarks

## Frame rate during continuous pan

Measured 2026-10-10 over central London (see Path), in release builds:

| Displayed map frames per second | macOS (MacBook Pro, M2 Max) | iPhone 15 Pro Max |
| --- | --- | --- |
| per-second p10 / p50 / p90 | 116 / 117 / 119 | 87 / 99–100 / 105 |
| lowest second | 112 | 85 |
| average over 30 s | 117.1 | 97 |

Against the go/no-go values: both meet the 30 fps minimum and the 60 fps target. The iPhone numbers are with rendering ahead (design D19), the default since 2026-10-10: while a frame takes longer than a refresh interval, the next frame renders without waiting until Flutter has taken the previous one. On the Mac a frame takes 5.7 ms, less than the 8.33 ms refresh interval, so the map stays paced there.

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

The copy-free variants need the FFI patch in `scripts/patches/` (design D20). The first copy-free rendering-ahead runs predate the hysteresis in D19, and the map switched between rendering ahead and pacing in them. With the hysteresis, copy-free raised the lowest second from 84–86 to 102–103 fps; 8% of rendered frames weren't displayed, against 2.4% with the copy.

The per-second values count the displayed map frames in each whole second of the measured pass; p10 means that 10% of seconds had that many frames or fewer. An average over the pass hides the slow seconds, which is why the benchmark reports them.

### Path

The camera is set on every Flutter frame for 30 s, panning east at zoom 14 from 51.5115, -0.14 (Charing Cross) through Covent Garden, the City, Whitechapel and Limehouse, at 0.2 tile widths per second (0.0044 degrees of longitude per second, about 102 logical pixels per second). A first 30 s pass over the same path loads the area into the cache; the camera then goes back to the start, and the map reaches idle before the measured pass. The path has dense streets, buildings and labels throughout.

Before 2026-10-10 the benchmark panned east from San Francisco (37.7749, -122.4194), a path that runs from the city into the bay, where water renders cheaply. That path gave 119.0 fps on macOS (Stage 1) and 88.8 fps average on the iPhone, and overstated the frame rate; the earlier description of its speed as 0.2 viewport widths per second was wrong (it was 0.2 tile widths per second, as now).

### Setup

| | macOS | iPhone |
| --- | --- | --- |
| Device | MacBook Pro (Mac14,5), Apple M2 Max, 12 CPU cores (8 performance, 4 efficiency), built-in Liquid Retina XDR display, 120 Hz | iPhone 15 Pro Max (iPhone16,2), ProMotion display, 120 Hz (`CADisableMinimumFrameDurationOnPhone` is set) |
| OS | macOS 26.6.2 (25G83) | iOS 26.7.1 (23H30) |
| Map size | window 1600x1000 logical pixels, pixel ratio 2, 3200x2000 physical | full screen, portrait, 430x932 logical pixels, pixel ratio 3, 1290x2796 physical |
| Measured Flutter vsync interval | 8.333 ms | 8.335 ms |

Both: Xcode 26.6 (17F113); Flutter 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4, Impeller (Metal); MapLibre Native FFI commit `dd97d20f8fab6990cd87c13f091ce00e662707bd` (presets `macos-arm64-metal` and `ios-arm64-metal`); style OpenFreeMap Liberty (`https://tiles.openfreemap.org/styles/liberty`); the example's Flutter control panel above the map. Thermal state on the iPhone was nominal at the start and end of every run.

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

These tables are from the first London measurement, before rendering ahead (iPhone in the slower state).

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

### 5-minute run (iPhone, before rendering ahead)

The measured pass pans back and forth over the warm-up path for 300 s. Average displayed map frame rate per 30 s interval: 40.5, 39.5, 39.9, 39.5, 39.4, 39.5, 39.8, 39.8, 40.7, 39.8. Per second: p10 33, p50 39, p90 52, lowest 30. Thermal state: nominal at the start of every interval and at the end. Skipped renders: 0. The frame rate doesn't decrease over the 5 minutes.

### Slower GPU (task 6.4)

Not run: the iPhone XR (iPhone11,8, A12, 60 Hz) intended as a slower-GPU data point was unavailable (`devicectl` listed it as unavailable on 2026-10-10).

### GPU time (macOS, Stage 1)

On 2026-10-09, with the earlier San Francisco path (see Path), a second run of the benchmark under Instruments' Metal System Trace (`xcrun xctrace record --template 'Metal System Trace'`) shows GPU work for the whole process: MapLibre's rendering, the per-frame copy and Flutter's compositing share one process and one GPU, and the trace doesn't attribute work to them separately. Over the traced run (warm-up and measured pass), the process's top-level GPU intervals summed to 4,117 ms on the vertex channel, 2,156 ms on the fragment channel and 680 ms on the compute channel (blits). Tracing reduced the displayed map frame rate to 97 frames per second (p95 interval 17.1 ms), so the untraced run's 119.0 fps was the result for that path.

Per frame, the best available bound for MapLibre's GPU time on that path was the `render_update` average of 2.74 ms, which includes CPU encoding; over central London it is 4.52 ms on macOS and 15.22 ms on the iPhone (Results).

## No CPU readback on the frame path

### macOS (Stage 1, task 7.3)

Source: a search of the plugin and the example (`src/`, `macos/` (now `darwin/`), `lib/`, `example/lib/`) for `mln_texture_read_premultiplied_rgba8`, `getBytes`, `CVPixelBufferLockBaseAddress`, `CVPixelBufferGetBaseAddress`, `IOSurfaceLock` and `replaceRegion` found no matches. The frame path is `mln_render_session_render_update` into a private `MTLTexture`, an `MTLBlitCommandEncoder` copy into an IOSurface-backed `CVPixelBuffer`, and `-[FlutterTexture copyPixelBuffer]` returning that pixel buffer.

Trace: in the Metal System Trace of the benchmark run (about 100 s, including the 60 s of continuous pan), the process's encoders were 13,872 render encoders and 6,577 blit encoders, with no compute encoders. In the trace's 33,477 time-profile samples, the frame-path functions appear (`MapTexture::MaybeRender`, `CopyToBuffer`, `mln_render_session_render_update`, `copyPixelBuffer`), while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes` and `mln_texture_read_premultiplied_rgba8` appear 0 times.

### iPhone (iOS slice, task 5.7)

A 20 s Metal System Trace on the iPhone 15 Pro Max (`xcrun xctrace record --device <id> --template 'Metal System Trace' --attach <pid>`, 2026-10-10), attached to a release build of the example panning continuously (`--dart-define=CONTINUOUS_PAN=true`): the app's encoders were 4,966 render encoders and 2,050 blit encoders, with no compute encoders; 4,100 were encoded on the map thread and 2,916 on Flutter's raster thread. Of the 12,808 time-profile samples, `mln_render_session_render_update` appears in 6,032, the plugin's blit (`-[IOGPUMetalBlitCommandEncoder copyFromTexture:toTexture:]` from `MetalRenderTarget::CopyToBuffer`) in 121 and `copyPixelBuffer` in 77, while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes`, `replaceRegion` and `mln_texture_read_premultiplied_rgba8` appear 0 times. Two samples are in `IOSurfaceClientGetBaseAddressOfPlane`; both are called by the Metal driver's `getGPUVirtualAddress` while it encodes the plugin's blit, which computes a GPU address, not a CPU read.
