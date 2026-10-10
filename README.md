# flutter_native_map

A proof of concept that renders a MapLibre Native map on the GPU into a Flutter `Texture` widget on macOS, through MapLibre Native FFI, with no platform view and no CPU pixel readback. Flutter widgets placed above the map draw on top of it and receive input.

- Design and requirements: `openspec/changes/archive/2026-10-09-macos-texture-vertical-slice/`
- Measurements: `benchmarks.md`
- Limitations, licenses and what iOS can reuse: `limitations.md`

## Repository layout

```
packages/flutter_map_maplibre_texture/   Flutter plugin (macOS only)
  lib/src/texture/                       Dart API: MapTextureController, MapTextureView, @Native bindings
  lib/src/layer/                         flutter_map layer (later change; empty)
  src/core/                              C++ core: map thread, commands, buffer state, C ABI (no Apple dependencies)
  darwin/flutter_map_maplibre_texture/   Swift package: Metal render target, FlutterTexture, plugin class
  test/                                  Dart unit tests; test/native/ C++ unit tests for the core
example/                                 macOS example app, integration tests, benchmark, color check
scripts/build_maplibre_ffi.sh            builds the pinned MapLibre Native FFI
scripts/maplibre_ffi.lock                the pinned FFI commit and preset
third_party/                             FFI checkout and build output (gitignored)
```

## Architecture

### Threads

```
 Dart (main isolate, platform thread)          map thread (one per map)                 Flutter raster thread
 ───────────────────────────────────           ─────────────────────────                ─────────────────────
 MapTextureController                          owns mln_runtime, mln_map,
   loadStyleUrl/Json, resize ──► ordered queue ──┐  mln_render_session
   setCamera ─────────────────► camera slot  ──┤
                  (both then mln_wake_source_signal)
                                               │ loop:
                                               │   mln_runtime_pump (parks until a wake)
                                               │   apply queued commands, then the latest camera
                                               │   drain events ── style loaded, loading failed,
   events stream ◄── NativeCallable.listener ◄─┤                   render error, idle
                                               │   if a render update is pending, Flutter has
                                               │   taken the latest frame, and a buffer is free:
                                               │     render_update into the render texture
                                               │     blit into the free IOSurface buffer
                                               │     publish it as latest
                                               │     textureFrameAvailable (via main queue)
                                               │                                        copyPixelBuffer:
                                               │                                          latest → presented,
   frames stream ◄── NativeCallable.listener ◄─┼──────────── frame displayed ◄─────────── return the buffer,
                                               └◄──────── wake (frame taken) ◄───────────  report its camera
```

Dart never calls MapLibre. It calls the plugin's C ABI (`src/core/map_texture_api.h`), whose functions only write to the command queue or camera slot and wake the map thread. The map thread is the owner thread of the runtime, map and render session, as the FFI requires. Camera updates coalesce in the slot, so the map renders the latest camera only. Consecutive resizes also coalesce.

### Frame path

```
MapLibre (Metal) ──render──► private MTLTexture (BGRA8, one per size)
                 ──blit────► IOSurface-backed CVPixelBuffer (one of three: latest, presented, free)
                 ──────────► FlutterTexture.copyPixelBuffer ──► Flutter composites it as a Texture widget
```

All copies stay on the GPU. The three buffers ensure that the map thread never writes into the buffer Flutter displays or the one it displays next. The map renders only when MapLibre publishes a render update, and only after Flutter has taken the previous frame, so it renders nothing while the map is idle and no more frames than the display shows.

Each displayed frame is reported to Dart with the camera and size it was rendered with (`MapTextureController.frames`), taken from `mln_render_session_projection_create()` after the frame rendered.

## Pinned versions

| Component | Version |
| --- | --- |
| MapLibre Native FFI | commit `dd97d20f8fab6990cd87c13f091ce00e662707bd`, preset `macos-arm64-metal` (`scripts/maplibre_ffi.lock`) |
| Flutter | 3.47.5 stable (framework `6a19cca564`, engine `ab598368592d`), Dart 3.13.4 |
| Xcode | 26.6 (17F113), macOS SDK, deployment target macOS 14.3 |

The plugin uses Swift Package Manager, the native build integration that the Flutter 3.47.5 plugin template uses by default. It has no podspec, so CocoaPods builds are not supported.

## Prerequisites

- An Apple silicon Mac with macOS 14.3 or later
- Xcode 26.6 with the macOS SDK
- Flutter 3.47.5 with macOS desktop support
- git and [mise](https://mise.jdx.dev) (`brew install mise`); the build script installs CMake, Ninja, Rust and cargo-about through mise
- CMake for the C++ unit tests (`brew install cmake`)

## Build and run

```sh
# 1. Build MapLibre Native FFI (about 4 minutes on an M2 Max)
scripts/build_maplibre_ffi.sh

# 2. Run the example app
cd example
flutter run -d macos
```

The example shows the map with a control panel above it: style selection (OpenFreeMap Liberty, MapLibre demo tiles, and an invalid URL that shows the reported failure), zoom, rotate and pan buttons, and a continuous pan switch that changes the camera on every Flutter frame. `--dart-define=LOG_FRAMES=true` prints every displayed frame with its camera.

## Tests

```sh
# C++ unit tests for the core (no MapLibre)
cd packages/flutter_map_maplibre_texture
cmake -S test/native -B build/native-tests
cmake --build build/native-tests
ctest --test-dir build/native-tests --output-on-failure

# Dart unit tests (including the check that lib/src/texture/ doesn't import flutter_map)
flutter analyze
flutter test

# macOS integration tests for the spec scenarios (about 30 s, needs network access)
cd ../../example
flutter test integration_test -d macos
```

## Measurements

```sh
cd example
flutter build macos --release --dart-define=BENCHMARK=true
MLT_WINDOW_SIZE=1600x1000 \
  build/macos/Build/Products/Release/flutter_map_maplibre_texture_example.app/Contents/MacOS/flutter_map_maplibre_texture_example
```

The app pans for 30 s to load the area, pans the same path again for 30 s while measuring, prints a line starting with `BENCHMARK_RESULT`, and exits. Results are in `benchmarks.md`.

Instruments' `xctrace` launches an app by its bundle identifier, which the Debug and Release builds share. Delete `build/macos/Build/Products/Debug/flutter_map_maplibre_texture_example.app` before tracing the Release build, or `xctrace` starts the Debug build.

## MapLibre Native FFI build details

The script:

1. clones `https://github.com/maplibre/maplibre-native-ffi.git` into `third_party/maplibre-native-ffi-src/` and checks out the pinned commit;
2. runs the FFI repository's `.mise/bin/sync-submodules`, which fetches MapLibre Native and the vendor submodules the build needs and applies the FFI's patches;
3. runs `cmake --preset macos-arm64-metal` and `cmake --build … --target install`, with CMake, Ninja, Rust and cargo-about installed by `mise exec` at the versions the FFI repository's `mise.toml` pins;
4. copies the install tree into `third_party/maplibre-native-ffi/` and wraps the dylib in `MapLibreNativeC.xcframework` for the Flutter plugin.

Output in `third_party/maplibre-native-ffi/` (gitignored):

- `lib/libmaplibre-native-c.dylib` and `include/maplibre_native_c.h`
- `MapLibreNativeC.xcframework`: a versioned macOS framework with install name `@rpath/MapLibreNativeC.framework/Versions/A/MapLibreNativeC`, the headers and a module map
- `share/maplibre-native-c/`: the FFI license and third-party notices

Measured on an Apple M2 Max, macOS 26.6.2, Xcode 26.6, from a clean checkout:

- total wall time 239 s (clone, submodules, mise tool install, configure and build); configure and build alone 123 s
- `libmaplibre-native-c.dylib`: 13,242,488 bytes (12.6 MiB), arm64 only

### Check the build with the upstream example

```sh
cd third_party/maplibre-native-ffi-src/examples/swift-map
export PKG_CONFIG_PATH="$PWD/../../build/macos-arm64-metal/install/share/pkgconfig"
swift build --product swift-map --scratch-path .build/macos-arm64-metal \
  -Xlinker -rpath -Xlinker "$PWD/../../build/macos-arm64-metal/install/lib"
.build/macos-arm64-metal/debug/swift-map borrowed-texture
```

The window shows a map of San Francisco.

## Packaging

`packages/flutter_map_maplibre_texture/darwin/flutter_map_maplibre_texture/Package.swift` declares `MapLibreNativeC.xcframework` as a binary target (through a symlink into `third_party/`), so Xcode links the framework into the app, embeds it in `Contents/Frameworks/` and signs it. The plugin's C++ core (`src/core/`, also a symlink) and the Metal bridge are compiled into the app executable, which exports the `map_texture_*` functions that Dart binds with `@Native`.

The example app is arm64 only (`ARCHS = arm64` in `example/macos/Runner/Configs/AppInfo.xcconfig`), because the FFI preset is arm64 only.

Release build check (2026-10-09): `otool -L` on the executable shows `@rpath/MapLibreNativeC.framework/Versions/A/MapLibreNativeC`, the only `LC_RPATH` entries are `/usr/lib/swift` and `@executable_path/../Frameworks`, `codesign --verify --deep --strict` passes, and a copy of the `.app` outside the build directory starts and shows the map. In the release bundle, `MapLibreNativeC.framework` takes 12,884 KB of 49,952 KB.

## Color check

`example/lib/color_check.dart` (`flutter run -d macos -t lib/color_check.dart`) shows a map whose style has a `#3366CC` background and a `#E6B31A` fill, and Flutter swatches of the same colors below it. In a window screenshot (Display P3, 2026-10-09) the map and the swatches measured:

| Color | Map | Flutter swatch | Largest channel difference |
| --- | --- | --- | --- |
| fill `#E6B31A` | 222, 181, 67 | 222, 181, 67 | 0 |
| background `#3366CC` | 64, 101, 197 | 64, 100, 197 | 1 |

Both are within the 2/255 tolerance, so the IOSurface buffers need no explicit color space.
