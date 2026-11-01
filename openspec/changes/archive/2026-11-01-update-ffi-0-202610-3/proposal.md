## Why

MapLibre Native FFI released 0.202610.3 on 2026-10-28. The package pins 0.202610.2. The release has many breaking changes to the C API, so each later FFI update that we skip makes the next update larger. The release also shares parsed glyphs among the maps of one runtime and adds events that a follow-up change uses.

## What Changes

- Update the FFI pin to release 0.202610.3 (tag `v0.202610.3`, commit `6c065d9613438bea56ad67d706c4893df14a2b32`), with the xcframework URL and checksum, the Android runtime AAR version and the committed FFI notices.
- Port the native code to the 0.202610.3 C API: the shared C++ core, the Metal glue, the Android glue and the native tests. The port keeps the package's behavior. The changes include renamed functions, types and constants, zeroed option structs in place of the removed `*_default()` functions, map creation that returns the map through `out_map`, `mln_render_session_dispose` in place of `mln_render_session_release`, frame result draining that returns its view, and the new log callback signature.
- Keep two behaviors that the new C API changes without a compile error: frame demands that must render unconditionally set `MLN_FRAME_DEMAND_FORCE`, because a zero flag set now renders only when the map changed; and map creation sets the `MLN_MAP_OPTION_EVENT_MASK` field bit, because without it the map queues every event type.
- On Android, the FFI now sends HTTP requests through the platform's `HttpURLConnection`, which applies the application's network security configuration. Android blocks cleartext HTTP by default, so a map on Android can no longer load an `http://` URL unless the application allows cleartext traffic to that host. **BREAKING** for applications that load `http://` URLs on Android. The test harness gets a network security configuration that allows cleartext traffic to `127.0.0.1` only, for the tests that serve resources from a local HTTP server. The package doesn't change what an application allows. The package README, `docs/limitations.md` and the CHANGELOG state the new behavior.
- The FFI's Android build no longer contains the Kotlin TLS helper and the patched rustls-platform-verifier (maplibre/maplibre-native-ffi#1184), so release 0.202610.3 has no `kotlin.txt`, `kotlin-notice.txt` and `rustls-platform-verifier-notice.txt`, and the package drops their license entries. The `third-party-notices` spec and the package's tests named each notice file, so this removal needed changes to the spec, the script, the Dart code and three tests. The package now takes the set of notice files from the release: the script copies every notice file that the release's tarballs contain, the package lists the notice files that the application's build contains, and the spec and the tests require that every notice file of the release is provided, without naming the files. A later FFI release that adds or removes a notice file then needs no change to the spec, the code or the tests.
- Compare the change with `main` on the Mac in the frame-rate benchmark and the alignment benchmark, and record the results in `docs/benchmarks.md`. We then decide whether to run the benchmarks on the iPhones and the Pixel.

Not in this change: reporting glyph and sprite load failures from the FFI's new map events in place of the log callback. That is a separate follow-up change.

## Capabilities

### New Capabilities

### Modified Capabilities
- `map-layer`: a new requirement states that on Android the map's HTTP requests follow the application's network security configuration, and that a request the configuration blocks is reported as a load failure.
- `third-party-notices`: the requirements "Native notices in the license registry" and "Notices equal to the FFI build" require an entry for every notice file of the release that applies to the platform, in place of tables of named files, and state that a notice file the release adds or removes needs no change to the package's code or tests.

## Impact

- `packages/flutter_mapigrade/maplibre_ffi.lock`, and the remote binary target in `packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift`, which `scripts/update_ffi_pins.sh` writes.
- `packages/flutter_mapigrade/notices/`, which `scripts/copy_ffi_notices.sh` writes: three Android notice files are removed, and `notices/android/rust.md` lists 21 Rust crates in place of 78.
- The notices code and tests: `scripts/copy_ffi_notices.sh`, `lib/src/notices/third_party_notices.dart`, the `dartPluginClass` entries in the package's `pubspec.yaml`, `test/notices/third_party_notices_test.dart`, `test/notices/ffi_notices_test.dart`, and `packages/test_harness/integration_test/notices_test.dart`.
- Native code: `packages/flutter_mapigrade/src/core/` (`map_texture.cpp`, `map_texture.h`, `map_texture_api.cpp`), `android/src/main/cpp/map_texture_android.cpp`, `darwin/.../MapTextureMetal.mm`, and `test/native/`.
- `packages/test_harness/android/`: the network security configuration and its manifest entry.
- `packages/test_harness/integration_test/resource_test.dart`: a test for a blocked cleartext request on Android.
- Documentation: `packages/flutter_mapigrade/README.md`, `packages/flutter_mapigrade/CHANGELOG.md`, `docs/limitations.md`, `docs/benchmarks.md`, `CONTRIBUTING.md` (the pinned release), and `docs/packaging.md` where it names the FFI release.
- The update also includes every other FFI change since release 0.202610.2, including MapLibre Native commits `254d0a8..36132b0`, none of which touches the MapLibre defects documented in `docs/upstream-fixes/`.
