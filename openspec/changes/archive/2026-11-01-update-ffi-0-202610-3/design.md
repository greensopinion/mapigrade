## Context

The package calls the FFI's C API from four places: the shared C++ core in `packages/flutter_mapigrade/src/core/`, the Metal glue `MapTextureMetal.mm`, the Android glue `map_texture_android.cpp`, and the native tests in `test/native/`. Dart calls only the core's own C API (`map_texture_api.h`), which doesn't change.

We syntax-checked these sources against the headers of both releases on 2026-11-01. Against 0.202610.2 they compile without errors. Against 0.202610.3 the core has 49 errors at about 25 sites, the Android glue 15, the native tests 21, and the Metal glue calls one removed function. Every error is a rename, a removed `*_default()` function or a changed signature. The C API also changed the meaning of some values without a change that the compiler detects (D210, D211).

The core uses no FFI delivery queue: it registers its event and log callbacks without a queue, and it compares FFI enums only by name and passes none of their values to Dart. So the FFI's changes to delivery queues (#1335, #1342, #1350) and the renumbered enums (#1116) need no change beyond recompiling.

## Goals / Non-Goals

**Goals:**
- The package behaves as with FFI 0.202610.2 on macOS, iOS and Android, apart from the Android HTTP behavior in the `map-layer` delta spec.
- The Mac benchmarks show whether the update changes the frame rate, the service call time or the alignment.

**Non-Goals:**
- Using new FFI features: the glyph and sprite events (a follow-up change), graphics devices, the EGL single-context option (#1351), and style expression evaluation.
- Benchmarks on the iPhones and the Pixel. We decide on them after the Mac results.

## Decisions

### D208. The FFI pin moves to release 0.202610.3

FFI release 0.202610.3 (tag `v0.202610.3`, commit `6c065d9`, 2026-10-28) publishes the tarballs of the four presets that the package uses under the same names as 0.202610.2, and `MaplibreNativeC.xcframework.zip`. Maven Central has `maplibre-native-ffi-runtime-opengl-android:0.202610.3`. The update follows `CONTRIBUTING.md`, "Update the FFI", without changes to the scripts.

The FFI's Android library now sends HTTP requests through `HttpURLConnection` and no longer through its Rust TLS stack (#1184). The Android tarball of 0.202610.3 therefore has no `kotlin.txt`, `kotlin-notice.txt` and `rustls-platform-verifier-notice.txt`, which 0.202610.2 added for the Kotlin TLS helper and the patched rustls-platform-verifier (D186), and its `rust.md` lists 21 crates in place of 78. We checked the removal against the binaries on 2026-11-01. The arm64 `libmaplibre-native-c.so` of the 0.202610.2 runtime AAR embedded one dex of 15 KB, the TLS helper, and contained rustls, webpki and ring. The library of 0.202610.3 contains no dex and none of them, and refers to `java/net/HttpURLConnection`. The six crates whose source paths it contains (`image`, `png`, `image-webp`, `zune-jpeg`, `zune-core`, `fdeflate`) are all in the new `rust.md`. The `classes.jar` of both AARs contains only a marker class. D217 removes the need to change code for such a removal.

The change is verified against the release, not a local build. Release 0.202610.3 still has the four configure presets and pins CMake, Ninja, Rust and cargo-about in its `mise.toml`, and `scripts/build_maplibre_ffi.sh` only uses configure presets, so the removal of the build presets (#1264) doesn't affect the script. The script's Android preset has failed since 0.202610.2, because the FFI compiled an Android TLS helper with `kotlinc` and the script used the rustls-platform-verifier AAR that the FFI removed. Release 0.202610.3 removes that TLS helper (#1184), so the Android preset may build again. The change records whether it does, and doesn't fix the script if it doesn't.

*Outcome (task 6.2, 2026-11-01):* the script fails for every preset, because 0.202610.3 moved `.mise/bin/sync-submodules` to `tools/deps/sync-submodules`; for Android it also still calls the removed `sync-rustls-platform-verifier` and builds the verifier's AAR, on which the plugin's Gradle local mode depends. A separate change fixes the local build.

### D209. Zeroed option structs replace the removed default functions

Each `mln_x x = mln_x_default();` becomes `mln_x x{}; x.size = sizeof(x);`, for runtime options, map options, render session attach options, camera updates and camera options, frame demands, GPU synchronization, HTTP header rules, rendered feature query options, GeoJSON source options, and the Metal and OpenGL descriptors. In 0.202610.3 a zero member means the member's default, and the C API marks members without a default as required.

Some 0.202610.2 defaults weren't zero. For each one the port either sets the member, or relies on the 0.202610.3 meaning of zero:
- Extents of 256x256 at scale factor 1 in the Metal and OpenGL descriptors: the glue sets the extent and the physical size, so the default doesn't matter.
- `requested_texture_ring_depth` of 2 in the attach options: the package's targets are borrowed texture rings and surfaces, whose depth comes from the target, so zero is correct.
- The Metal owned texture descriptor's RGBA8 pixel format, used only in the native tests: the tests set the pixel format if zero no longer means RGBA8.
- The header rule's resource kinds, all kinds: in 0.202610.3, zero also selects all kinds, but the port sets `MLN_RESOURCE_KIND_FLAG_ALL` explicitly, as before.
- The frame demand's `MLN_FRAME_DEMAND_IF_NEEDED`: see D210.

Text that the package passes in needs no trailing NUL byte, so the core's `View()` helper is unchanged. Empty text now means absent, so the feature state selector and the rendered feature query set text members only for values that are present, without the removed field bits. A Dart value that is an empty string therefore means absent too. Before, an empty source layer ID or state key selected nothing.

### D210. Unconditional frame demands set `MLN_FRAME_DEMAND_FORCE`

In 0.202610.2, a demand rendered unconditionally unless it set `MLN_FRAME_DEMAND_IF_NEEDED`. The core uses this after a frame that asked for another without a map update, as during a paint transition (`repaint_wanted_`). In 0.202610.3 the flag is removed, a demand without flags renders only when a newer map update exists, and `MLN_FRAME_DEMAND_FORCE` renders unconditionally. `MLN_FRAME_DEMAND_WAIT_FOR_UPDATE` is still valid without `FORCE`, and invalid with it.

The core's demand flags become `repaint_wanted_ ? MLN_FRAME_DEMAND_FORCE : MLN_FRAME_DEMAND_WAIT_FOR_UPDATE`, plus `MLN_FRAME_DEMAND_PRESENT` for a surface target, as before. Removing `IF_NEEDED` without adding `FORCE` would compile, and paint transitions would stop after their first frame. A native test checks that a paint transition renders more than one frame without a camera change.

### D211. Map creation sets the event mask's field bit

`mln_map_options.event_mask` now applies only when `fields` contains `MLN_MAP_OPTION_EVENT_MASK`. Without the bit, the map queues every event type, including a camera event for each camera change. The core sets the bit with its mask of style loaded, loading failed, render error and idle, renamed to the `MLN_RUNTIME_EVENT_FLAG_*` constants.

### D212. Map creation reads the map from `out_map`

`mln_runtime_create_map` writes the map to `out_map` when it accepts the creation, and the completion reports when the map is ready. The core no longer copies the map from the completion's value. It still waits up to 30 s for the completion before it attaches a session, because an attach returns `MLN_STATUS_INVALID_STATE` until the completion reports `MLN_STATUS_OK`. If creation fails after acceptance, the core releases the map, which the FFI requires whether or not creation succeeds.

### D213. Sessions are disposed after their detach or abandon

`mln_render_session_release` is removed. `mln_render_session_dispose(session, completion, diagnostic)` consumes a session in any state. The core keeps its sequence: detach, wait for the detach completion, or abandon if the detach is refused, then dispose with a null completion. For a session whose target a detach or abandon already released, disposal follows the rules of that call, so the core destroys its Metal textures and EGL surfaces at the same points as before. This applies to `DestroySession` and `RecoverLostTarget`.

`mln_render_session_drain_frame_results` now writes the batch's view to a third argument, and `mln_render_frame_batch_get` is removed. Each frame result's `view.camera` is an `mln_camera`, the new output record for complete cameras. The core reads the center, zoom and bearing from it as before.

### D214. The log callback keeps its role with the new signature

The log callback returns `bool` and receives the message as `mln_buffer_view`, which has a NUL byte after its bytes. `OnLogRecord` checks the glyph failure prefix on the view and returns `false`, so that MapLibre's platform logger still writes the record, as the return value 0 did before. Replacing the callback with the FFI's glyph events is the follow-up change.

### D215. The test harness allows cleartext traffic to 127.0.0.1 only

`packages/test_harness/android/app/src/main/res/xml/network_security_config.xml` allows cleartext traffic to the domain `127.0.0.1` and to no other domain, and the harness's manifest names it. The tests in `resource_test.dart` that serve resources from `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` keep their `http://127.0.0.1` URLs. A new test requests `http://localhost:<port>` from the same server, which the configuration blocks, and checks for the load failure and that the server received no request. The test runs only on Android.

The demo and the example load only `https://` and `asset://` URLs, so they get no configuration. The package itself ships none, because a library's manifest entry for `networkSecurityConfig` would replace the application's own when the manifests are merged.

Alternatives:
- HTTPS with a self-signed certificate in the tests: the harness then needs a configuration that trusts the certificate, which is no simpler and doesn't test the blocked case.
- `android:usesCleartextTraffic="true"` in the harness: it allows cleartext traffic to every host, so the harness can't test the blocked case.

### D216. Mac benchmarks against `main`

The method is the one of the 2026-10-22 FFI update (`docs/benchmarks.md`, "The port to the FFI core executor"). `main` at `bbbc764` (FFI 0.202610.2) runs against the change (FFI 0.202610.3), 3 runs of each, alternating, release builds, copy-free, with rendering ahead at its default. The benchmarks are the frame-rate benchmark (30 s pan) and the alignment benchmark with children (`ALIGNMENT_CHILDREN=1`, mode `predict1`, phases `pan100,pan500,pan1000,stop,fling,reverse`). The Mac and its conditions are those of the earlier run: MacBook Pro (M2 Max), window 1600x1000 on the built-in display at 120 Hz, AC power. The results go into a new section of `docs/benchmarks.md`. The user then decides whether the iPhones and the Pixel run them too.

### D217. The notices follow the release's notice files, not a list

Until this change, the script, the Dart code, the spec and three tests each listed the notice files by name, so the removal in D208 failed the script and needed changes in six places. We (user decision, 2026-11-01) make the release the only source of the set of notice files. The FFI generates its Rust notices from the crate graph with cargo-about and lists its C, C++ and other notices in its CMake files, so the release states what its libraries contain. When the set of notice files changes, the diff of `notices/` shows it for review, as the D208 check did.

- `scripts/copy_ffi_notices.sh` copies every notice file of the tarballs of the presets in `maplibre_ffi.lock`, without a table: `LICENSE` to `common/maplibre-native-ffi.txt`, and `licenses/<name>` to `android/<name>` when only Android presets' tarballs contain it, otherwise to `common/<name>`. It replaces `notices/` as a whole, so a notice file that the release removes is removed. It still fails when two tarballs contain a notice file with the same name and different content, because the package can't choose between them; that is a defect of the release, not a change to its set of notice files.
- A notice file that only Apple presets' tarballs contain goes to `common/`, so Android applications list it too. A separate directory for Apple would have to exist before any file is in it, because the package's `pubspec.yaml` names asset directories and a build fails for a directory that doesn't exist. Listing one notice too many on Android is acceptable; listing one too few is not.
- `thirdPartyNotices` lists the notice files from Flutter's asset manifest, the keys under `packages/flutter_mapigrade/notices/`, as the registry reads the entries. The asset entry `notices/android/` with `platforms: [android]` in `pubspec.yaml` already keeps the Android files out of Apple builds, so the Dart code has no list of files and no platform flag. One `dartPluginClass`, `MapigradeNotices`, registers the notices on every platform.
- An entry's package name comes from a table of known file names (for example `rust.md` is "MapLibre Native FFI Rust crates"). A file that the table doesn't contain gets its file name without the extension. The table only supplies names; no test requires it to cover the notice files.
- `ffi_notices_test.dart` also fails for a file in `notices/` that no tarball contains. `third_party_notices_test.dart` checks the entries against the files in `notices/`: one entry per file, with the file's text. The integration test `notices_test.dart` checks the registry against the notice assets of the running build: one entry with the asset's text for each, and on macOS and iOS no asset under `notices/android/`. No test names a notice file.

Alternatives:
- Generate a Dart file or an index of the notice files with the script: a second copy of the set of files, which the asset manifest already provides.
- Keep the lists and update them with each FFI update: an FFI update that changes the set of notice files fails until a developer edits the lists, which is what we want to avoid.

## Risks / Trade-offs

- [A semantic change that the compiler doesn't detect, other than D210 and D211] → The port reads the 0.202610.3 contract of every function the core calls, and the native tests and the integration tests on the Mac and the Android emulator run before the benchmarks.
- [Shared glyphs (#1339) and other renderer changes change frame times] → The Mac benchmarks (D216) measure it. A difference on the Mac decides whether the other devices run too.
- [HTTP on Android behaves differently through `HttpURLConnection`, for example in the headers it adds or in how it reports errors] → `resource_test.dart` runs on the Android emulator: the header rule tests check that the rules' headers arrive, and the load failure tests check that failures are reported with a message.
- [Applications that load `http://` URLs on Android stop loading them] → The CHANGELOG lists the change as breaking, and the package README and `docs/limitations.md` state what the application must configure.
- [The FFI's notice files miss a component that its libraries contain] → The package copies what the release states and can't detect a missing notice. When the set of notice files changes, the diff of `notices/` shows it, and we check the change against the binaries as in D208.
- [The asset manifest of a build doesn't apply the platform filter as expected] → `notices_test.dart` runs on macOS, the iOS simulator and the Android emulator, and fails on Apple platforms if an asset under `notices/android/` is in the build.

## Migration Plan

The package's next release contains the update. Its CHANGELOG states the new FFI version and the Android cleartext HTTP change. To roll back, revert the change, which restores the pin and the code together.
