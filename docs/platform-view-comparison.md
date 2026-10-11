# Mapigrade and flutter_map_maplibre: what makes Mapigrade worth exploring further

Written on 2026-10-11. This document compares Mapigrade with flutter_map_maplibre 0.0.5 and the `maplibre` 0.3.6 package that it uses, and lists where Mapigrade could improve one of two things:

- **Customer experience:** what the people who use an application with a map see and feel, for example dropped frames, visual effects and correct placement.
- **Developer experience:** what the people who build that application can do and how much work it takes, for example screenshots, golden tests and platform-specific workarounds.

Each reason below names which of the two it improves and how much evidence supports it. Little of it is measured yet. The test plan at the end decides which of the reasons hold.

We assume a release-ready Mapigrade that supports Android, and alignment between the map and `flutter_map` overlays during camera changes that is good enough. Without these assumptions, flutter_map_maplibre is ahead: it is published, it exposes the full `maplibre` API (sources, style layers, feature queries, pitch), and it supports Android and the web.

The comparison is between two ways of embedding a map, so the reasons below apply to the `maplibre` package in general, not only to its `flutter_map` layer.

## How each one embeds the map

| | Mapigrade | flutter_map_maplibre |
| --- | --- | --- |
| Native map | MapLibre Native through MapLibre Native FFI, one pinned commit for all platforms | MapLibre Native Android 13.5 and iOS 6.29 SDKs, called through JNI and Dart FFI bindings |
| iOS | `Texture` widget | Platform view: `UiKitView` holding an `MLNMapView` |
| Android | `Texture` widget (planned) | Platform view. Default mode `tlhc_vd` (Texture Layer Hybrid Composition, falling back to virtual display) with `androidTextureMode: true` |
| `flutter_map` layer | `MapLibreTextureLayer`: Dart knows the camera of each displayed frame, and the layer corrects for it | `MapLibreLayer`: calls `moveCamera` on every `flutter_map` move event, with no correction |

## 1. Frame rate of the Flutter UI around the map

Mapigrade is unlikely to render the map itself faster than a native view. `MLNMapView` renders into its own Metal layer on its own display link. Mapigrade does the same rendering and then either copies the frame or, with copy-free rendering, takes about one refresh interval longer per frame on the iPhone (`benchmarks.md`). Over central London the iPhone 15 Pro Max displays about 100 map frames per second.

The frame rate that may differ is that of the Flutter UI around the map:

- On iOS, Flutter composites each Flutter widget that overlaps a platform view in an extra overlay layer.
- On Android, the `maplibre` defaults choose correct placement over performance. Its source has a TODO that MapLibre's texture mode "comes at a significant performance penalty" (`maplibre_android/lib/src/map_state.dart`). The alternative, hybrid composition (`hc`), composites Flutter's frames on the platform thread, which Flutter's documentation says "can significantly impact Flutter's performance".

A texture adds no composition work to the widgets above it. If platform views cause dropped Flutter frames while overlays are animating above the map, customers see it as stutter in the application's UI.

Improves: customer experience. Status: plausible, not measured.

## 2. Defects that occur only with a platform view

Improves: customer experience (shared images, filters and placement) and developer experience (golden tests).

- **Capturing the screen on iOS.** Whether `RepaintBoundary.toImage` can capture a platform view depends on the layer that Flutter's render object adds (`packages/flutter/lib/src/rendering/platform_view.dart`, Flutter 3.47.5):
  - `UiKitView` (iOS) adds a `PlatformViewLayer`, which the native view is composited into after Flutter rasterizes its frame, so `toImage` can't capture it.
  - `AndroidView` adds a `TextureLayer`, the same layer as a `Texture` widget, unless the controller requires view composition. Then it adds a `PlatformViewLayer`. The `maplibre` default, `tlhc_vd`, falls back to virtual display, which is also a texture, so the map is in a `TextureLayer` with either fallback. `tlhc_hc` with `androidTextureMode: false` falls back to hybrid composition (a `PlatformViewLayer`), as does `hc`.

  On iOS, an application that lets customers share an image that includes the map, for example a forecast with the map and its overlays, gets an image without the map. To make the feature work, the application must take a native snapshot of the map and composite it with the overlays itself, at the same camera and size. Golden tests of map screens have the same problem. With the `maplibre` defaults on Android, `toImage` should capture the map, so this is a defect on iOS, and on Android only in the hybrid composition modes. `toImage` captures Mapigrade's map: the iPhone color measurement (`example/integration_test/color_measurement.dart`) depends on this. Status: Mapigrade measured on iOS; for platform views, read from the Flutter source, not tested.
- **Filters over the map.** Flutter's Android documentation states that Hybrid Composition++ (HCPP), the newest Android mode, "does not currently support BackdropFilter or ImageFilter effects applied to or over platform views". That excludes a blurred bottom sheet over the map, and the overscroll stretch. HCPP needs Android 14 or later, Impeller and Vulkan; other devices fall back to the application's chosen mode. Support on iOS may also be limited; we haven't checked which filters work there. Status: documented for HCPP, not tested.
- **Placement in scroll views.** In Texture Layer Hybrid Composition, Flutter's documentation states that a `SurfaceView` "will be drawn at the wrong location and/or z-index". In a scroll view, the map then isn't drawn at the scroll position and isn't clipped when scrolled off-screen. This occurred with Google Maps in the past. The `maplibre` default, texture mode, avoids it at the performance cost in section 1. Status: documented, not tested.

## 3. Effects applied to the map

A texture is part of Flutter's scene, so Flutter can apply effects to the map and not only draw widgets over it:

- `ColorFiltered` and `ShaderMask`, for example a dark or grayscale tint, or a fade while the style loads.
- `ImageFilter.shader` with a fragment shader on Impeller, for example to blend data drawn by Flutter (such as weather layers) with the map.
- `Opacity` and blend modes between the map and the widgets above it.

With a platform view these effects are unavailable or available only on some platforms and modes. For applications whose value is the data drawn on the map, this is a capability, not only a performance difference.

Improves: customer experience, through effects that a platform view can't show, and developer experience, through effects that work the same on every platform. Status: not tested with either.

## Durability

None of the reasons above depends on something that only Mapigrade can have. They depend on rendering the map into a Flutter texture instead of a platform view. The `maplibre` package could do the same. It already calls its SDKs through Dart FFI and JNI, and MapLibre Native FFI is a MapLibre project. In its issue tracker we found no plan to move to textures or to MapLibre Native FFI (searched on 2026-10-11).

We left out one candidate reason because the `maplibre` package can match it directly: one pinned MapLibre Native build on every platform, instead of two SDKs whose versions, defects and exposed features differ. The package could get this by moving both platforms to MapLibre Native FFI. It would then still choose between a platform view, which keeps the defects in sections 1 to 3, and a texture, which is Mapigrade's design.

What Mapigrade has that a move to textures doesn't give automatically is the work this repository did and measured: the map thread and display pacing, rendering ahead on the iPhone, the iOS lifecycle handling, the workaround for Flutter's texture cache (`docs/flutter-texture-cache-followup.md`), and alignment with `flutter_map`. Whether to keep Mapigrade separate or offer it as a texture backend for the `maplibre` package is therefore a decision to make after the test plan, not an assumption.

## What would not justify further work

- A higher map frame rate alone: section 1 explains why we don't expect it.
- One MapLibre build on every platform alone: see Durability.
- Properties of the design, for example "composites like any other widget", unless sections 1 to 3 show that they improve customer or developer experience.

## Test plan

Build one test page in the example app with two variants, Mapigrade and `MapLibreMap`, and run both on an iPhone and an Android device. On Android, run `MapLibreMap` with the default mode and with `androidTextureMode: false`.

1. A map with several animated Flutter overlays, a bottom sheet with a `BackdropFilter`, and a switch that applies `ColorFiltered` to the map. Record Flutter frame times, and record which effects render.
2. `RepaintBoundary.toImage` of the screen. Check whether the map is in the image.
3. The map as an item in a `ListView`, scrolled across the screen and off it. Check placement and clipping.

If test 1 shows dropped Flutter frames with the platform view, or tests 1 to 3 show effects, captures or placement that fail with the platform view, those results show an improvement in customer or developer experience, and we explore Mapigrade further on their basis. If they don't, no reason in this document remains. Mapigrade's Android variant can only be tested once the Android bridge exists; until then, run tests 2 and 3 for Mapigrade on iOS.

## Sources

- [flutter_map_maplibre documentation](https://pub.dev/documentation/flutter_map_maplibre/latest/) and source ([josxha/flutter_map_plugins](https://github.com/josxha/flutter_map_plugins))
- [maplibre documentation](https://pub.dev/documentation/maplibre/latest/) and source ([josxha/flutter-maplibre](https://github.com/josxha/flutter-maplibre))
- [Flutter: Android platform views](https://github.com/flutter/flutter/blob/main/docs/platforms/android/Android-Platform-Views.md)
