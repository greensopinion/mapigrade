## Why

The macOS vertical slice met its go/no-go criteria: the median displayed map frame rate was 119 fps during continuous pan, with no CPU readback (`benchmarks.md`). iOS is a required platform and macOS isn't, so Stage 2 of the roadmap in `docs/maplibre-native-ffi-flutter-texture-concept.md` tests the same frame path on an iPhone against the 30 fps minimum. iOS also adds constraints that macOS doesn't have: the app can't submit GPU work while it is in the background, and the OS reports memory pressure and expects the app to release memory.

## What Changes

- Add iOS to the `flutter_map_maplibre_texture` plugin. It reuses the C/C++ core (`src/core/`), the Dart API (`lib/src/texture/`) and the Metal bridge, as listed in `limitations.md` ("What the iOS slice can reuse").
- Move the plugin's Apple native code from `macos/` to a shared `darwin/` directory (Flutter's `sharedDarwinSource`), so that macOS and iOS build the same bridge sources. Platform differences (the `Flutter` and `FlutterMacOS` imports, application lifecycle notifications) are handled with conditional compilation in those sources.
- Extend `scripts/build_maplibre_ffi.sh` to build the `ios-arm64-metal` and `ios-simulator-arm64-metal` presets in addition to `macos-arm64-metal`, and produce one `MapLibreNativeC.xcframework` with a slice per platform. The FFI commit stays pinned at `dd97d20f8fab6990cd87c13f091ce00e662707bd`.
- Stop rendering while the iOS app is in the background, and resume when it returns to the foreground, showing the latest camera.
- Release cached renderer resources when iOS reports a memory warning.
- Add an iOS target to the example app, and run the integration tests and the benchmark on iOS.
- Measure on the reference iPhone (iPhone 15 Pro Max, 120 Hz) against the 30 fps minimum and the 60 fps target. Also measure sustained frame rate and thermal state, and the app size increase on iOS.

Out of scope: Android, the `flutter_map` layer and overlay alignment (Stage 3), the iOS simulator as a measurement platform (it is used only for functional tests), Mac Catalyst, x86_64 simulator slices, CocoaPods support, and MapLibre-side gestures or camera animation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-texture`: the capability becomes specified for macOS and iOS. Changed requirements: frame rate (adds the reference iPhone), viewport size and pixel ratio (adds orientation change). New requirements: supported platforms, rendering stops while the app is in the background, and memory warnings release cached renderer resources.

## Impact

- Code: `packages/flutter_map_maplibre_texture/macos/` moves to `darwin/`; the bridge sources gain iOS code paths; `src/core/` gains a pause and resume operation and a memory-reduction command, which have no Apple dependencies. The Dart API doesn't change.
- Example: a new `example/ios/` project. Its minimum iOS version is 15.5, which is the FFI's iOS deployment target.
- Build prerequisites: Xcode with the iOS SDK and an iOS simulator runtime, in addition to the macOS prerequisites. A connected iPhone with a development team for signing is needed for device tests and measurements.
- Distribution: the iOS app bundle includes `MapLibreNativeC.framework`. This change records the size increase.
- Licenses: the iOS build includes the same MapLibre Native and FFI components as the macOS build. The license review that `limitations.md` lists as not done still applies.
