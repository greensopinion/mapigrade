# Packaging

`packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift` declares `MapLibreNativeC.xcframework` as a binary target (through a symlink into `third_party/`), so Xcode links the framework into the app, embeds it in `Contents/Frameworks/` and signs it. The plugin's C++ core (`src/core/`, also a symlink) and the Metal bridge are compiled into the app executable, which exports the `map_texture_*` functions that Dart binds with `@Native`.

On iOS, Xcode embeds and signs the framework in `Runner.app/Frameworks/`. The test harness is arm64 only, because the FFI presets are arm64 only: `ARCHS = arm64` in `packages/test_harness/macos/Runner/Configs/AppInfo.xcconfig`, and `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` in `packages/test_harness/ios/Flutter/Debug.xcconfig` and `Release.xcconfig`.

Xcode removes every global symbol from the app executable when it archives the app, because `STRIP_STYLE` defaults to `all` and archiving sets `DEPLOYMENT_POSTPROCESSING`. Dart's `@Native` lookup and `nativeLibraryAvailable` then can't find `map_texture_create`, so an app must set `STRIP_STYLE = non-global` for the `Runner` target's Release and Profile configurations (plugin README, Supported platforms). `flutter build` and `flutter run --release` don't set `DEPLOYMENT_POSTPROCESSING`, so their executables keep the symbols. The release build check below used such a build. The examples and the test harness don't set `STRIP_STYLE`.

iOS release build check (2026-10-10): the executable exports all `map_texture_*` functions that Dart binds (`dyld_info -exports`), it loads `@rpath/MapLibreNativeC.framework/MapLibreNativeC` with `@executable_path/Frameworks` as an `LC_RPATH` entry, and the release build displays the map on an iPhone 15 Pro Max.

Release build check (2026-10-09): `otool -L` on the executable shows `@rpath/MapLibreNativeC.framework/Versions/A/MapLibreNativeC`, the only `LC_RPATH` entries are `/usr/lib/swift` and `@executable_path/../Frameworks`, `codesign --verify --deep --strict` passes, and a copy of the `.app` outside the build directory starts and shows the map. In the release bundle, `MapLibreNativeC.framework` takes 12,884 KB of 49,952 KB.

## Android

`packages/flutter_mapigrade/android/` is a Gradle library module (`minSdk` 29, `ndkVersion` 30.0.16248370, `abiFilters` `arm64-v8a`). Its CMake build (`android/src/main/cpp/CMakeLists.txt`) compiles the C++ core and the Android render target into `libflutter_mapigrade.so`, and links `libmaplibre-native-c.so` from `third_party/maplibre-native-ffi/android-arm64-egl/` as an imported library. Gradle packages both libraries in the APK under `lib/arm64-v8a/`: the plugin's from the CMake build, and the FFI's through a generated `jniLibs` directory. Both libraries link the NDK's C++ runtime statically (`c++_static`); only the C ABI crosses between them. Both have 16 KB segment alignment, which devices and emulators with 16 KB pages require.

The module adds the file-based Maven repository `third_party/maplibre-native-ffi/android-maven/` and depends on the FFI's patched `rustls-platform-verifier` Android component (`org.maplibre.nativeffi:rustls-platform-verifier-android`, versioned by the first 12 characters of the FFI commit). The APK needs it, because `mln_android_init` uses it to verify TLS certificates with the Android platform verifier.

The plugin class loads `libflutter_mapigrade.so` with `System.loadLibrary`. The package's build hook (`hook/build.dart`) declares the same library as a code asset with link mode `DynamicLoadingSystem`, so Flutter adds no file to the APK, and Dart's lookup by name returns the library that is already loaded (design D56 of the android-texture-vertical-slice change).

Android release build check (2026-10-16, FFI commit `677a1cfdf1ab2b914f633d4abc790b7136d3a321`): the release APK contains `libflutter_mapigrade.so` and `libmaplibre-native-c.so` for `arm64-v8a` only, stored uncompressed, and the release build starts on a Pixel 4a (5G) with Android 14, logs a successful `mln_android_init`, and shows the map with a style and tiles loaded over HTTPS. Sizes are in `limitations.md`.
