## Context

See proposal.md for motivation and scope, and specs/third-party-notices/spec.md for the requirements. The last decision of an archived change is D89, so decisions here are numbered from D90.

Current state, as checked in this repository on 2026-10-13:

- `scripts/build_maplibre_ffi.sh` copies each preset's install tree into `third_party/maplibre-native-ffi/<preset>/`, which `.gitignore` excludes. Each tree has `share/maplibre-native-c/LICENSE` (BSD 2-Clause, MapLibre contributors) and `share/maplibre-native-c/licenses/`. All presets have `maplibre-native.md`, `icu.txt`, `fastpfor.txt`, `nunicode.txt` and `pmtiles.txt`, byte-identical across presets. `android-arm64-egl` also has `rust.md` (cargo-about output for 62 crates, 129 KB) and `cxx-runtime.txt` (the NDK's C++ runtime notices, 494 KB). Each preset writes `BUILD_INFO` with the commit and preset name. `share/maplibre-native-c/` also contains files that aren't notices: `artifact.json` (build metadata) in every preset, and `zig-libc` (a Zig configuration with local SDK paths) in the iOS presets. The notices are `LICENSE` and the files in `licenses/`.
- The Android component `rustls-platform-verifier-android` is an AAR whose notices are in the AAR's `META-INF/licenses/`. The APK doesn't contain them. `rust.md` lists `rustls-platform-verifier-android 0.1.1`, so its entry covers the component.
- The example's debug APK contains `assets/flutter_assets/NOTICES.Z`, built by the Flutter tool from the `LICENSE` file of each Dart package. No other license text is in the APK.
- The plugin declares only `pluginClass` for `android`, `ios` and `macos`, and has no assets.
- Flutter 3.47 supports `platforms:` on an asset entry. The tool includes such an asset only when `targetPlatform.osName` is in the list, and includes every asset when the target is the tester (`flutter test`).
- Flutter 3.47 supports `dartPluginClass` together with `pluginClass` for a platform, and `dartFileName` to name a file under `lib/` that the generated registrant imports. The generated registrant calls the class's static `registerWith()` before `main`.

## Goals / Non-Goals

**Goals:**
- An app shows the right notices for its platform with no code in the app.
- An FFI update can't change the notices without the change being visible in review.

**Non-Goals:**
- No change to how the Flutter tool collects the notices of Dart packages.
- No check that an app actually shows `showLicensePage`. That is the app's decision.

## Decisions

### D90. The package is licensed under BSD-3-Clause

`packages/flutter_mapigrade/LICENSE` contains the BSD 3-Clause license text with `Copyright (c) 2026 David Green`. BSD 3-Clause is the license of the Flutter framework and of Google's packages in `flutter/packages`. It is permissive like the BSD 2-Clause licenses of MapLibre Native and the FFI.

Alternative: MIT, the most common license on pub.dev. The user chose BSD 3-Clause.

The repository root gets a copy of the same `LICENSE`, added during implementation at the user's request. Pub and the Flutter tool read the package directory's `LICENSE`, so the package needs its own copy. The root copy covers the files outside the package: the scripts, the docs, the test harness and `assets/`. None of those files is third-party content. A unit test checks that the two files are identical.

### D91. Committed, unchanged copies of the notice files in the package

The package gets a directory `notices/` with two subdirectories:

| Package file | Source in `share/maplibre-native-c/` |
| --- | --- |
| `notices/common/maplibre-native-ffi.txt` | `LICENSE` |
| `notices/common/maplibre-native.md` | `licenses/maplibre-native.md` |
| `notices/common/icu.txt` | `licenses/icu.txt` |
| `notices/common/fastpfor.txt` | `licenses/fastpfor.txt` |
| `notices/common/nunicode.txt` | `licenses/nunicode.txt` |
| `notices/common/pmtiles.txt` | `licenses/pmtiles.txt` |
| `notices/android/rust.md` | `licenses/rust.md` (Android presets) |
| `notices/android/cxx-runtime.txt` | `licenses/cxx-runtime.txt` (Android presets) |

The FFI's `LICENSE` is renamed so that no file other than the package's root `LICENSE` is named `LICENSE`. All other names are the FFI's names. The files are committed. Flutter assets must be inside the package, and `third_party/` is excluded from git. Committing makes the review of every FFI update include the notices: a new crate, a removed crate or a changed license text appears in the diff.

Alternatives:
- Generate the copies with the script and exclude them from git. Rejected: license changes would not appear in review.
- Append the notices to the package's `LICENSE` in the Flutter tool's format (entries separated by 80 `-` characters), so that the tool adds them to `NOTICES` with no runtime code. Rejected: one file serves all platforms, so Apple apps would list 62 Rust crates they don't contain, and the package's own license file would mix with third-party notices.
- Convert the Markdown files to plain text and split them into one entry per crate or library. Rejected by the user: the license requirements are met by the unchanged text, and the conversion adds a parser that an FFI update can break. It can be added later without changing the rest of this design.

### D92. The FFI build script copies the notices

A new script, `scripts/copy_ffi_notices.sh <preset>...`, copies the notice files of the given presets from `third_party/maplibre-native-ffi/` into `packages/flutter_mapigrade/notices/`, using the table of D91. `scripts/build_maplibre_ffi.sh` calls it after its loop over the presets, with the presets it built. A separate script can run without a rebuild, which takes tens of minutes, so its error paths can be checked against an installed preset. It stops with an error, and names the file, when:

- a preset's `licenses/` directory contains a file that isn't in the table, so that a developer decides which platforms the new file applies to and adds it to the table, the pubspec and the registration (D94);
- a common file of one preset differs from the same file of another preset built in the same run.

The table is written once in the script. The Dart code of D94 and the test of D96 have their own lists, and the test checks that all three agree with the files in `notices/`.

### D93. Assets with a platform filter

`pubspec.yaml` declares:

```yaml
flutter:
  assets:
    - path: notices/common/
    - path: notices/android/
      platforms: [android]
```

The Flutter tool leaves `notices/android/` out of macOS and iOS builds. App code reads the assets under the keys `packages/flutter_mapigrade/notices/...`.

### D94. Registration from a `dartPluginClass`

A new file, `lib/src/notices/third_party_notices.dart`, contains:

- `Stream<LicenseEntry> thirdPartyNotices(AssetBundle bundle, {required bool android})`, which loads each file with `bundle.loadString` and yields one `LicenseEntryWithLineBreaks` per file, with the package name of the spec's tables. With `android: false` it yields the six common entries, and with `android: true` it also yields the two Android entries.
- `MapigradeAndroidNotices.registerWith()`, which calls `LicenseRegistry.addLicense(() => thirdPartyNotices(rootBundle, android: true))`.
- `MapigradeDarwinNotices.registerWith()`, which does the same with `android: false`.

`pubspec.yaml` adds `dartPluginClass` and `dartFileName: src/notices/third_party_notices.dart` to each platform: `MapigradeAndroidNotices` for `android`, and `MapigradeDarwinNotices` for `ios` and `macos`. The existing `pluginClass` entries stay. The file is under `lib/src/`, so the main library's exports don't change, and the `package-api` requirements still hold.

`addLicense` only stores the callback. The registry calls it when an app reads the licenses, for example when `showLicensePage` opens, so the files are loaded then and not at startup. `loadString` decodes files larger than 50 KB on another isolate.

Registration doesn't depend on `MapigradeLayer.isSupported`: it calls no native code, and an Android app on a device without the native library still contains the FFI in its APK.

Alternatives:
- Register when the first map is created. Rejected: an app that opens its license page before showing a map would show no FFI notices.
- A public function that the app calls. Rejected: every app would need to call it, and an app that forgets it would ship without the notices. A public API for apps with their own notices page can be added later.
- One class that checks `defaultTargetPlatform`. Rejected: one class per platform family matches the asset filter of D93 directly, and needs no runtime check.

### D95. Entry names and text

Each entry has one package name, from the spec's tables. The text is the file's content unchanged. `LicenseEntryWithLineBreaks` splits paragraphs on blank lines, so the Markdown headings, code fences and `[name](url)` links appear as text. The license texts inside the fences appear unchanged.

`showLicensePage` places the first package that the registry returns above its alphabetical list, on the assumption that it is the app's own package. The registry returns entries in registration order. The generated registrant registers the FFI's notices before `main`, so before the binding's `initLicenses()` registers the Dart packages' licenses (`NOTICES`). So every app shows "MapLibre Native FFI" above the list. All entries are still listed. Before this change the page placed the first package of `NOTICES` there. The Flutter tool sorts `NOTICES`, so that package was effectively the alphabetically first one, and the placement wasn't visible.

Found during implementation, with two attempts to avoid it:
- Registering in a microtask. Rejected: the engine calls the registrant from native code, and the Dart VM runs pending microtasks before `main` starts, so on the Android emulator "MapLibre Native FFI" was still above the list.
- Registering in a timer, or polling with timers until the binding exists. Rejected: the first depends on undocumented ordering of the VM and the engine, and the second adds polling to every app's startup to change the position of one entry.

The user chose to accept the position.

`showLicensePage` merges entries with the same package name. An app that has another dependency with an entry named, for example, "ICU" sees both texts under one name. That is the page's normal behavior for any package.

### D96. Tests

- `test/notices/third_party_notices_test.dart`, a unit test that calls `thirdPartyNotices` with a test `AssetBundle` that returns each file's content from `notices/` on disk. It checks that `android: false` yields the six names and texts, and that `android: true` yields the eight. It also checks that the files in `notices/` are exactly the files the function loads, and that `pubspec.yaml` declares `dartPluginClass` and `dartFileName` for each platform. A test `AssetBundle` is used because the tester includes every asset and doesn't apply the platform filter.
- `test/notices/ffi_notices_test.dart`, a unit test that locates `third_party/maplibre-native-ffi/` from the package directory. For each preset whose `BUILD_INFO` names the commit in `scripts/maplibre_ffi.lock`, it compares `share/maplibre-native-c/LICENSE` and each file in `share/maplibre-native-c/licenses/` with the package's copy, byte for byte, and fails on a difference or on a file the package doesn't contain. Presets built at another commit are ignored, because their notices may differ legitimately. The test is skipped when no preset at the pinned commit is installed.
- `packages/test_harness/integration_test/notices_test.dart`, an integration test that reads `LicenseRegistry.licenses` on a device and checks that each entry name appears exactly once, and the first line of each text. It runs on macOS, the iPhone simulator and the Android emulator. Found during implementation: the integration test's entrypoint runs the generated registrant, as an app's does, and a call to `DartPluginRegistrant.ensureInitialized()` in the test registered the notices a second time, so the test doesn't call it. `TestWidgetsFlutterBinding.initLicenses` doesn't add the Dart packages' licenses (`NOTICES`) to the registry, so the test can't check the package's own license. The license page check (task 4.2) covers it.
- The test harness app gets a button that opens `showLicensePage`, for the manual check in task 4.2.
- A build check that the macOS app and the iOS app don't contain `notices/android/`, and that the Android APK contains both directories.

### D97. Documentation

`docs/limitations.md` replaces "We have not completed a license review" with: the package shows the FFI's notices in the license registry (this change), and no review of whether the licenses are acceptable has been done. The table adds `rust.md` and `cxx-runtime.txt` for Android, and the paragraph on Rust crates states that their notices are shown on Android only. The README's section on the FFI build states that the script also updates `packages/flutter_mapigrade/notices/`, and that those files must be committed with a change to `scripts/maplibre_ffi.lock`. `CHANGELOG.md` gets an entry.

## Risks / Trade-offs

- [App size: about 720 KB of text in Android apps and 97 KB in Apple apps] → Text compresses well in the APK and IPA. Task 5.1 measures the APK size before and after. The notices are required, so the alternative is only a smaller format, which D91 rejected.
- [The Markdown files are hard to read on the license page] → The license texts are complete and unchanged. Conversion can be added later (D91).
- [The integration test's entrypoint may not run the generated registrant, so the test would pass for the wrong reason or fail] → It does run it (D96). Task 4.2 also opens `showLicensePage` in the test harness app, started with `flutter run`, which runs the real registrant, and checks that the page lists the entries.
- [Someone changes `scripts/maplibre_ffi.lock` without running the script, so the committed notices belong to the old commit] → The test of D96 ignores presets built at another commit, so it doesn't detect this. The Android build fails, because the plugin's Gradle build derives the verifier's Maven version from the lock file and that version isn't installed. Once the script runs, it updates the notices, and the diff shows the changes. The README states that the notices must be committed with a change to the lock file (D97).
- [`dartFileName` under `lib/src/` is unusual] → The Flutter tool documents it for this purpose, and the generated registrant imports the file directly. Task 2.2 checks the generated registrant on each platform.
- [`showLicensePage` reads the registry only when it opens, so an error in loading an asset appears only then] → The integration test reads every entry's text on each platform.
