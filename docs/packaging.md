# Packaging

`packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift` declares `MapLibreNativeC.xcframework` as a binary target (through a symlink into `third_party/`), so Xcode links the framework into the app, embeds it in `Contents/Frameworks/` and signs it. The plugin's C++ core (`src/core/`, also a symlink) and the Metal bridge are compiled into the app executable, which exports the `map_texture_*` functions that Dart binds with `@Native`.

On iOS, Xcode embeds and signs the framework in `Runner.app/Frameworks/`. The test harness is arm64 only, because the FFI presets are arm64 only: `ARCHS = arm64` in `packages/test_harness/macos/Runner/Configs/AppInfo.xcconfig`, and `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` in `packages/test_harness/ios/Flutter/Debug.xcconfig` and `Release.xcconfig`.

iOS release build check (2026-10-10): the executable exports all `map_texture_*` functions that Dart binds (`dyld_info -exports`), it loads `@rpath/MapLibreNativeC.framework/MapLibreNativeC` with `@executable_path/Frameworks` as an `LC_RPATH` entry, and the release build displays the map on an iPhone 15 Pro Max.

Release build check (2026-10-09): `otool -L` on the executable shows `@rpath/MapLibreNativeC.framework/Versions/A/MapLibreNativeC`, the only `LC_RPATH` entries are `/usr/lib/swift` and `@executable_path/../Frameworks`, `codesign --verify --deep --strict` passes, and a copy of the `.app` outside the build directory starts and shows the map. In the release bundle, `MapLibreNativeC.framework` takes 12,884 KB of 49,952 KB.
