## 1. FFI version and release artifacts

- [ ] 1.1 Move `scripts/maplibre_ffi.lock` to `packages/flutter_mapigrade/maplibre_ffi.lock`, add `MAPLIBRE_FFI_VERSION=0.202610.0` and empty `MAPLIBRE_FFI_XCFRAMEWORK_URL` and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` (D99), keep `MAPLIBRE_FFI_COMMIT=677a1cf...` for local builds until stage 2, and make `scripts/build_maplibre_ffi.sh` and `android/build.gradle.kts` read the new path; verify that `grep -rn "scripts/maplibre_ffi.lock"` outside `openspec/changes/archive/` finds nothing and that `scripts/build_maplibre_ffi.sh android-arm64-egl` still succeeds
- [ ] 1.2 Add `scripts/fetch_ffi_release.sh` (D106, step 5), which downloads the tarballs that the package uses and `SHA256SUMS` for `MAPLIBRE_FFI_VERSION` into `third_party/maplibre-native-ffi-release/<version>/`, checks every tarball against `SHA256SUMS`, and skips files already present and valid; verify that a run downloads and checks the files, a second run downloads nothing, and a run after one byte of a tarball is changed fails and names the tarball

## 2. Apple

- [ ] 2.1 Add `scripts/package_xcframework.sh` (D102), which builds `MapLibreNativeC.xcframework.zip` from the fetched `ios-arm64-metal`, `ios-simulator-arm64-metal` and `macos-arm64-metal` tarballs with the framework steps of `scripts/build_maplibre_ffi.sh` and prints the output of `swift package compute-checksum`; verify that the zip has `MapLibreNativeC.xcframework/` at its top level with three slices, that `otool -D` shows the same install names as the local build's frameworks, and that `nm -gU` lists the same `mln_` symbols as the local build's framework for each slice, apart from symbols that the three commits after 0.202610.0 change
- [ ] 2.2 Publish the zip as an asset of a pre-release on a fork of this repository (stage 0), and verify that `curl -L` downloads a file whose `swift package compute-checksum` equals the value from 2.1
- [ ] 2.3 Add `scripts/update_ffi_pins.sh`, which writes `MAPLIBRE_FFI_XCFRAMEWORK_URL` and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` from the lock file into `Package.swift`, and change `Package.swift` to the conditional binary target of D102 and D103; set the lock values to the pre-release of 2.2 and run the script; verify that the macOS test harness builds and shows the map with the local symlink present, and that after the symlink's target is renamed the build downloads the zip into the Swift Package Manager cache and the map appears (then restore the name)
- [ ] 2.4 Change one character of the checksum in `Package.swift`, and verify that package resolution fails with an error that names the zip; revert the change
- [ ] 2.5 Add a unit test that fails when the URL or checksum in `Package.swift` differs from the lock file; verify that it passes, and fails and names the value after one character of the checksum in `Package.swift` is changed (then revert the change)

## 3. Android

- [ ] 3.1 Copy `include/` of the fetched `android-arm64-egl` tarball unchanged to `packages/flutter_mapigrade/android/src/main/cpp/ffi-include/` (D101), and add a test that compares it with the fetched tarball's `include/`, fails and names a header that differs or is missing, and is skipped when the tarball isn't fetched; verify all three outcomes
- [ ] 3.2 Change `android/build.gradle.kts` to release mode (D100, D101): the dependency on `maplibre-native-ffi-runtime-opengl-android:$MAPLIBRE_FFI_VERSION` from `mavenCentral()`, a task that extracts `jni/<abi>/libmaplibre-native-c.so` from the resolved AAR for CMake, `ffi-include/` as the headers, and `abiFilters` `arm64-v8a`, `armeabi-v7a` and `x86_64` (D104); verify that a release APK of the test harness built without a local FFI build has `lib/<abi>/libmaplibre-native-c.so` and `lib/<abi>/libflutter_mapigrade.so` for the three ABIs with no duplicate-file error, and that `readelf -d` on `libflutter_mapigrade.so` lists as `NEEDED` the soname that `readelf -d` reports for the AAR's library
- [ ] 3.3 Add local mode to `android/build.gradle.kts` (D103): when the Gradle property `mapigrade.ffiDir` names an existing directory, use today's library, local verifier repository and `CopyFfiLibrary`, limited to the installed presets' ABIs; log the mode and the version or directory; set the property in the `android/gradle.properties` of the example and the test harness; verify that the test harness's debug build logs local mode and runs on the Pixel, and logs release mode after `third_party/maplibre-native-ffi/` is renamed (then restore the name)
- [ ] 3.4 Build a release APK (with R8) of the test harness without a local FFI build, as in 3.2, install it on the Pixel, and verify that a style and tiles load over HTTPS, so that the AAR's keep rules cover the verifier; check `consumer-rules.pro` still keeps the plugin's own JNI classes

## 4. Notices

- [ ] 4.1 Change `scripts/copy_ffi_notices.sh` to read the fetched release tarballs (D108), and remove its call from `scripts/build_maplibre_ffi.sh`; verify that a run leaves `git status` of `packages/flutter_mapigrade/notices/` unchanged, and that the error rules of D92 still fail on an extra file in a fetched tarball's `licenses/` (extract, change, check, then delete the fetched copy and fetch again)
- [ ] 4.2 Change `test/notices/ffi_notices_test.dart` to compare with the fetched tarballs; verify that it passes, fails and names the file after one byte of a package copy is changed (then revert the change), and reports itself skipped when `third_party/maplibre-native-ffi-release/` is renamed (then restore the name)

## 5. Package metadata and documentation

- [ ] 5.1 Edit `pubspec.yaml` (D105): remove `publish_to: none`; add `repository`, `issue_tracker` and up to five `topics`. Add the `.pubignore` of D105. Verify that `flutter pub publish --dry-run` lists no file with the extension `.so`, `.a`, `.dylib`, `.framework` or `.xcframework`, that its list is the same with and without `third_party/maplibre-native-ffi/`, and that its only warning is the one for uncommitted files
- [ ] 5.2 Update `README.md` (installation: Swift Package Manager only, the downloads of a first build and their sizes, the supported ABIs, the `abiFilters` example), `docs/limitations.md` (replace the arm64-only statement) and `CHANGELOG.md`; verify by reading that no text states that Android supports arm64 only, and that every path the files name exists

## 6. CI

- [ ] 6.1 Add `.github/workflows/consumer-build.yml` with the macOS job of D106 (steps 1 to 5), triggered on pull requests that change the package's native build files, the lock file or `.pubignore`; verify that it passes on a branch, and that it fails when `android/build.gradle.kts` temporarily reads a file through `../../..` (then revert the change)
- [ ] 6.2 Add the Linux job of D106, which installs the test harness's APK on an x86_64 emulator and runs its integration tests; verify that it passes on a branch

## 7. Runtime checks (stage 0, against 0.202610.0)

- [ ] 7.1 Install the release build of the consumer application from 6.1 on the Pixel, and verify that the map appears with a style and tiles loaded over HTTPS and that `MapigradeLayer.isSupported` is true
- [ ] 7.2 Check `adb shell getprop ro.product.cpu.abilist` on the available Android devices; on a device that lists `armeabi-v7a`, run `adb install --abi armeabi-v7a` with the release APK and verify that the map appears with HTTPS loading and `isSupported` is true. If no device lists it, run the same check on a 32-bit device in Firebase Test Lab, and record which was used
- [ ] 7.3 Run the release build on an iPhone and on macOS, and verify that the map appears and `isSupported` is true
- [ ] 7.4 Run `packages/test_harness/integration_test/unsupported_test.dart` on the Pixel as before, and verify that it passes with the release-mode build of 3.2

## 8. Upstream (stage 1)

- [ ] 8.1 Open a pull request to `maplibre/maplibre-native-ffi` that adds `MapLibreNativeC.xcframework.zip` and its checksum to the native release (D107), using the steps of 2.1; record its URL here
- [ ] 8.2 Propose a Prefab module in the runtime AARs to upstream as an issue or pull request, and record its URL here
- [ ] 8.3 After 8.1 is merged, set the lock file to the zip in `unstable-native-snapshot`, run `scripts/update_ffi_pins.sh`, and verify that 6.1 and 7.3 pass with it

## 9. Release pin (stage 2)

- [ ] 9.1 When an upstream release contains #807 and #808, set `MAPLIBRE_FFI_VERSION` and `MAPLIBRE_FFI_COMMIT` to it, and set the zip URL and checksum to the release's zip, or, if 8.1 isn't in the release, to a zip from `scripts/package_xcframework.sh` published on an immutable release of this repository; run `scripts/update_ffi_pins.sh`, `scripts/fetch_ffi_release.sh` and `scripts/copy_ffi_notices.sh`, and verify that the package's tests pass and that `artifact.json` in the fetched tarballs states the commit in the lock file
- [ ] 9.2 Repeat 6.1, 6.2 and 7.1 to 7.4 with the release pin, and verify that `flutter pub publish --dry-run` from a clean checkout reports no warnings
- [ ] 9.3 Before archiving this change, verify that `android-texture-vertical-slice` is archived, so that the `map-texture` delta applies to its requirement "Supported platforms"
