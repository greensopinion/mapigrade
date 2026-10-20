<p align="center">
  <img src="https://raw.githubusercontent.com/greensopinion/mapigrade/main/assets/mapigrade.svg" alt="Mapigrade logo" width="360">
</p>

# flutter_mapigrade

Displays a [MapLibre Native](https://github.com/maplibre/maplibre-native) map as the base layer of a [`flutter_map`](https://pub.dev/packages/flutter_map) map. MapLibre renders the map on its own thread into a Flutter `Texture` widget.

Because the map is part of Flutter's scene, it appears in screen captures and Flutter's effects apply to it. The plugin also keeps `flutter_map` overlays aligned with the displayed map frame, including while the camera moves.

The usual way to show a native map in Flutter is a platform view, which Flutter composites separately from its own widgets. Depending on the platform and configuration, this causes defects:

- Overlays move relative to the map while the camera moves.
- Captures with `RepaintBoundary.toImage` don't contain the map.
- Effects such as `ColorFiltered` and `ShaderMask` leave the map unchanged.

The plugin doesn't use a platform view, so it avoids these defects.

The plugin is experimental: we haven't yet validated it for production use. A recording and a demo app are in the [repository](https://github.com/greensopinion/mapigrade).

## Installation

```sh
flutter pub add flutter_mapigrade
```

On iOS and macOS the plugin supports Swift Package Manager only; it has no podspec.

The package contains no native libraries of MapLibre Native FFI. The first build on a machine downloads them from the FFI release that the package pins, so it needs network access:

- Android: the runtime AAR `org.maplibre.nativeffi:maplibre-native-ffi-runtime-opengl-android` from Maven Central, 34 MB. The `android/build.gradle.kts` that `flutter create` writes includes `mavenCentral()` in the repositories of every project.
- iOS and macOS: `MaplibreNativeC.xcframework.zip` from the FFI's GitHub release, 28 MB. Swift Package Manager checks it against the checksum that the package states.

Gradle and Swift Package Manager cache the downloads for later builds.

### Application settings

An application created with `flutter create` needs these changes before it builds with the package:

- Android: set `minSdk = 29` in `android/app/build.gradle.kts`.
- iOS: set the deployment target to 15.5 (`IPHONEOS_DEPLOYMENT_TARGET` of the Runner target), and exclude `x86_64` from simulator builds, because the FFI's xcframework has no `x86_64` slice. Add this line to `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`:

  ```
  EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64
  ```

  Without it, `flutter build ios --simulator` fails with undefined `mln_` symbols.
- macOS: set the deployment target to 14.3 (`MACOSX_DEPLOYMENT_TARGET` of the Runner target), and build for arm64 only. Add this line to `macos/Runner/Configs/AppInfo.xcconfig`:

  ```
  ARCHS = arm64
  ```

  To load styles and tiles over the network, add the `com.apple.security.network.client` entitlement with the value `true` to `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.

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

Place widgets that don't move with the map, such as zoom buttons or a scale bar, among the `FlutterMap` children after the layer.

Give `styleUrl` or `styleJson`. To change the style, rebuild the layer with a different one.

## Supported platforms

| Platform | Minimum version | Architecture |
| --- | --- | --- |
| Android | API level 29 | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| iOS | 15.5 | arm64 (devices, and the simulator on Apple silicon Macs) |
| macOS | 14.3 | arm64 |

Apps built for web build with the package, compiled to JavaScript or to WebAssembly, but the layer draws no map there: `MapigradeLayer.isSupported` is false, and a placed layer reports a `LayerCreateException`.

On iOS and macOS the plugin supports Swift Package Manager only.

On iOS and macOS, set **Strip Style** to **Non-Global Symbols** for the `Runner` target's Release and Profile configurations. In `ios/Runner.xcodeproj/project.pbxproj` and `macos/Runner.xcodeproj/project.pbxproj` that is:

```
STRIP_STYLE = "non-global";
```

Swift Package Manager links the plugin's native code into the app executable, and Dart looks up its functions in the process. When Xcode archives an app, the default strip style removes every global symbol from the executable, so in an archived build, such as one installed from TestFlight or the App Store, `MapigradeLayer.isSupported` is false and the layer reports a `LayerCreateException`: "the native library of flutter_mapigrade is not available in this process". Debug builds and `flutter run --release` don't strip the executable, so they don't show the failure. To check an archive, run `nm -gU` on the app executable; the output must include `_map_texture_create`.

An app that also runs on web, or on Android devices with other ABIs, such as 32-bit `x86`, can read `MapigradeLayer.isSupported` and place another layer when it is false:

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

To send an access key or other headers to a tile server, give `httpHeaders` a list of `HttpHeaderRule`s. The documentation of `HttpHeaderRule` describes how rules match URLs and which headers a rule can't set.

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

`asset://<asset key>` refers to a Flutter asset, in the style URL and in every URL in a style. The documentation of `MapigradeLayer.styleUrl` describes package assets, PMTiles and add-to-app hosts.

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
- Sprite and glyph density is fixed when the map is created.

More in [docs/limitations.md](https://github.com/greensopinion/mapigrade/blob/main/docs/limitations.md).
