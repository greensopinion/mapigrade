## Context

See proposal.md for motivation and scope, and the specs for the requirements. The last decision of an archived or in-progress change is D97 (`third-party-notices`), so decisions here are numbered from D98.

Current state, as checked on 2026-10-13:

- `flutter pub publish --dry-run` in `packages/flutter_mapigrade` reports a 23 MB archive and two warnings: modified files in git, and no `homepage` or `repository`. Pub follows the checked-in symlink `darwin/flutter_mapigrade/Frameworks/MapLibreNativeC.xcframework`, whose target `third_party/maplibre-native-ffi/MapLibreNativeC.xcframework` is git-ignored, and packs the framework. It also follows `Sources/flutter_mapigrade/core`, which points to `src/core` inside the package.
- `android/build.gradle.kts` sets `repositoryRoot` to `../../..` and reads from it `third_party/maplibre-native-ffi/android-arm64-egl/` (library and headers, passed to CMake as `MLN_FFI_DIR`), `third_party/maplibre-native-ffi/android-maven/` (the patched `rustls-platform-verifier-android`, added to every project of the build) and `scripts/maplibre_ffi.lock`. `android/src/main/cpp/CMakeLists.txt` reads `src/core` through `../../../../src/core`, which is inside the package.
- `scripts/maplibre_ffi.lock` pins commit `677a1cf`, three commits after the upstream release `core/v0.202610.0` (`dd97d20`). Two of them are #807 and #808, which this repository needs.
- The upstream project `maplibre/maplibre-native-ffi` publishes:
  - a GitHub release per version (0.202608.0, 0.202609.0, 0.202609.1, 0.202610.0) with `maplibre-native-c-<preset>.tar.gz` for 32 presets and `SHA256SUMS`. Each tarball contains `include/`, `lib/` (shared and static libraries), `share/maplibre-native-c/LICENSE`, `share/maplibre-native-c/licenses/` and `artifact.json` (`gitSha`, `version`). The Apple tarballs contain `libmaplibre-native-c.dylib`; no release contains an xcframework.
  - a rolling pre-release `unstable-native-snapshot`, whose assets are replaced.
  - on Maven Central, `org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android:0.202610.0`, an AAR of 16.9 MB with `jni/{arm64-v8a,armeabi-v7a,x86_64}/libmaplibre-native-c.so` (12.8, 8.6 and 13.4 MB), `libs/rustls-platform-verifier-android.jar` (`org.maplibre.nativeffi.internal.rustlsplatformverifier.*`), `proguard.txt` keeping those classes, and `META-INF/licenses/` for `maplibre-native-c`, `rustls-platform-verifier` and `android-ndk`. Its manifest declares `minSdkVersion 24` and no components; `classes.jar` contains one marker class. It has no Prefab module and no headers. Its only dependency is `kotlin-stdlib`.
- The library that this repository's script builds for `android-arm64-egl` is 29 MB with debug information; the upstream library is 12.8 MB. AGP strips both when it packages an APK.
- `flutter pub publish` and `dart pub` in Flutter 3.47.5 have no option that writes the archive to a file.
- The names `flutter_mapigrade` and `mapigrade` are free on pub.dev.

## Goals / Non-Goals

**Goals:**
- An app that depends on the published package builds and runs on every supported platform with only pub.dev, Maven Central and GitHub release downloads.
- One file states the FFI version, and every artifact the package uses comes from that version.
- Repository development can still use an FFI commit that has no release.

**Non-Goals:**
- No hosting of Android artifacts by this repository.
- No change to `src/core` or to the plugin's Dart API.

## Decisions

### D98. Upstream releases are the only source of released native libraries

The package uses the upstream release artifacts as they are: the runtime AAR on Android, and an xcframework zip on Apple platforms (D102). We don't build the FFI for a release of the package. The first release waits for an upstream release that contains #807 and #808.

Alternatives:
- Bundle the binaries in the archive. Rejected: about 35 MB per version in every consumer's pub cache, all platforms downloaded by every consumer, and a full FFI build before every publish. Of 21 packages with native libraries that we checked on pub.dev, 5 bundle them; MapLibre's and Mapbox's Flutter packages don't.
- Build our own binaries and host them. Rejected: requires the full FFI toolchain in the release process, and adds hosting that upstream already provides.
- Build the FFI from source in consumer builds. Rejected: 754 MB of source with 60 submodules, and Rust, CMake and an exact NDK on every consumer machine.

### D99. The lock file moves into the package

`scripts/maplibre_ffi.lock` moves to `packages/flutter_mapigrade/maplibre_ffi.lock`, because a published package can only read files inside itself. It keeps its shell syntax, so `scripts/build_maplibre_ffi.sh` can still source it, and gains:

- `MAPLIBRE_FFI_VERSION`: the upstream release version, for example `0.202611.0`.
- `MAPLIBRE_FFI_COMMIT`: the commit of that release's tag, which `artifact.json` states as `gitSha`. The local build uses it unless the developer gives another commit.
- `MAPLIBRE_FFI_XCFRAMEWORK_URL` and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM`.

`android/build.gradle.kts` reads the file at configuration time, as it reads the old lock file today. `Package.swift` can't depend on reading it, so `scripts/update_ffi_pins.sh` writes the URL and checksum into `Package.swift`, and a unit test fails when the two files disagree.

### D100. Android depends on the upstream runtime AAR

`android/build.gradle.kts` declares `implementation("org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android:$MAPLIBRE_FFI_VERSION")` with `mavenCentral()` in the plugin's repositories. A Flutter app's default `settings.gradle.kts` already includes `mavenCentral()`. The AAR gives the app the native library for three ABIs, the verifier classes and their keep rules. The plugin's `rootProject.allprojects` repository block, the dependency on the local verifier and `CopyFfiLibrary` are used only in local mode (D103).

Alternatives:
- Download the `android-*-egl` tarballs in a Gradle task and check them against pinned SHA-256 values. Rejected: the verifier would have to be vendored, the downloads bypass Maven repository proxies, and the task has to manage its own cache.
- Publish our own AAR with a Prefab module. Rejected: Maven Central publishing (namespace, signing) for an artifact upstream already publishes.

### D101. Linking against the AAR's library

CMake needs the library and the headers at link time, and the AAR has neither a Prefab module nor headers.

- Library: a Gradle task resolves the AAR through a configuration with the same coordinates, extracts `jni/<abi>/libmaplibre-native-c.so` into `build/`, and passes the directory to CMake as the imported library's location. CMake links against it only. The APK gets the copy that AGP packages from the AAR, so the plugin adds nothing to `jniLibs` and no duplicate file arises.
- Headers: the release's `include/` is committed to `android/src/main/cpp/ffi-include/`, unchanged, as D91 does for the notices: an FFI update then shows API changes in the diff. A test compares the committed headers with the release tarball's `include/` when the tarball is present (D106). Apple builds use the headers in the framework, through `src/core/mln.h`.

Alternatives:
- Upstream adds a Prefab module to the AAR, and CMake uses `find_package(maplibre-native-c CONFIG REQUIRED)`. This is the better result; we propose it upstream (D107) and adopt it in a later version. It doesn't block this change.
- `libflutter_mapigrade.so` resolves the FFI functions at runtime through `dlopen` and a function table. Rejected: changes every call site in `src/core`.

### D102. Apple uses a remote binary target

`Package.swift` declares `MapLibreNativeC` as `.binaryTarget(name:url:checksum:)` with the values from D99. When `Frameworks/MapLibreNativeC.xcframework` exists in the package directory, it declares `.binaryTarget(name:path:)` in its place (D103). `.pubignore` excludes `darwin/flutter_mapigrade/Frameworks/`, so a published archive never contains a framework and always uses the URL. Swift Package Manager downloads the zip while Xcode resolves packages, checks the checksum and caches the zip.

The zip comes from the upstream release when upstream publishes it (D107). Until then, `scripts/package_xcframework.sh` builds it from the release's `ios-arm64-metal`, `ios-simulator-arm64-metal` and `macos-arm64-metal` tarballs, after checking `SHA256SUMS`, with the steps that `scripts/build_maplibre_ffi.sh` uses today: wrap each dylib in a framework, set its install name, run `xcodebuild -create-xcframework`. We attach the zip to a release of this repository, with GitHub's immutable releases enabled.

Alternatives:
- A build hook that downloads the dylib tarballs and declares each dylib as a code asset. Rejected: `src/core` and `MapTextureMetal.mm` link against `MapLibreNativeC` at link time and would have to resolve it at runtime, and we haven't checked whether Flutter runs build hooks before Xcode resolves plugin packages.

### D103. Local mode for repository development

The package builds against a local FFI build in this repository, and against the released artifacts everywhere else:

- Apple: `Package.swift` uses the path binary target when the symlink `Frameworks/MapLibreNativeC.xcframework` resolves to an existing framework. In a published archive the symlink is absent (D102).
- Android: `android/build.gradle.kts` uses today's build, with the local library, the local verifier repository and `CopyFfiLibrary`, when the Gradle property `mapigrade.ffiDir` names an existing directory. The example and the test harness set it in their `android/gradle.properties`. In a consumer's pub cache the directory doesn't exist, so the plugin uses the AAR. Gradle logs which mode it uses. Local mode builds only the ABIs that the local build installed.

The two modes don't mix, because the AAR and the local build would both package `libmaplibre-native-c.so`.

Alternative: release mode only, with local FFI builds published to a local Maven repository. Rejected: every FFI commit under test would need a Maven publication and an xcframework zip.

### D104. ABIs

The plugin's `abiFilters` are `arm64-v8a`, `armeabi-v7a` and `x86_64`, the ABIs of the AAR. An app building for another ABI, such as 32-bit `x86`, gets neither library for it, and the requirement "Unsupported architectures" applies there. An app that wants only `arm64-v8a` sets `abiFilters` in its own module, as the README already describes.

### D105. Pubspec and `.pubignore`

`pubspec.yaml` drops `publish_to: none` and adds `repository: https://github.com/greensopinion/mapigrade`, `issue_tracker: https://github.com/greensopinion/mapigrade/issues` and `topics` (at most five, for example `maps`, `maplibre`, `flutter-map`). The version stays `0.0.1`.

A `.pubignore` in the package root makes pub ignore the package's `.gitignore`, so the `.pubignore` repeats its entries, adds `darwin/flutter_mapigrade/Frameworks/` and `android/.cxx/`, and keeps the `test/` directory, including `test/native/`, in the archive.

### D106. A consumer build from the archive in CI

A GitHub Actions workflow on a macOS runner, which has no FFI build:

1. Reproduces the archive: runs `flutter pub publish --dry-run`, takes the file list it prints, and copies those files, with symlinks resolved, to a directory outside the checkout. Flutter 3.47.5 can't write the archive to a file.
2. Creates an app with `flutter create` outside the checkout, with a path dependency on that directory and the example's `lib/main.dart`.
3. Builds `flutter build apk --release`, `flutter build ios --simulator`, `flutter build ios --no-codesign` and `flutter build macos`.
4. Checks that the APK's `lib/` has both libraries for each of the three ABIs, and that the iOS and macOS apps contain `MapLibreNativeC.framework`.
5. Runs `scripts/fetch_ffi_release.sh`, which downloads the pinned release's tarballs and `SHA256SUMS` into the git-ignored `third_party/maplibre-native-ffi-release/<version>/` and checks them, and runs the tests that compare the committed headers (D101) and notices (D108) with them. `scripts/package_xcframework.sh` (D102) and `scripts/copy_ffi_notices.sh` (D108) read the tarballs from the same directory.

The workflow runs on pull requests that change the package's native build files, the lock file or `.pubignore`. A second job on a Linux runner with KVM installs the APK on an x86_64 emulator and runs the test harness's integration tests: the Android emulator on Apple-silicon Macs runs only arm64 system images. The other runtime checks need devices and are tasks, not CI: an arm64 Android device, `armeabi-v7a` through `adb install --abi armeabi-v7a` on a device whose `ro.product.cpu.abilist` lists it, an iPhone and macOS. Each runs a release build that loads a style over HTTPS, which exercises the verifier's keep rules under R8.

### D107. Upstream contribution

We propose a pull request to `maplibre/maplibre-native-ffi` that adds `MapLibreNativeC.xcframework.zip`, assembled from the Apple presets as in D102, and its checksum to the native release, and, separately, a Prefab module in the runtime AARs. The MapLibre organization already publishes an xcframework zip for Swift Package Manager: `maplibre-native` releases contain `MapLibre.dynamic.xcframework.zip`, which `maplibre-gl-native-distribution` declares as a remote binary target.

Before the pull request, we build the zip from upstream tarballs and run it as a remote binary target on macOS and an iPhone, so the proposal describes an assembly that works. We do that first, before the Android and CI work, because the zip is only in the release that this change waits for if the pull request is merged before that release. The Prefab proposal needs no prototype and can be raised at any time.

Upstream's `AI_POLICY.md` requires the contributor to write issues, pull request descriptions and review replies, and to read every line submitted. The user writes and opens both proposals. The implementation on a branch of a fork follows upstream's conventions (mise tasks, `hk` checks, `ci:test`).

### D108. Notices from the release

`scripts/copy_ffi_notices.sh` reads the notice files from the release tarballs of the pinned version: the common files from an Apple preset's tarball and the Android files from `android-arm64-egl`, with the table and error rules of D91 and D92. `scripts/build_maplibre_ffi.sh` no longer calls it, because a local build may be at a commit without a release.

We compared the 0.202610.0 artifacts on 2026-10-13. The AAR's `META-INF/licenses/maplibre-native-c/` files are byte-identical to the `android-arm64-egl` tarball's `licenses/`, and its `android-ndk/NOTICE` is byte-identical to `cxx-runtime.txt`. The package's committed notices, copied from the local build at `677a1cf`, are byte-identical to the 0.202610.0 tarball's. The AAR also contains `rustls-platform-verifier/` (`LICENSE-APACHE`, `LICENSE-MIT`, and a `NOTICE` that describes the FFI project's modifications). `rust.md` already lists `rustls-platform-verifier-android 0.1.1` and `rustls-platform-verifier 0.6.2`, which the `third-party-notices` change accepted as covering the component, so the license entries don't change.

## Risks / Trade-offs

- [The upstream release containing #807 and #808 is later than planned] → 0.0.1 waits for it, as decided. Stage 0 runs against 0.202610.0, which lacks the fixes; they affect resizing, not packaging.
- [Upstream doesn't accept the xcframework zip, or not in time] → D102's fallback: our own zip built from upstream tarballs, which needs only Xcode.
- [A release asset that a published version points to is deleted] → Builds of that version fail. Our own releases are immutable; for upstream assets we have no control, and the version would need a new release.
- [First builds need network access; organizations that block GitHub downloads can't resolve the Apple binary target] → Documented in the README. Android goes through Maven Central, which repository proxies mirror.
- [The C++ core or the JNI bridge has 32-bit faults] → The `armeabi-v7a` runtime check of D106. No such device is known to be available; Firebase Test Lab is the alternative.
- [Local mode hides a release-mode fault] → D106 builds in release mode on every relevant pull request, and Gradle logs the mode.
- [Swift Package Manager rejects the conditional `binaryTarget`, or a non-HTTPS URL for stage 0] → Checked in stage 0; stage 0 hosts the zip on a pre-release of a fork.
- [The AAR's `.so` has a different soname from the local build's] → `readelf -d` on both in stage 0; `libflutter_mapigrade.so` records the soname it linked against.
- [APK size grows by about 22 MB before compression for the two added ABIs] → Apps that publish app bundles download one ABI per device; apps can filter ABIs.

## Migration Plan

1. Stage 0, against 0.202610.0: build the zip with `scripts/package_xcframework.sh`, publish it on a fork's pre-release, and run it as a remote binary target on macOS and an iPhone.
2. Stage 1: raise Prefab and open the xcframework zip pull request upstream (D107). While upstream reviews them, implement the rest of D99 to D106 against 0.202610.0 and run D106 and the runtime checks. After the pull request is merged, repeat the checks against `unstable-native-snapshot`.
3. Stage 2: pin the release that contains #807, #808 and, if accepted, the zip. Run `scripts/update_ffi_pins.sh`, the notices script and D106, and confirm that the dry run reports no warnings.

Nothing is published before stage 2, so there is no rollback beyond reverting commits.

## Open Questions

- Prefab: whether upstream accepts it, and in which release. Adopting it replaces D101's extraction task without changing the specs.
- The exact `topics`.
