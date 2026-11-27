## Context

The package pins MapLibre Native FFI 0.202610.3 (commit `6c065d9`). Since then the FFI's `main` branch replaced its C++ implementation with mln-rs, the Rust port of MapLibre Native, and reshaped the C API around it (maplibre/maplibre-native-ffi#1801, commit `d62ed4c`, 2026-11-14). The C headers now come from mln-rs (#1806). The gesture recognizer and the frame projection arrived with the mln-rs update in #1818 (commit `79dee41`, 2026-11-22). No FFI release contains any of this: the last release, 0.202611.0, is from 2026-11-07.

Between `6c065d9` and `main`, 68 commits are marked breaking. Of the FFI functions, types and constants that our native code uses, 18 no longer exist, and others changed their meaning. The changes that affect our code:

- **Render targets.** A session renders through a GPU device (`gpu_device.h`) into one target descriptor (`render_target.h`). Owned textures are gone. Our host devices are wrapped with `mln_gpu_device_wrap_metal` and `mln_gpu_device_wrap_open_gl`. The Metal ring is `MLN_RENDER_TARGET_KIND_METAL_BORROWED_TEXTURES`; the EGL window surface is `MLN_RENDER_TARGET_KIND_OPEN_GL_SURFACE` with a wrapped EGL context.
- **Frames.** `mln_render_session_request_frame` is now `mln_render_session_demand_frame`, and every demand presents. `mln_render_session_acquire_frame` acquires the newest rendered frame and drops older ones. `mln_acquired_frame_release` takes a consumer sync (`MLN_GPU_SYNC_CPU_COMPLETE` when the consumer's GPU work has finished). A session's failure is a value in its snapshot.
- **GeoJSON.** `mln_geo_json_source_data` (data prepared by the caller) is gone. `mln_map_set_geo_json_source_data` takes GeoJSON text and prepares it in the background, newest first.
- **Events and status codes.** Events carry typed payloads. The log callback returns void. A duplicate source or layer is `MLN_STATUS_ALREADY_EXISTS`. A style JSON that fails to parse completes with `MLN_STATUS_INVALID_ARGUMENT`. Style loads complete after the parse.
- **New:** `mln_render_frame_result.frame_projection` and `mln_gesture_recognizer_*`.

The FFI's presets are renamed (`macos-arm64`, `ios-arm64`, `ios-simulator-arm64`, `android-arm64`). Building the FFI now runs Cargo on mln-rs, with a toolchain that the FFI's mise configuration pins (Rust 1.99.1). `scripts/build_maplibre_ffi.sh` builds the old presets and the old Android TLS helper, so it builds nothing that the new FFI has. The platform minimums of the new presets match ours: macOS 14.3, iOS 15.0, Android API level 24, below our minimum of 29.

## Goals / Non-Goals

**Goals:**
- The package builds on the pinned commit with a local FFI build on macOS, iOS and Android, and keeps the behavior that the specs require.
- The map thread keeps the frame projection of each published frame, for `add-mapigrade-map`.

**Non-Goals:**
- Using the gesture recognizer, giving the frame projection to Dart, or anything that `add-mapigrade-map` and `split-mapigrade-package` do.
- Building against an FFI release; that happens when one exists.
- Moving Android to Vulkan or to the FFI's exported ring of hardware buffers.
- The FFI's frame pacing (`mln_render_session_set_frame_pacing`). It demands frames at display refreshes, whether or not Flutter displays them; the map thread keeps demanding a frame only when Dart has chosen the previous one and a slot is free.

## Decisions

### D218. Pin FFI `main` at `4371ff6`

The pin is `4371ff607e0bd22115d390de27d72a54987cc6c7`, the head of `main` on 2026-11-27. It contains `d62ed4c` and `79dee41`. On 2026-11-27, FFI `main` is `4371ff6` and builds mln-rs `71769bb` (2026-11-22). mln-rs 0.0.16 (2026-11-26) adds terrain, with breaking changes to the C API. If the FFI merges the update to mln-rs 0.0.18 before this change is done, we move the pin to that merge; the C API changes it brings are ported in this change.

Alternatives: waiting for an FFI release blocks `add-mapigrade-map` for an unknown time; release 0.202611.0 has neither the recognizer nor the frame projection.

### D219. Without a release, builds need a local FFI build

`maplibre_ffi.lock` states the commit and no release: `MAPLIBRE_FFI_VERSION`, the xcframework URL and checksum, and the Android runtime AAR version are empty. Builds that would take the FFI from a release (Swift Package Manager's binary target, Gradle's release mode) fail with a message that names `scripts/build_maplibre_ffi.sh`. Builds of the example, the test harness and the demo use the local FFI build, as the `package-distribution` requirement on local builds already allows.

On the branch `mapigrade-map`, `ffi_pins_test.dart` and `scripts/consumer_build.sh` fail, because they check the release pins. They must pass again before either package is released. We don't change them to accept a lock without a release, because that would let a lock without a release reach a published package.

Alternative: keep the 0.202610.3 release fields in the lock. Release-mode builds would then link the old library against code for the new C API, and fail with link errors instead of a clear message.

### D220. Rewrite the local FFI build for mln-rs

`scripts/build_maplibre_ffi.sh` uses the FFI's own toolchain: `mise bootstrap` for macOS and iOS, and `mise -E android` for Android, in the FFI checkout at the pinned commit. It builds the presets `macos-arm64`, `ios-arm64`, `ios-simulator-arm64` and `android-arm64`, and combines the three Apple frameworks into `MaplibreNativeC.xcframework` as before. The Android TLS helper step and the patches in `scripts/patches/` that no longer apply are removed. `CONTRIBUTING.md` lists mise as a prerequisite for a local FFI build.

Alternative: install Rust and its targets ourselves with rustup. The FFI's mise configuration already pins the Rust version, the NDK and the other tools that its CMake presets expect, and keeping our own copy of those pins would drift from it.

### D221. Metal: wrap our device, render into a borrowed ring

The map thread wraps the plugin's `MTLDevice` and command queue with `mln_gpu_device_wrap_metal` and attaches a `MLN_RENDER_TARGET_KIND_METAL_BORROWED_TEXTURES` target with the four slots' textures, in slot order, as `copyFree: true` does today (D182). For `copyFree: false`, the ring has one private texture, and the map thread copies each frame into a free slot on the GPU, as today (D3b).

Alternative for `copyFree: false`: the offscreen target. It is read back through CPU memory, which the `map-texture` requirement on GPU-only frames forbids.

### D222. Android: wrap our EGL context, render to our window surfaces

The map thread creates its EGL context as today, wraps it with `mln_gpu_device_wrap_open_gl` (EGL platform), and attaches a `MLN_RENDER_TARGET_KIND_OPEN_GL_SURFACE` target for the window surface of each `ImageReader`. It keeps setting each frame's id as the presentation time before every service call (D184), because the image listener matches images to slots by it.

Alternatives: `MLN_RENDER_TARGET_KIND_ANDROID_WINDOW` lets the session create the EGL surface itself, so we couldn't set presentation times on it. The exported ring of `AHardwareBuffer`s (`MLN_RENDER_TARGET_KIND_EXPORTED_RING`) would need a way to give Flutter an `android.media.Image` for each buffer, which is a separate redesign.

### D223. Frames: demand, acquire the newest, release with CPU completion

The map thread's loop stays as `docs/architecture.md` describes it, with the caller-graphics-thread driver. `request_frame` becomes `demand_frame`. Unconditional demands keep `MLN_FRAME_DEMAND_FORCE`, and the demands that wait for a render update use `MLN_FRAME_DEMAND_WAIT_FOR_UPDATE`. After each drain, the map thread acquires the newest frame and publishes it into its slot; older frames that it didn't acquire are dropped, as an unchosen ready frame is today. When a slot becomes free (D126 on macOS and iOS, D133 on Android), the map thread releases its frame with `MLN_GPU_SYNC_CPU_COMPLETE`, because Flutter has then presented a later slot and finished reading this one. The new API also reports a producer sync for each acquired frame (`mln_acquired_frame_get_producer_sync`), which the old API didn't have. The map thread waits for it before it publishes the frame, so that Flutter never reads a texture that the GPU is still writing.

### D224. GeoJSON overlays keep their GeoJSON text

The kept state of each overlay (D201) holds the GeoJSON text of each source in place of prepared source data. Commands send it with `mln_map_set_geo_json_source_data`, and after a style load the map thread installs it again from the kept text, still without a round trip to Dart. The FFI now parses and tiles the data in the background, so the reason for D202's `Isolate.run` is reduced to encoding the JSON in Dart above 20,000 points, which stays.

Alternative: keep the data only in Dart and send it again after a style load. That adds a round trip to Dart after each style load, which D201 avoided.

### D225. Status codes and events

The core maps `MLN_STATUS_INVALID_ARGUMENT` from a style JSON parse to the same load failure as before, and treats `MLN_STATUS_ALREADY_EXISTS` from an overlay command as the condition that overlay planning already handles. Events are read from their typed payloads. The log callback adapts to the void return; reporting glyph and sprite failures from map events stays a separate follow-up.

### D226. The map thread keeps each frame's projection

The map thread copies `frame_projection` from each frame result into the published frame of its slot, beside the camera and the camera sequence number. The C ABI to Dart doesn't change in this change.

## Risks / Trade-offs

- [The reshaped C API differs in ways the header diff doesn't show, as the 0.202610.3 port found for cleartext HTTP on Android] → The port runs every integration test on the Mac, the iPhone and the Pixel. A behavior change becomes a delta spec in this change.
- [mln-rs renders differently from the C++ MapLibre Native, such as different anti-aliasing or a missing style feature] → The color check and the static alignment tests compare pixels; a difference that isn't a defect of ours goes in `docs/limitations.md` or `docs/upstream-fixes/`.
- [Performance changes with mln-rs] → The frame-rate and alignment benchmarks on the Mac compare with `main`. A regression is reported to you before the change continues.
- [The branch can't be released until the FFI releases] → Accepted; the release of both packages waits for it.
- [Building the FFI locally now needs mise and its Rust toolchain] → Only contributors build the FFI; application developers get it from the release once there is one.
- [The pinned commit can be force-pushed away or the FFI's `main` changes the C API again before a release] → The pin is a full commit hash on `main`, and the next pin is a port of its own.

## Migration Plan

Nothing reaches users before an FFI release. When a release contains the pinned features, a follow-up sets the lock's release fields, `ffi_pins_test.dart` and `consumer_build.sh` pass again, and both packages can be released.

## Open Questions

- Whether a contributor's local FFI build can be shared between worktrees, as `third_party/maplibre-native-ffi/` is today, given Cargo's shared `build/cargo` directory.
