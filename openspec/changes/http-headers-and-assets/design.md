## Context

Each `MapTexture` owns one MapLibre runtime, which `MapTexture::Init` creates on the map's own thread (`src/core/map_texture.cpp`). `Init` sets `cache_path` and `event_mask` on the runtime options, and nothing else. `map_texture_create` waits until `Init` has finished, and returns a handle, or `MAP_TEXTURE_ERROR_CREATE_FAILED` without a message. `MapTextureLayer` turns a failed create into a `LayerCreateException`.

MapLibre Native FFI provides what this change needs:

- `mln_runtime_options.asset_path` sets the root directory of `asset://` URLs. `AssetFileSource` appends the percent-decoded rest of the URL to it. On Android, paths under `/android_asset/` read the APK's `assets/` directory with `AAssetManager`, which the FFI can do because `mln_android_init` already receives the application context.
- `mln_runtime_set_http_header_transform` registers a callback that MapLibre calls synchronously on a worker or network thread for each HTTP request. `callback_adapter.h` provides an implementation of that callback, `mln_adapter_http_header_transform_callback`, that reads a native rule table, so no Dart code runs on a MapLibre thread. The rule table holds borrowed pointers that must stay valid while the transform is registered.
- `mln_adapter_http_header_validate` checks one header against the FFI's rules (field-name syntax, UTF-8, control bytes, and a list of 15 header names that MapLibre or the platform HTTP client manages) without a runtime. On failure, `mln_thread_last_error_message()` on the same thread names the header and doesn't contain its value.
- The PMTiles source fetches its inner URL through the main resource loader, with byte ranges, so `pmtiles://asset://...` reads ranges of an asset file.

## Goals / Non-Goals

**Goals:**

- No Dart code runs on a MapLibre thread, and the layer adds no per-request work outside native code.
- One copy of the FFI's header rules: the managed header names aren't duplicated in Dart.

**Non-Goals:**

- Changing headers on a map that exists (the specs fix the rules at creation).
- A resource provider for custom URL schemes, or Dart code that serves requests.
- URL rewrite rules.
- Headers for requests that the ambient cache serves without contacting the server.
- Add-to-app hosts whose Flutter assets aren't in the main bundle's `App.framework` (see Risks).

## Decisions

### D80. `HttpHeaderRule` and the `httpHeaders` parameter

```dart
final class HttpHeaderRule {
  HttpHeaderRule({required this.url, required this.headers});
  final String url;                    // glob, see the class doc
  final Map<String, String> headers;
}

// MapigradeLayer and MapTextureLayer:
final List<HttpHeaderRule> httpHeaders;   // default const []
```

`HttpHeaderRule` defines `==` and `hashCode`, like the exception classes. Its documentation states the glob syntax from the `map-layer` spec, that the first matching rule supplies all its headers, and that the URL is compared after tile URL templates are filled in. `httpHeaders` documents that the layer reads it when it creates its map, and that a later change has no effect.

The constructor isn't `const`, so that its assert can check each header (D82).

The name follows the naming rule of `package-api`. It doesn't start with `Layer`, as `LayerAlignment` does, because a rule describes HTTP requests and not the layer.

Alternatives:
- `Map<String, String> httpHeaders` applied to every request. Rejected: it sends the access key to every host in the style, including glyph and sprite hosts of third parties.
- A rule with a list of URL patterns. Rejected: the FFI rule has one pattern, and an application can repeat a rule with each pattern.

### D81. The rules cross FFI as a flat string array

`map_texture_create` gets three more parameters:

```c
int64_t map_texture_create(double pixel_ratio, int32_t copy_free,
                           map_texture_event_callback callback,
                           const char* const* header_strings,
                           const int32_t* header_counts, int32_t rule_count,
                           char** out_error);
```

`header_strings` holds, for each rule in order, the URL followed by `header_counts[i]` name and value pairs. `MapTextureController.create` allocates the array with an `Arena` and frees it after the call returns. `map_texture_create` copies the strings, so the array is borrowed only for the call.

`MapTexture` keeps the copies in `std::string` members, and builds from them the `mln_adapter_http_header` arrays, the `mln_adapter_http_header_transform_rule` array, and the `mln_adapter_http_header_transform_rules` table. Every rule uses `MLN_ADAPTER_RESOURCE_KIND_ANY` and `MLN_ADAPTER_URL_MATCH_GLOB`. These members are declared so that they are destroyed after the runtime, because `mln_runtime_destroy` waits for in-flight transform callbacks, and the table must stay valid until then. The vectors aren't resized after the table points into them.

When `rule_count` is 0, `Init` doesn't register a transform.

Alternatives:
- A JSON string decoded in C++. Rejected: it adds a JSON parser to the native code, for a fixed shape.
- A separate `map_texture_set_http_headers` command after create. Rejected: the transform must be registered on the map thread before the style loads, and a command would race with the style URL that the layer sends right after create.

### D82. Header validation: syntax in Dart, full check in native code

The `HttpHeaderRule` constructor asserts, for each header, that the name is a non-empty RFC 9110 token, and that the value contains no control character other than horizontal tab. This catches most mistakes at the call site in debug builds.

`map_texture_create` calls `mln_adapter_http_header_validate` for each header on the calling thread, before it starts the map thread. On the first failure it returns `MAP_TEXTURE_ERROR_INVALID_ARGUMENT`, and sets `*out_error` to a copy of `mln_thread_last_error_message()`, allocated with `malloc`. Dart reads and frees it with a new `map_texture_string_free`, and throws `MapTextureException` with it, which `MapTextureLayer` reports as a `LayerCreateException`. The FFI's message names the header and doesn't contain its value.

`out_error` is also set when `MapTexture::Create` fails for another reason, with the message that `Init` reported, so that a `LayerCreateException` states its cause in general.

Alternatives:
- Copying the 15 managed header names into Dart, so that the assert catches everything. Rejected: two lists that the FFI can change independently.
- Calling `mln_adapter_http_header_validate` from the Dart assert through FFI. Rejected: the constructor then needs the native library, and plugin unit tests that build a layer run without it.

### D83. The asset root is Flutter's asset directory

A new function `std::string PlatformAssetPath()`, declared next to `PlatformCachePath()` in `render_target.h`, returns:

- Android: `/android_asset/flutter_assets`, a constant.
- macOS and iOS: the `resourcePath` of the bundle at `<main bundle>/<privateFrameworksPath>/App.framework`, followed by `/flutter_assets`. `resourcePath` is the framework's root directory on iOS and its `Resources` directory on macOS, so one expression covers both. When the framework bundle doesn't exist, it returns an empty string.

`Init` sets `runtime_options.asset_path` to it. An empty string leaves MapLibre's default, so `asset://` URLs fail to load instead of reading a wrong directory.

`asset://` requests are served before the ambient cache, so assets aren't copied into the cache, and the header transform doesn't apply to them.

Alternatives:
- `FlutterPluginRegistrar lookupKeyForAsset:`. Rejected: macOS has no equivalent, and it returns a path per key, but MapLibre needs one root.
- An application-supplied asset root. Rejected: we decided the root isn't configurable.

### D84. Tests

- Dart unit tests (`test/layer/`): `HttpHeaderRule` equality and asserts; `MapTextureLayer` passes `httpHeaders` to its controller factory once, and a rebuild with different rules doesn't call it again; the API test lists `HttpHeaderRule`.
- Native unit tests (`test/native/`): `fake_mln.cpp` gains `mln_runtime_set_http_header_transform`, `mln_adapter_http_header_validate` and `mln_adapter_http_header_transform_callback`, and records the registered rules. Tests check that `map_texture_create` copies the rules (the caller's strings are overwritten after the call), registers them in `Init`, registers nothing for zero rules, and returns `MAP_TEXTURE_ERROR_INVALID_ARGUMENT` with a message for a rejected header.
- Integration test in the test harness (`integration_test/resource_test.dart`), run on macOS, iOS and Android:
  - A `dart:io` `HttpServer` on the loopback address serves a style and tiles from two path prefixes, and records the headers of each request. The rules add a header for one prefix only. The test checks which requests carry it, including the first-match order.
  - A style and a small PMTiles file bundled as harness assets: one test loads `asset://` for the style, and one loads a style whose source is `pmtiles://asset://...`, and checks that a pixel at a known coordinate has the source's color.
  - A missing asset reports a `LayerLoadException`.
- The test harness's Android build excludes `pmtiles` from compression (`androidResources { noCompress += "pmtiles" }`), as the README tells applications to.

## Risks / Trade-offs

- [The Android build compresses `.pmtiles` assets by default: the Flutter Gradle plugin sets no `noCompress` rule. `AAsset_seek64` on a compressed entry decompresses from the start of the entry, so each range read of a large file takes time in proportion to its offset.] → The README states that Android applications must add `noCompress += "pmtiles"`. A small file in the test harness doesn't show the cost, so the integration test doesn't measure it.
- [Add-to-app: a host app that loads Flutter from a framework other than the main bundle's `App.framework` has its assets elsewhere.] → `PlatformAssetPath()` returns an empty string and `asset://` URLs fail with a load failure. The README states the limitation.
- [Header rules are fixed at creation, and a rebuild with different rules has no effect without an error.] → The parameter documentation states it. An application that needs new rules gives the layer a new key.
- [The ambient cache serves a tile from a request that carried the access key to a later request without the server checking the key again.] → This is how MapLibre caches for every platform SDK, and the key protects the server, not the tile data on the device.
- [Loopback HTTP in the integration test: iOS App Transport Security and Android cleartext rules can block `http://127.0.0.1`.] → The task that adds the test checks this on each platform first, and adds the narrowest exception to the test harness only, if one is needed.

## Migration Plan

No migration: the parameter is optional, and a layer without it sends the same requests as before. `asset://` URLs failed before this change, so no application depends on their old behavior.

## Open Questions

None.
