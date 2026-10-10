# Benchmarks

## Frame rate during continuous pan

Measured 2026-10-10 over central London (see Path), in release builds:

| Displayed map frames per second | macOS (MacBook Pro, M2 Max) | iPhone 15 Pro Max |
| --- | --- | --- |
| per-second p10 / p50 / p90 | 116 / 117 / 119 | 37 / 41 / 57 |
| lowest second | 112 | 35 |
| average over 30 s | 117.1 | 46.4 |
| 5-minute run, per-second p10 / p50 / p90 (lowest) | not run | 33 / 39 / 52 (30) |

Against the go/no-go values: both meet the 30 fps minimum. macOS reaches the display's 120 Hz refresh rate; the iPhone stays below the 60 fps target, and its lowest second in the 5-minute run was 30 fps. On the iPhone a frame takes about 17 ms (`render_update` 15.2 ms plus the copy 1.8 ms), just over two 120 Hz vsync intervals, so most frames are displayed every third vsync (median interval 24.9 ms).

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
# macOS: open brings the window to the front; a window behind others gets no frames.
flutter build macos --release --dart-define=BENCHMARK=true
open -W --env MLT_WINDOW_SIZE=1600x1000 --stdout result.txt \
  build/macos/Build/Products/Release/flutter_map_maplibre_texture_example.app

# iPhone: the result line is read from the console.
flutter build ios --release --dart-define=BENCHMARK=true
xcrun devicectl device install app --device <device> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <device> --console \
  -e '{"MLT_KEEP_AWAKE":"1"}' org.maplibre.flutterMapMaplibreTextureExample

# 5-minute run: add --dart-define=BENCHMARK_SUSTAINED_S=300 to the iOS build.
```

The app prints one line starting with `BENCHMARK_RESULT` (or `BENCHMARK_SUSTAINED_RESULT`) and exits.

### Results (measured 30 s pass)

Displayed map frames: Dart counts each distinct frame id that Flutter took from the texture (the "frame displayed" event) and the time between them.

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

### 5-minute run (iPhone)

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
