## 1. FFI release

- [ ] 1.1 Wait until maplibre/maplibre-native-ffi#874 is merged and an FFI release includes it; verify with `gh pr view 874 --repo maplibre/maplibre-native-ffi` and the release notes, and verify that `vtool -show-build` reports minos 15.0 for the `ios-arm64` and `ios-arm64-simulator` slices of the release's `MaplibreNativeC.xcframework.zip`
- [ ] 1.2 Check that `publish-readiness` is archived; if it isn't, either archive it first or copy its current text of the supported platforms requirement into `specs/map-texture/spec.md` of this change, with iOS 15.0; verify with `openspec validate support-ios-15-0`

## 2. FFI pin

- [ ] 2.1 Set `MAPLIBRE_FFI_VERSION`, `MAPLIBRE_FFI_XCFRAMEWORK_URL`, `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` and `MAPLIBRE_FFI_COMMIT` in `packages/flutter_mapigrade/maplibre_ffi.lock` to the release of 1.1, and run `scripts/update_ffi_pins.sh`; verify that `packages/flutter_mapigrade/test/ffi_pins_test.dart` passes
- [ ] 2.2 Run `scripts/build_maplibre_ffi.sh` and `scripts/copy_ffi_notices.sh` for the new commit; verify that every preset builds, that the local xcframework's iOS slices report minos 15.0, and review any change to the committed notices
- [ ] 2.3 Adapt the package to any FFI API change since 0.202610.1; verify that the package's tests pass

## 3. iOS deployment target

- [ ] 3.1 Change `.iOS("15.5")` to `.iOS("15.0")` in `packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift`; verify that `flutter build ios --no-codesign` of the example succeeds, which fails if the plugin's Swift sources call an API newer than iOS 15.0
- [ ] 3.2 Set `IPHONEOS_DEPLOYMENT_TARGET` to 15.0 in the Runner projects of `packages/demo`, `packages/flutter_mapigrade/example` and `packages/test_harness`; verify that `git grep 15.5` finds no deployment target outside `openspec/changes/archive`, and that the example's release build embeds an `ios-arm64` slice with minos 15.0 (`vtool -show-build`)

## 4. Documentation

- [ ] 4.1 Change the iOS deployment target to 15.0 in `packages/flutter_mapigrade/README.md` (setup step and platform table), `CONTRIBUTING.md` (iPhone requirement, version table, xcframework description) and `docs/limitations.md`, and add a `CHANGELOG.md` entry; verify by reading each changed line

## 5. Verification

- [ ] 5.1 Run the test harness on the iOS simulator and on the iPhone, and `map_texture_test.dart` and `map_layer_test.dart` on macOS, the iOS simulator and the Pixel; verify that the map appears and the tests pass. Record that no run on iOS 15 was possible unless a device or simulator runtime for iOS 15 is available
