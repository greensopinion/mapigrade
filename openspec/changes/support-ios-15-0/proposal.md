## Why

The Epic Ride Weather app targets iOS 15.0, and SwiftPM doesn't let a target depend on a package with a higher deployment target, so the app can't depend on flutter_mapigrade while the package's iOS deployment target is 15.5. The 15.5 came from the MapLibre Native FFI. maplibre/maplibre-native-ffi#874 lowers the FFI's iOS deployment target to 15.0. This change can start only after #874 is merged and an FFI release includes it.

## What Changes

- Update the FFI pin to the first FFI release that includes maplibre/maplibre-native-ffi#874.
- Lower the package's iOS deployment target from 15.5 to 15.0, and the iOS deployment target of the demo, the example and the test harness to match.
- Update the documentation that states the iOS deployment target.
- The macOS deployment target stays at 14.3.

## Capabilities

### New Capabilities

### Modified Capabilities
- `map-texture`: the supported platforms requirement states iOS 15.0 or later in place of iOS 15.5 or later.

## Impact

- `packages/flutter_mapigrade/maplibre_ffi.lock` and the remote binary target in `packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift`, which `scripts/update_ffi_pins.sh` writes.
- The `.iOS` platform in `packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift`.
- `IPHONEOS_DEPLOYMENT_TARGET` in the Runner projects of `packages/demo`, `packages/flutter_mapigrade/example` and `packages/test_harness`.
- `packages/flutter_mapigrade/README.md`, `packages/flutter_mapigrade/CHANGELOG.md`, `CONTRIBUTING.md` and `docs/limitations.md`.
- The FFI update also includes every other FFI change since release 0.202610.1.
- The `publish-readiness` change also modifies the supported platforms requirement. The delta in this change is based on that change's text, so archive `publish-readiness` first.
