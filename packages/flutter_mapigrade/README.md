<p align="center">
  <img src="https://raw.githubusercontent.com/greensopinion/mapigrade/main/assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# flutter_mapigrade

Displays a [MapLibre Native](https://github.com/maplibre/maplibre-native) map as the base layer of a [`flutter_map`](https://pub.dev/packages/flutter_map) map. MapLibre renders on its own thread into a Flutter `Texture`, so the `flutter_map` layers above it are ordinary widgets.

## Usage

Place a `MapigradeLayer` first among the children of a `FlutterMap`:

```dart
FlutterMap(
  options: const MapOptions(initialCenter: LatLng(49.25, -123.1)),
  children: [
    MapigradeLayer(styleUrl: 'https://tiles.openfreemap.org/styles/liberty'),
    MarkerLayer(markers: [
      Marker(point: const LatLng(49.25, -123.1), child: const Icon(Icons.place)),
    ]),
  ],
)
```

Give `styleUrl` or `styleJson`. To change the style, rebuild the layer with a different one.

## Supported platforms

| Platform | Minimum version | Architecture |
| --- | --- | --- |
| Android | API level 29 | arm64 |
| iOS | 15.5 | arm64 |
| macOS | 14.3 | arm64 |

iOS and macOS support Swift Package Manager only.

The native library is built for arm64. On Android, an app that also runs on other ABIs, such as `armeabi-v7a` or `x86_64`, starts there without the native library. `MapigradeLayer.isSupported` is then false; read it and place another layer when it is false:

```dart
FlutterMap(
  options: const MapOptions(initialCenter: LatLng(49.25, -123.1)),
  children: [
    if (MapigradeLayer.isSupported)
      MapigradeLayer(styleUrl: 'https://tiles.openfreemap.org/styles/liberty')
    else
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.app',
      ),
  ],
)
```

A `MapigradeLayer` placed without the native library reports a `LayerCreateException` to `onError` and draws nothing.

An app that wants no fallback limits its ABIs to `arm64-v8a` in its own app module, so that Google Play offers it only to devices with an arm64 ABI. In `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        ndk {
            abiFilters += "arm64-v8a"
        }
    }
}
```

## Options

- `alignment`: while the camera moves, the default `LayerAlignment.prediction()` keeps the map within about one frame of the overlays; `LayerAlignment.none` within about two.
- `onError`: receives each `LayerException`; when null, failures go to `FlutterError.reportError`.
- `MapigradeLayer.maximumCacheSizeBytes`: the tile cache's maximum size, 50 MiB by default, for maps created afterwards. Each map evicts from the shared cache file to its own maximum size; after a reduction, the cache reaches the new maximum size as the map stores new tiles. Freshness follows the server's cache headers.

## HTTP headers

To send an access key or other headers to a tile server, give `httpHeaders` a list of `HttpHeaderRule`s:

```dart
MapigradeLayer(
  styleUrl: 'https://tiles.example.com/style.json',
  httpHeaders: [
    HttpHeaderRule(
      url: 'https://tiles.example.com/**',
      headers: {'X-Access-Key': 'my-key'},
    ),
  ],
)
```

Each HTTP request that the map sends gets the headers of the first rule whose `url` matches the request's complete URL, and no headers when no rule matches. A request to a host that no rule names, such as a third-party glyph server, doesn't get the access key.

`url` is a glob, compared with the URL byte for byte and case-sensitively, after tile URL templates are filled in:

- `*` matches any characters except `/`, so `https://*.example.com/**` matches `https://a.example.com/x` but not `https://attacker.example/x.example.com/x`.
- `**` matches any characters.
- `?` matches one character except `/`.
- `\` makes the next character literal.

The layer reads `httpHeaders` when it creates its map. Rebuilding the layer with different rules has no effect; to change them, give the layer a new `key`.

MapLibre or the platform HTTP client manages these headers, and a rule can't set them: `Accept-Encoding`, `Connection`, `Content-Length`, `Host`, `If-Modified-Since`, `If-None-Match`, `Keep-Alive`, `Proxy-Authorization`, `Proxy-Connection`, `Range`, `TE`, `Trailer`, `Transfer-Encoding`, `Upgrade` and `User-Agent`. A rule with one of them, an invalid header name, or a value with a control character other than horizontal tab makes the layer report a `LayerCreateException`, whose message names the header and doesn't contain its value. In debug builds, the `HttpHeaderRule` constructor also asserts on an invalid name or a control character.

Requests that the map serves from its cache or from assets don't get the headers.

## Flutter assets

`asset://<asset key>` loads the Flutter asset with that key, in the style URL and in every URL in a style:

```dart
MapigradeLayer(styleUrl: 'asset://assets/style.json')
```

An asset of a package `foo` has the key `packages/foo/<path>`, for example `asset://packages/foo/assets/style.json`. A PMTiles file bundled as an asset has the source URL `pmtiles://asset://assets/tiles.pmtiles`.

MapLibre reads a PMTiles file in byte ranges. On Android, a compressed asset is decompressed from its start for each range, so exclude PMTiles files from compression in `android/app/build.gradle.kts`:

```kotlin
android {
    androidResources {
        noCompress += "pmtiles"
    }
}
```

MBTiles files can't be loaded from assets, because MapLibre opens them only from an absolute file path.

On iOS and macOS, the layer reads assets from the main bundle's `App.framework`. In an add-to-app host that loads Flutter from another framework, `asset://` URLs fail with a `LayerLoadException`.

## Limitations

- No API for style layers, sources, queries or pitch.
- One Flutter engine per process.
- Sprite and glyph density is fixed when the map is created.
- Camera prediction was measured only on 120 Hz displays.

More in [docs/limitations.md](https://github.com/greensopinion/mapigrade/blob/main/docs/limitations.md).
