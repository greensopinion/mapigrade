<p align="center">
  <img src="https://raw.githubusercontent.com/greensopinion/mapigrade/main/assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# flutter_mapigrade

Displays a [MapLibre Native](https://github.com/maplibre/maplibre-native) map as the base layer of a [`flutter_map`](https://pub.dev/packages/flutter_map) map. MapLibre renders on its own thread into a Flutter `Texture`, so the `flutter_map` layers above it are ordinary widgets.

## Usage

Place a `MapigradeLayer` first among the children of a `FlutterMap`, and place overlay layers such as markers in the layer's own `children`:

```dart
FlutterMap(
  options: const MapOptions(initialCenter: LatLng(49.25, -123.1)),
  children: [
    MapigradeLayer(
      styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
      children: [
        MarkerLayer(markers: [
          Marker(point: const LatLng(49.25, -123.1), child: const Icon(Icons.place)),
        ]),
      ],
    ),
  ],
)
```

MapLibre renders the map on its own thread, so while the camera moves, for example during a pan or a zoom, the displayed map lags the `flutter_map` camera by one to two frames. Layers placed after `MapigradeLayer` among the `FlutterMap` children are drawn at the live camera, so they move relative to the map while the camera moves. To keep overlay layers such as a `MarkerLayer` or a `PolylineLayer` aligned with the map, place them in the layer's own `children`, as in the example, instead of the `FlutterMap` children.

Place widgets that don't move with the map, such as zoom buttons or a scale bar, among the `FlutterMap` children after the layer. On Android the layer draws its own `children` at the live camera; see `MapigradeLayer.children`.

Give `styleUrl` or `styleJson`. To change the style, rebuild the layer with a different one.

## Supported platforms

| Platform | Minimum version | Architecture |
| --- | --- | --- |
| Android | API level 29 | arm64 |
| iOS | 15.5 | arm64 |
| macOS | 14.3 | arm64 |

iOS and macOS support Swift Package Manager only.

On Android, an app that also runs on other ABIs, such as `armeabi-v7a` or `x86_64`, can read `MapigradeLayer.isSupported` and place another layer when it is false:

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

## HTTP headers

To send an access key or other headers to a tile server, give `httpHeaders` a list of `HttpHeaderRule`s. `HttpHeaderRule` describes how rules match URLs and which headers a rule can't set.

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

## Flutter assets

`asset://<asset key>` refers to a Flutter asset, in the style URL and in every URL in a style. `MapigradeLayer.styleUrl` describes package assets, PMTiles and add-to-app hosts.

```dart
MapigradeLayer(styleUrl: 'asset://assets/style.json')
```

MapLibre reads a PMTiles file in byte ranges. On Android, a compressed asset is decompressed from its start for each range, so exclude PMTiles files from compression in `android/app/build.gradle.kts`:

```kotlin
android {
    androidResources {
        noCompress += "pmtiles"
    }
}
```

## Limitations

- No API for style layers, sources, queries or pitch.
- One Flutter engine per process.
- Sprite and glyph density is fixed when the map is created.

More in [docs/limitations.md](https://github.com/greensopinion/mapigrade/blob/main/docs/limitations.md).
