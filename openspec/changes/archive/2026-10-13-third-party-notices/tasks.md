## 1. License and notice files

- [x] 1.1 Replace `packages/flutter_mapigrade/LICENSE` with the BSD 3-Clause license text and the line `Copyright (c) 2026 David Green` (D90), and verify that the text matches the SPDX text of `BSD-3-Clause` apart from the copyright line and that no `TODO` remains
- [x] 1.2 Add `scripts/copy_ffi_notices.sh <preset>...` with the table of D91, failing with the file's name on a file in `licenses/` that isn't in the table and on a common file that differs between presets of the same run (D92); run it with all installed presets, and verify that `packages/flutter_mapigrade/notices/` contains the eight files of D91 and that `cmp` against each preset's source reports no difference
- [x] 1.3 Check the error paths of 1.2: copy an extra file into an installed preset's `licenses/` and verify the script fails and names it; change one byte of a common file in one preset and verify the script fails and names it; remove both changes and verify the script succeeds again
- [x] 1.4 Make `scripts/build_maplibre_ffi.sh` call `scripts/copy_ffi_notices.sh` with the presets it built, after the loop over the presets and before the script exits when no Apple preset was built, and verify by reading the script that an Apple-only, an Android-only and a full run each reach the call

- [x] 1.5 Add a root `LICENSE` identical to `packages/flutter_mapigrade/LICENSE` (D90), and add a test to `test/notices/third_party_notices_test.dart` that fails when the two differ; verify it passes, and fails after one byte of the root copy is changed (then revert the change)

## 2. Registration

- [x] 2.1 Add `lib/src/notices/third_party_notices.dart` with `thirdPartyNotices`, `MapigradeAndroidNotices` and `MapigradeDarwinNotices` (D94, D95), and add the assets of D93 and, for `android`, `ios` and `macos`, `dartPluginClass` and `dartFileName: src/notices/third_party_notices.dart` next to the existing `pluginClass` in `pubspec.yaml`; verify `flutter analyze` in `packages/flutter_mapigrade` reports no issues and `test/api_test.dart` passes with the exported names unchanged
- [x] 2.2 Build the test harness for macOS, for the iOS simulator and as an Android debug APK, and verify that each generated `dart_plugin_registrant.dart` under `.dart_tool/` imports `package:flutter_mapigrade/src/notices/third_party_notices.dart` and calls `MapigradeAndroidNotices.registerWith()` on Android and `MapigradeDarwinNotices.registerWith()` on macOS and iOS
- [x] 2.3 Add `test/notices/third_party_notices_test.dart` (D96, first item), and verify that it passes and that it fails when a file is added to `notices/` without a matching entry in `thirdPartyNotices`

## 3. Comparison with the FFI build

- [x] 3.1 Add `test/notices/ffi_notices_test.dart` (D96, second item), and verify that it passes with the installed presets, that it fails and names the file after one byte of a package copy is changed (then revert the change), and that it reports itself skipped when `third_party/maplibre-native-ffi/` is renamed for the run (then restore the name)

## 4. Devices and builds

- [x] 4.1 Add `packages/test_harness/integration_test/notices_test.dart` (D96, third item), and verify that it passes on macOS and on the iPhone simulator with the six common entries and neither Android name, and on the Android emulator with all eight entries
- [x] 4.2 Add a button to the test harness app's toolbar in `packages/test_harness/lib/main.dart` that opens `showLicensePage`; start the harness with `flutter run` on macOS and on the Android emulator, open the page, and verify with a screenshot that it lists `flutter_mapigrade` with the BSD 3-Clause text, the six common entries, with "MapLibre Native FFI" above the alphabetical list (D95), and on Android only the two Android entries (2026-10-14: on the Android emulator, screenshots and the accessibility tree showed all eight entries, "MapLibre Native FFI" above the list, and the BSD 3-Clause text of `flutter_mapigrade`. On macOS, the screenshot showed "MapLibre Native FFI" above the list and no "Android NDK C++ runtime" at its alphabetical position; this shell can't scroll the macOS app, so the other macOS entries rely on 4.1 and 4.3, and the package license on the `NOTICES` file of the macOS build)
- [x] 4.3 Verify the asset filter of D93: `unzip -l` on the Android debug APK lists `assets/flutter_assets/packages/flutter_mapigrade/notices/common/` and `.../notices/android/`, and the macOS app's and the iOS simulator app's `flutter_assets/packages/flutter_mapigrade/notices/` contain `common/` only

## 5. Documentation and size

- [x] 5.1 Measure the size of the test harness's Android release APK and of the macOS release app before and after this change, and record both differences in `docs/limitations.md`
- [x] 5.2 Update the section "Licenses and third-party notices" in `docs/limitations.md` as D97 describes, and verify that it no longer states that the notices must still be included and that it states that no review of the licenses' acceptability has been done
- [x] 5.3 Update the FFI build section of `README.md` to name `scripts/copy_ffi_notices.sh` and to state that `packages/flutter_mapigrade/notices/` must be committed with a change to `scripts/maplibre_ffi.lock`, and add an entry to `CHANGELOG.md`; verify by reading both that the paths match the files in the repository
