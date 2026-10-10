# Benchmarks

## Frame rate during continuous pan (task 7.4)

Result: the median displayed map frame rate was **119 frames per second**. That is above the 30 fps minimum and above the 60 fps target, and it matches the display's 120 Hz refresh rate.

### Setup

| | |
| --- | --- |
| Date | 2026-10-09 |
| Machine | MacBook Pro (Mac14,5), Apple M2 Max, 12 CPU cores (8 performance, 4 efficiency), built-in Liquid Retina XDR display, pixel ratio 2, 120 Hz (the measured Flutter vsync interval is 8.333 ms) |
| macOS | 26.6.2 (25G83) |
| Xcode | 26.6 (17F113) |
| Flutter | 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4, Impeller (Metal) |
| MapLibre Native FFI | commit `dd97d20f8fab6990cd87c13f091ce00e662707bd`, preset `macos-arm64-metal` |
| Build | release (`flutter build macos --release --dart-define=BENCHMARK=true`) |
| Window | 1600x1000 logical pixels (`MLT_WINDOW_SIZE=1600x1000`), map texture 3200x2000 physical pixels |
| Style | OpenFreeMap Liberty (`https://tiles.openfreemap.org/styles/liberty`) |
| Scenario | Camera set on every Flutter frame for 30 s, panning east from 37.7749, -122.4194 at zoom 14 at 0.2 viewport widths per second. A first 30 s pass over the same path loaded the area into the cache; the camera then went back to the start, and the map reached idle before the measured pass. |
| Overlay | the example's Flutter control panel above the map |

Procedure (`example/lib/benchmark.dart`):

```sh
cd example
flutter build macos --release --dart-define=BENCHMARK=true
MLT_WINDOW_SIZE=1600x1000 \
  build/macos/Build/Products/Release/flutter_map_maplibre_texture_example.app/Contents/MacOS/flutter_map_maplibre_texture_example
```

The app prints one line starting with `BENCHMARK_RESULT` and exits.

### Results (measured 30 s pass)

Displayed map frames: Dart counts each distinct frame id that Flutter took from the texture (the "frame displayed" event) and the time between them.

| Metric | Median | p95 | p99 | Max |
| --- | --- | --- | --- | --- |
| Displayed map frame interval | 8.33 ms | 8.87 ms | 12.72 ms | 19.83 ms |
| Flutter frame interval (vsync to vsync) | 8.33 ms | 8.34 ms | 8.34 ms | 9.52 ms |
| Flutter frame total span (build start to raster end) | 0.74 ms | 2.19 ms | 3.03 ms | 6.24 ms |
| Flutter build | 0.06 ms | 0.25 ms | 2.01 ms | 4.01 ms |
| Flutter raster | 0.50 ms | 1.63 ms | 1.85 ms | 4.04 ms |

| Metric | Value |
| --- | --- |
| Displayed map frames | 3,569 in 30 s (119.0 per second) |
| Flutter frames | 3,508 in 30 s |
| Map frames rendered | 3,569 (every rendered frame was displayed) |
| `render_update` duration, average | 2.74 ms (CPU encoding plus the wait for GPU completion, see below) |
| GPU copy into the display buffer, average | 0.40 ms (including `waitUntilCompleted`) |
| Renders skipped because no buffer was free | 0 |
| Renders deferred until Flutter took the latest frame | 13,836 |

`render_update` returns only after MapLibre's command buffer completes (design, Context), so its duration is MapLibre's CPU encoding plus GPU execution on the map thread. The stats record only the maximum over the whole run, 326 ms, which occurred during the first style and tile load, not in the measured pass.

### GPU time

A second run of the same benchmark under Instruments' Metal System Trace (`xcrun xctrace record --template 'Metal System Trace'`) shows GPU work for the whole process: MapLibre's rendering, the per-frame copy and Flutter's compositing share one process and one GPU, and the trace doesn't attribute work to them separately. Over the traced run (warm-up and measured pass), the process's top-level GPU intervals summed to 4,117 ms on the vertex channel, 2,156 ms on the fragment channel and 680 ms on the compute channel (blits). Tracing reduced the displayed map frame rate to 97 frames per second (p95 interval 17.1 ms), so the untraced numbers above are the result.

Per frame, the best available bound for MapLibre's GPU time is the `render_update` average of 2.74 ms, which includes CPU encoding.

## No CPU readback on the frame path (task 7.3)

Source: a search of the plugin and the example (`src/`, `macos/`, `lib/`, `example/lib/`) for `mln_texture_read_premultiplied_rgba8`, `getBytes`, `CVPixelBufferLockBaseAddress`, `CVPixelBufferGetBaseAddress`, `IOSurfaceLock` and `replaceRegion` found no matches. The frame path is `mln_render_session_render_update` into a private `MTLTexture`, an `MTLBlitCommandEncoder` copy into an IOSurface-backed `CVPixelBuffer`, and `-[FlutterTexture copyPixelBuffer]` returning that pixel buffer.

Trace: in the Metal System Trace of the benchmark run (about 100 s, including the 60 s of continuous pan), the process's encoders were 13,872 render encoders and 6,577 blit encoders, with no compute encoders. In the trace's 33,477 time-profile samples, the frame-path functions appear (`MapTexture::MaybeRender`, `CopyToBuffer`, `mln_render_session_render_update`, `copyPixelBuffer`), while `CVPixelBufferLockBaseAddress`, `IOSurfaceLock`, `getBytes` and `mln_texture_read_premultiplied_rgba8` appear 0 times.
