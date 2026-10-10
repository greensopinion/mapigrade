# Follow-up: Flutter's Darwin texture cache keeps replaced pixel buffers alive

**Status:** worked around in the plugin; not reported to Flutter yet
**Found:** 2026-10-10, during the iOS vertical slice (`openspec/changes/ios-texture-vertical-slice/`)

## Summary

On macOS and iOS, Flutter wraps each `CVPixelBuffer` that a `FlutterTexture` returns in a Metal texture created through a `CVMetalTextureCache`, and never flushes that cache while frames are drawn. A `CVMetalTextureCache` keeps the IOSurface of every pixel buffer it has wrapped until the cache has been idle for longer than its maximum texture age (1 s by default) and then creates another texture or is flushed. While textures keep being created, nothing is freed, even with a flush after every frame.

For a plugin that allocates new pixel buffers when the texture size changes, every resize therefore adds pixel buffers that Flutter keeps alive until the resizing stops and Flutter creates one more texture after an idle second. On an idle map, the next texture can be minutes away.

## Where in Flutter

Checked in the Flutter 3.47.5 engine source (`engine/src/flutter` in the Flutter repository):

- iOS: `shell/platform/darwin/graphics/FlutterDarwinExternalTextureMetal.mm`. `wrapBGRAExternalPixelBuffer:` calls `CVMetalTextureCacheCreateTextureFromImage` with the engine's texture cache (created in `FlutterDarwinContextMetalImpeller.mm` with default attributes). `CVMetalTextureCacheFlush` is called only in `dealloc` and in `onGrContextDestroyed`.
- macOS: `shell/platform/darwin/macos/framework/Source/FlutterExternalTexture.mm`. `populateTextureFromRGBAPixelBuffer:` uses `_darwinMetalContext.textureCache` (created in `FlutterDarwinContextMetalSkia.mm`), which is never flushed.

## Evidence

### CVMetalTextureCache behavior

A command-line probe on macOS 26.6 (Apple M2 Max) creates a 200x200 BGRA IOSurface-backed pixel buffer every 20 ms, wraps it with `CVMetalTextureCacheCreateTextureFromImage`, releases the texture and the buffer, and counts how many of the buffers' IOSurfaces are still alive (`IOSurfaceLookup` by id):

| Cache | After 3 s (150 buffers) | After 1.2 s idle | After one more texture |
| --- | --- | --- | --- |
| default attributes, no flush | 130 alive | 130 | 1 |
| default attributes, flush after each texture | 123 alive | 123 | 2 |
| maximum texture age 0, no flush | 150 alive | 150 | 151 |
| maximum texture age 0, flush after each texture | 0 alive | 0 | 0 to 8 (IOSurface ids are reused, so this count includes unrelated surfaces) |

Only a maximum age of 0 combined with a flush after each texture frees the IOSurfaces while textures keep being created.

### Effect in the plugin

`example/integration_test/memory_measurement.dart` resizes a map 300 times (about 10 s) and counts the plugin's released display buffers that are still alive. With the plugin-side fixes below and the workaround:

| | macOS | iOS simulator (iPhone 16 Pro, iOS 18.1) | iPhone 15 Pro Max (iOS 26.7.1) |
| --- | --- | --- | --- |
| after 300 resizes | 606 of 900 alive (1,117 MiB) | 608 of 900 alive (1,832 MiB) | 673 of 900 alive (2,305 MiB) |
| 0.5 s after the last resize | 606 alive | 608 alive | 673 alive |
| 2.5 s after the last resize (after the workaround) | 51 alive (93 MiB) | 74 alive (220 MiB) | 44 alive (150 MiB) |

During the resizing, the buffers that stay alive are the ones Flutter's cache holds. Neither macOS's nor the simulator's memory footprint counts IOSurface memory, so this doesn't show in the footprint there. On the iPhone it counts in part. The iPhone's memory footprint (`phys_footprint`, the value Xcode's memory gauge shows) in the same measurement:

| | before the fixes | after the fixes and the workaround |
| --- | --- | --- |
| before resizing | 292 MiB | 289 MiB |
| after 300 resizes | 696 MiB | 457 MiB |
| 2.5 s after the last resize | 698 MiB (freed only at dispose) | 246 MiB |
| after dispose | 215 MiB | 216 MiB |

In the integration suite's resize test (600 resizes up to 90% of the screen), the peak footprint was 1,003 MiB before the fixes and 572 MiB after. Before the fixes, a run that started with the phone locked was terminated for using too much memory. The remaining growth during a burst comes from Flutter's cache.

## Workaround in the plugin

The core tells Flutter once more that a frame is available 1.1 s after the last resize (`MapTexture::MaybeNotifyAfterResize()` in `src/core/map_texture.cpp`). Flutter then creates a texture after an idle period longer than the cache's maximum age, and the cache frees the aged entries. This bounds the retained buffers to those of the current burst of resizes, but it doesn't help during a burst: a long continuous resize (for example dragging a desktop window edge) still accumulates buffers until it stops.

The plugin had two leaks of its own, which are fixed, not worked around:

- The map thread had no autorelease pool, so each frame's autoreleased command buffer, and with it the display buffer it copied into, stayed alive until the thread exited at dispose. The map thread now runs each loop iteration in an autorelease pool (`RunInPlatformScope`).
- The plugin wrapped its own buffers through its own `CVMetalTextureCache`, which kept them alive in the same way. It now creates the Metal textures directly from the IOSurfaces (`newTextureWithDescriptor:iosurface:plane:`).

## Proposed fix in Flutter

Either of these, in both Darwin embedders:

1. Create the Metal texture directly from the pixel buffer's IOSurface (`-[MTLDevice newTextureWithDescriptor:iosurface:plane:]`) instead of through a `CVMetalTextureCache`. The cache saves the cost of creating a texture object for a pixel buffer that is displayed again, which is small compared with the memory it can hold.
2. Create the cache with `kCVMetalTextureCacheMaximumTextureAgeKey` set to 0 and call `CVMetalTextureCacheFlush` after each frame that wraps a pixel buffer.

## Next steps

- Search the Flutter issue tracker for an existing report about external texture memory on iOS or macOS.
- If none exists, file one with the probe above as a reproduction and the two proposed fixes; optionally submit an engine change for option 1.
- When a fixed Flutter version is available, remove `MaybeNotifyAfterResize()` and its timer from the core.
