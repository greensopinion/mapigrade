## 1. Scripts and tests on main

- [x] 1.1 Add `--local` to `scripts/package_xcframework.sh` (D251): check that each of `macos-arm64`, `ios-arm64` and `ios-simulator-arm64` in `third_party/maplibre-native-ffi/` has a `BUILD_INFO` of the lock's commit, zip `MaplibreNativeC.xcframework` with the framework at the zip's top level, and print the checksum; verify that the zip lists `MaplibreNativeC.xcframework/Info.plist` at its top level, and that the script fails and names the preset when one `BUILD_INFO` names another commit
- [x] 1.2 Make `scripts/set_version.sh` accept a prerelease version and set the range to the next prerelease for it, and `version_test.dart` check that rule (D254); verify by running the script with `0.2.0-beta.1` in a scratch copy of the two pubspecs and `flutter test test/version_test.dart` in `flutter_mapigrade`, and that `0.2.0` still gives the range `>=0.2.0 <0.2.1`
  - First done with the exact version as the constraint; task 3.2's dry run warned about it, so the constraint is now the range to the next prerelease (D254). Both forms pass `version_test.dart`, and `0.2.0-beta` is refused.
- [x] 1.3 Replace the test "the lock file names an FFI release" in `ffi_pins_test.dart` with the rules of D252; verify with unit tests over sample lock and pubspec texts: a release version passes, a stable version without a release fails, a prerelease that declares `android` fails, a prerelease with a URL outside `github.com/greensopinion/mapigrade` fails, and a prerelease without `android` and with such a URL passes
- [x] 1.4 Make `scripts/consumer_build.sh` expect an APK without `libmaplibre-native-c.so` and `libmapigrade.so` when the lock names no FFI release (D253); verify by reading the script's check against both cases, and in task 4.2
- [x] 1.5 Add the section "Prerelease without an FFI release" to `docs/releasing.md`, and update `docs/packaging.md` and the comments of the lock, `update_ffi_pins.sh` and `Package.swift` for the hosted archive (D250 to D252); verify by reading each changed section

## 2. Hosted xcframework

- [x] 2.1 Run `scripts/build_maplibre_ffi.sh macos-arm64 ios-arm64 ios-simulator-arm64` from a clean `third_party/maplibre-native-ffi/` and `scripts/package_xcframework.sh --local`; verify that the three `BUILD_INFO` files name `4371ff607e0bd22115d390de27d72a54987cc6c7`, and record the zip's size and checksum in this task
  - Built on 2026-11-27 from a clean `third_party/maplibre-native-ffi/` (the FFI checkout reused its compiled Rust code); the three `BUILD_INFO` files name `4371ff607e0bd22115d390de27d72a54987cc6c7`. `MaplibreNativeC.xcframework.zip`: 16,732,693 bytes, checksum `2b6d362d4f00054e2e3b9e41f4d4ae5d627e75ded2bf472fa08b1c601f51c217`. A second packaging of the same build gives another checksum, because the zip isn't reproducible byte for byte, so the hosted asset must not be replaced (D251).
- [x] 2.2 Write the release notes of D251, and ask the user to create the GitHub prerelease `maplibre-native-ffi-4371ff6` of `greensopinion/mapigrade` with the zip as its asset; verify that `curl -L` of the asset URL downloads a file whose `swift package compute-checksum` equals the checksum of task 2.1
  - The user created the GitHub prerelease `maplibre-native-ffi-4371ff6` on 2026-11-27. The downloaded asset has 16,732,693 bytes and the checksum of task 2.1.
- [x] 2.3 Set the URL and checksum in the lock on `main`, run `scripts/update_ffi_pins.sh`, and move `third_party/maplibre-native-ffi/MaplibreNativeC.xcframework` aside; verify that the test harness builds for macOS and the iOS simulator from the hosted archive and shows the map, that `ffi_pins_test.dart` "Package.swift has the xcframework URL and checksum" passes, and put the local xcframework back
  - The first asset contained the frameworks' extended attributes as `._` files, because `ditto -c -k` stores them by default; `package_xcframework.sh` now passes `--norsrc --noextattr --noacl` in both modes. The user replaced the asset under the same tag (D251). The new zip: 16,684,353 bytes, checksum `ef00de824a5b3d162efbe9fd887a55a07172d9d5e1ea23df52cccaa83dedaef4`.
  - With the local xcframework moved aside, the test harness built for macOS and the iOS simulator from the hosted archive, which was identical to the local build and had no `._` files, and both showed the map. SwiftPM had cached the first asset by its URL and rejected it against the new checksum until the cache entry was deleted, which is why a referenced asset must not be replaced.

## 3. Release branch

- [ ] 3.1 Commit the work of groups 1 and 2 on `mapigrade-map`, and create `release/0.2.0-beta` from it (D250); run `scripts/set_version.sh 0.2.0-beta.1`, remove the `android` entry from `mapigrade`'s plugin platforms (D253), and make the README and CHANGELOG changes of D255; verify that `ffi_pins_test.dart` and `version_test.dart` pass on the branch
- [ ] 3.2 Run `flutter pub publish --dry-run` in both packages on the branch; verify that neither reports a warning, and add `android/` to `mapigrade`'s `.pubignore` on the branch only if the dry run warns about it

## 4. Verification on the release branch

- [ ] 4.1 Run `dart pub global run pana` on both packages in a clean clone of the branch; verify that pana reports no issue it would fix before a release, and that it lists iOS and macOS, not Android, for `mapigrade`
- [ ] 4.2 Run `scripts/consumer_build.sh <work-dir> android ios macos` on the branch with no local FFI build and an empty SwiftPM cache for the archive; verify that every build succeeds, the APK has neither library, and the iOS and macOS applications contain `MaplibreNativeC.framework`
- [ ] 4.3 Install the release build of the consumer application on the iPhone 15 Pro Max, and on the Android emulator, and run the macOS build; verify that the map appears on the iPhone and the Mac, and that on Android the application starts and the `MapigradeCreateException` is reported
- [ ] 4.4 Present the results of tasks 4.1 to 4.3 to the user, and ask whether to publish; record the decision in this task

## 5. Publication

- [ ] 5.1 With the user's approval, the user publishes `mapigrade` and then `flutter_mapigrade` `0.2.0-beta.1` from a clean clone of the branch, and pushes the branch and the tag `v0.2.0-beta.1`; verify on pub.dev that both packages show `0.2.0-beta.1` as a prerelease with the CHANGELOG of D255
- [ ] 5.2 Create a new Flutter application outside the checkout that depends on `flutter_mapigrade: 0.2.0-beta.1` from pub.dev, and build it for macOS and the iOS simulator; verify that both builds succeed and show the map
