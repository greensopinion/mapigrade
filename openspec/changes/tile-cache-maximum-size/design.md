## Context

See proposal.md for motivation and scope, and specs/map-texture/spec.md for the requirement. The in-flight change `android-texture-vertical-slice` uses decisions up to D60; decisions here are numbered from D61.

Current state, as checked in this repository and in the MapLibre Native FFI and MapLibre Native sources under `third_party/` on 2026-10-12:

- `MapTexture::Init()` (`src/core/map_texture.cpp`) runs on the map thread, which becomes the runtime's owner thread. It creates the runtime with `cache_path` from `PlatformCachePath()` and `event_mask = MLN_RUNTIME_EVENT_MASK_NONE`, then creates the map. The style is loaded later, by a command from Dart (`map_texture_load_style_url` or `_json`).
- Each map creates its own runtime. The FFI gives each runtime its own platform context, and MapLibre's `FileSourceManager` includes the platform context in the key under which it shares file sources. Each runtime therefore has its own `DatabaseFileSource`: its own database thread and its own SQLite connection to the shared cache file. MapLibre sets an unlimited SQLite busy timeout, so two maps that write to the file at the same time wait for each other and don't fail.
- `OfflineDatabase` holds the maximum ambient cache size in memory, per connection. It is not stored in the database. Each connection starts with `ResourceOptions::maximumCacheSize()`, which the FFI leaves at `DEFAULT_MAX_CACHE_SIZE` (50 MiB), and evicts ambient resources (least recently used first) when a write would exceed it. `mln_runtime_options` has no size field.
- `mln_runtime_set_maximum_ambient_cache_size_start(runtime, size, &operation_id)` must be called on the owner thread. It queues `DatabaseFileSource::setMaximumAmbientCacheSize` on that runtime's database thread. The new limit takes effect when the database thread runs it, and lowering the limit evicts at once. Completion is reported through `MLN_RUNTIME_EVENT_OFFLINE_OPERATION_COMPLETED`. `mln_runtime_offline_operation_discard()` drops the stored result and suppresses the completion event.
- The database thread is a single MapLibre actor: it runs the messages queued to it in order. Resource requests and the writes of downloaded resources reach the same database thread.
- `MapTexture::ReportStatus()` emits a `MAP_TEXTURE_EVENT_RENDER_ERROR` event, which Dart receives as `RenderError`.
- `src/core/map_texture_api.cpp` already holds process-wide state guarded by `registry_mutex` (the registry of live maps and `all_paused`).

## Goals / Non-Goals

**Goals:**
- A size set before a map is created is in effect on that map's connection before the first cached resource is read, stored or evicted.
- Maps behave exactly as today when Dart sets no size.

**Non-Goals:**
- Reporting the cache's current size to Dart.
- Observing the asynchronous result of the size operation.
- Coordinating the limits of maps with different sizes that share the file (see Risks).

## Decisions

### D61. One process-wide value, read when a map is created

`map_texture_api.cpp` stores the value as an `int64_t`, with -1 meaning that Dart has not set one, guarded by `registry_mutex`. A new exported function sets it:

```c
// Sets the maximum size in bytes of the tile cache for maps created after the
// call. Returns 0, or MAP_TEXTURE_ERROR_INVALID_ARGUMENT for a negative size.
MAP_TEXTURE_EXPORT int32_t map_texture_set_maximum_cache_size(int64_t bytes);
```

`map_texture_create` reads the value under the lock and passes it to the `MapTexture` constructor with the pixel ratio and `copy_free`, as an `std::optional<uint64_t>`. The map keeps that value for its lifetime, so a later call doesn't change it.

*Alternatives:*
- A parameter of `map_texture_create` and `MapTextureController.create`. Maps that share the cache file would then commonly get different limits, and each connection evicts to its own limit (see Risks). A process-wide value makes the common case, one limit for the application, the only easy one.
- A setting that also changes live maps. This needs a command to each map thread. The user decided on 2026-10-12 that the value applies only to maps created after the call.

### D62. `Init()` starts the size operation right after it creates the runtime

When the map has a value, `Init()` calls `mln_runtime_set_maximum_ambient_cache_size_start()` right after `mln_runtime_create()` succeeds, before it creates the map, and then calls `mln_runtime_offline_operation_discard()` with the returned operation id. The style load comes later, from a command that the map thread applies after `Init()` returns. Because the database thread runs its messages in order, the size change runs before the first resource request and before the first write of a downloaded resource. Nothing is evicted under the 50 MiB default first.

The size operation and the map's resource loader use the same `DatabaseFileSource`. The first operation creates it (the FFI's `database_source_for_runtime`, `src/runtime/runtime.cpp`) and the runtime keeps a reference to it. The map's resource loader requests a database file source from `FileSourceManager` with the same resource options, `resource_options_for_runtime(runtime)` (`src/map/map.cpp` and MapLibre's `main_resource_loader.cpp`), so it gets the same instance.

When no value has been set, `Init()` doesn't call the function, so the default stays MapLibre's.

*Alternatives:*
- Enable `MLN_RUNTIME_EVENT_OFFLINE_OPERATION_COMPLETED` and report an asynchronous failure. It would add event handling to the pump for a failure that only a broken database causes, and such a database fails tile loads in other ways that are already reported. Discarding keeps runtime events masked.
- Start the operation after the map is created. That also works, because the style isn't loaded yet, but starting before `mln_map_create` doesn't depend on the map creating no requests.

### D63. A start failure is reported as a render error, and the map continues

If `mln_runtime_set_maximum_ambient_cache_size_start()` returns a status other than `MLN_STATUS_OK`, `Init()` calls `ReportStatus()`, which Dart receives as `RenderError`, and continues. The map then uses the 50 MiB default. `Init()` doesn't fail, because the map can render without the limit.

### D64. Dart: a static function that validates its argument

```dart
/// Sets the maximum size in bytes of the tile cache for maps created after
/// this call, in the whole process. ...
static void setMaximumCacheSize(int bytes)
```

It throws `ArgumentError` for a negative `bytes` without calling native code, and throws `MapTextureException` if the native function returns an error. It is declared on `MapTextureController`, next to `create`, so that applications find it where they create maps. The documentation states the default (50 MiB), that 0 keeps no cache, that maps created before the call keep their limit, and that maps that share the file each evict to their own limit.

*Alternatives:*
- A top-level function or a separate `TileCache` class. Neither has any other members, so a static function on the class that creates maps is easier to find.

## Risks / Trade-offs

- [Two maps created with different limits share one file, and each connection evicts to its own limit. The smaller limit wins whenever that map writes.] → D61 makes one application-wide value the common case; the Dart documentation states the behaviour.
- [A later FFI or MapLibre version creates separate database file sources for the size operation and the resource loader, and the limit no longer applies to the connection that stores tiles.] → The check that more than 50 MiB stays in the cache across a restart (tasks.md, section 4) shows it.
- [An asynchronous failure of the size operation isn't reported.] → The map uses the 50 MiB default, which is today's behaviour.
- [A limit of 0 means every downloaded resource is evicted when the next is written, so the map downloads tiles again after each pan back.] → This is the meaning of 0; the documentation states it.

## Migration Plan

None. The change adds API, and applications that don't call it behave as before.
