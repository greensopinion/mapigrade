# flutter_mapigrade

Displays a [MapLibre Native](https://github.com/maplibre/maplibre-native) map as the base layer of a [`flutter_map`](https://pub.dev/packages/flutter_map) map. MapLibre renders the map on the GPU on its own thread, and Flutter displays it in a `Texture` widget, so the layers that `flutter_map` draws above it, such as markers and polylines, are ordinary Flutter widgets.

## Usage

Place a `MapigradeLayer` first among the children of a `FlutterMap`, so that the layers after it are drawn above it:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

FlutterMap(
  options: const MapOptions(
    initialCenter: LatLng(49.25, -123.1),
    initialZoom: 11,
  ),
  children: [
    MapigradeLayer(
      styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
      onError: (exception) => debugPrint('$exception'),
    ),
    MarkerLayer(
      markers: [
        Marker(
          point: const LatLng(49.25, -123.1),
          child: const Icon(Icons.place),
        ),
      ],
    ),
  ],
)
```

Give the style as a URL with `styleUrl`, or as MapLibre style JSON with `styleJson`. The layer follows the `FlutterMap` camera. `flutter_map` handles gestures as usual.

To change the style, for example when the platform switches between light and dark mode, rebuild the layer with a different `styleUrl` or `styleJson`. The layer loads the new style into the map it has, and calls `onStyleLoaded` each time a style has loaded.

The example in `example/` shows a map with a marker.

## Supported platforms

| Platform | Minimum version | Architecture |
| --- | --- | --- |
| Android | API level 29 (Android 10) | arm64 |
| iOS | 15.5 | arm64 (devices, and the simulator on Apple-silicon Macs) |
| macOS | 14.3 | arm64 |

On iOS and macOS the plugin supports Swift Package Manager only; it has no podspec. An Android app must limit its ABIs to `arm64-v8a` and set `minSdk = 29`.

## Alignment with the overlays

The map renders on its own thread, so while the camera moves, the displayed map can trail the overlays by a frame or two. `alignment` selects how the layer reduces this:

- `LayerAlignment.prediction()` (the default) sets the map camera to the `FlutterMap` camera extrapolated one display refresh interval ahead from its recent velocity. In steady pans the map trails the overlays by up to about one frame of movement, and it runs ahead of them briefly after an abrupt stop or reversal. `LayerAlignment.prediction(lead: n)` extrapolates n refresh intervals ahead.
- `LayerAlignment.none` sets the current camera. The map trails the overlays by about two frames of movement in steady pans.

At rest, both align the map with the overlays within 1 logical pixel.

## Failures

The layer doesn't throw failures of its map into your code. It calls `onError` with a `LayerException`:

- `LayerLoadException`: the style, or a resource it needs, failed to load. MapLibre retries a request that fails to connect; the layer reports a failure with the same message once until the style changes.
- `LayerRenderException`: rendering failed.
- `LayerCreateException`: the map couldn't be created. The layer then occupies the viewport without drawing anything, and the layers after it are still drawn.

When `onError` is null, the layer reports the failure through `FlutterError.reportError`, with `flutter_mapigrade` as the library. Later versions may add subclasses of `LayerException`, so handle other types when you switch over the type.

## Limitations

- The API covers the style and the alignment. There is no API for style layers, sources, queries or pitch.
- arm64 only on every platform.
- One Flutter engine per process.
- The density of the style's sprites and glyphs is fixed when the map is created. After a change of the device pixel ratio, the map renders at the new ratio, but the sprites keep the original density.
- Camera prediction was measured only on 120 Hz displays.

The measured findings and the other limitations are in [docs/limitations.md](https://github.com/greensopinion/mapigrade/blob/main/docs/limitations.md) in the repository.
