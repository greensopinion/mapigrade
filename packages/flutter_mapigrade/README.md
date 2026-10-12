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

iOS and macOS support Swift Package Manager only. Android apps must limit their ABIs to `arm64-v8a`.

## Options

- `alignment`: while the camera moves, the default `LayerAlignment.prediction()` keeps the map within about one frame of the overlays; `LayerAlignment.none` within about two.
- `onError`: receives each `LayerException`; when null, failures go to `FlutterError.reportError`.
- `MapigradeLayer.maximumCacheSizeBytes`: the tile cache's maximum size, 50 MiB by default, for maps created afterwards. Each map evicts from the shared cache file to its own maximum size. Freshness follows the server's cache headers.

## Limitations

- No API for style layers, sources, queries or pitch.
- One Flutter engine per process.
- Sprite and glyph density is fixed when the map is created.
- Camera prediction was measured only on 120 Hz displays.

More in [docs/limitations.md](https://github.com/greensopinion/mapigrade/blob/main/docs/limitations.md).
