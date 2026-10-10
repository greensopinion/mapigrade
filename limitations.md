# Limitations and findings of the macOS vertical slice

Measured results are in `benchmarks.md`. The design and its amendments are in `openspec/changes/macos-texture-vertical-slice/design.md`.

## App bundle size

Release builds, arm64, measured with `du -sk` on 2026-10-09:

| Bundle | Size |
| --- | --- |
| `flutter create` template app (baseline) | 37,716 KB |
| example app with this plugin | 51,816 KB |
| increase | 14,100 KB (13.8 MiB) |
| of which `MapLibreNativeC.framework` | 12,884 KB |

The rest of the increase is the plugin's native code in the app executable and the example's own Dart code. The FFI library is built for arm64 only; a universal build would roughly double the framework.

## Licenses and third-party notices

We have not completed a license review. Before any distribution, the following must be reviewed and their notices included with the app. The FFI build installs them in `third_party/maplibre-native-ffi/share/maplibre-native-c/`:

| File | Component | License |
| --- | --- | --- |
| `LICENSE` | MapLibre Native FFI | BSD 2-Clause |
| `licenses/maplibre-native.md` | MapLibre Native and the third-party code it includes (Boost, RapidJSON, earcut.hpp, protozero, geojson-vt-cpp and others; 1,347 lines) | BSD 2-Clause plus the listed notices |
| `licenses/icu.txt` | ICU | Unicode license |
| `licenses/fastpfor.txt` | FastPFOR | Apache 2.0 |
| `licenses/nunicode.txt` | nunicode | MIT |
| `licenses/pmtiles.txt` | PMTiles | BSD 3-Clause |

The macOS build of the FFI doesn't link its Rust platform component, so no Rust crate notices apply to this build.

Map data: the example uses OpenFreeMap tiles (OpenStreetMap data, ODbL) and the MapLibre demo tiles. The example does not show the attribution that OpenStreetMap data requires. A product must show it.

## Decisions and findings

### D3b instead of D3: one render texture and a GPU copy per frame

D3 rendered directly into the three IOSurface buffers and switched the session's target with `mln_metal_borrowed_texture_set_target()` before each frame. `set_target` was cheap (7.0 µs average, 893 µs maximum over 6,948 calls) and never caused `MLN_RENDER_RESULT_SIZE_PENDING`, but after each target change the renderer reported `needs_repaint` and the map published another render update, so with a static camera the map rendered about 880 frames per second and never stopped. With one render texture the map stops rendering after the style and tiles load. We chose D3b: MapLibre renders into one private `MTLTexture`, and each frame is copied with an `MTLBlitCommandEncoder` into a free IOSurface buffer. The copy took 0.40 ms per frame at 3200x2000 including the wait for completion. The full measurement is in design.md (D3).

The constant re-rendering after `set_target` may be worth reporting to MapLibre Native FFI. If it is fixed upstream, D3 would save the copy.

### Rendering is paced by the display

The map thread renders the next frame only after Flutter has taken the latest one (amendment to D4). Without this, during camera changes the map rendered about 1,200 frames per second, of which Flutter displayed about 120. The map is therefore at most one frame ahead of the display.

### `textureFrameAvailable:` needs the platform thread

The engine source asserts the platform thread in `Shell::OnPlatformViewMarkTextureFrameAvailable`, so the bridge dispatches `textureFrameAvailable:` to the main queue. We did not run this with a debug engine that has the assertions enabled. Details are in design.md (D4).

### Colors

Map colors match Flutter's within 1/255 per channel without setting a color space on the IOSurface (README, Color check).

## Known limitations

- arm64 only: the FFI preset is `macos-arm64-metal`, and the example sets `ARCHS = arm64`.
- Swift Package Manager only: the plugin has no podspec.
- One Flutter engine per process: the plugin keeps the texture registry of the engine that registered it last.
- The map's sprite and glyph density is fixed when the map is created (`mln_map_options.scale_factor`). After a device pixel ratio change the map renders at the new ratio, but MapLibre logs a warning and keeps sprites at the original density. A map recreated at the new ratio would fix this.
- We did not test moving the window between displays with different pixel ratios, because only one display was available. Resizing was tested by resizing the map widget on every frame for 10 s in an integration test, and by dragging the example window's edge for about 10 s by hand; after the drag the map filled the window at the correct scale.
- The displayed map frame can lag the Flutter overlays by one or more frames during camera changes. Each displayed frame reports its camera (`MapTextureController.frames`), which the `flutter_map` slice needs to align overlays.
- `render_update` waits on the map thread until the GPU completes. At 119 frames per second this was not a limit on the reference Mac. On slower GPUs the session may need its own thread (design D2, alternative).
- The plugin exposes only style, camera (center, zoom, bearing), resize and dispose. There are no gestures, pitch or animations.

## What the iOS slice can reuse

- `src/core/` as is: the map thread, command queue, camera coalescing, buffer state, pacing, events and the C ABI. It has no Apple dependencies.
- The Dart API (`lib/src/texture/`) as is.
- Most of `MapTextureMetal.mm`: `CVPixelBuffer`, IOSurface, `CVMetalTextureCache`, `MTLBlitCommandEncoder` and `FlutterTexture` work the same on iOS. The changes are the `Flutter` instead of `FlutterMacOS` import and the registrar.
- The build script, after adding the `ios-arm64-metal` and `ios-simulator-arm64-metal` presets, with an xcframework that has a slice per platform.
- The measurement procedure (`example/lib/benchmark.dart`) and the integration tests.
