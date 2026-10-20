# Mapigrade and flutter_map_maplibre: what makes Mapigrade worth exploring further

Written on 2026-10-11, and revised on 2026-10-19 with the results of a manual test on an iPhone and an Android phone. This document compares Mapigrade with flutter_map_maplibre 0.0.5 and the `maplibre` 0.3.6 package that it uses, and lists where Mapigrade could improve one of two things:

- **Customer experience:** what the people who use an application with a map see and feel, for example dropped frames, visual effects and correct placement.
- **Developer experience:** what the people who build that application can do and how much work it takes, for example screenshots, golden tests and platform-specific workarounds.

The comparison is between two ways of embedding a map: in a platform view, as the `maplibre` package does, or in a Flutter texture, as Mapigrade does. The results therefore apply to the `maplibre` package in general, not only to its `flutter_map` layer.

We assume a release-ready Mapigrade. Without it, flutter_map_maplibre is the better choice: it is published, and it supports the web.

Neither `flutter_map` option exposes the runtime API of the `maplibre` package: sources and style layers that the application adds or changes while the map runs, feature queries, and pitch. `MapigradeLayer` and `MapLibreLayer` take the style when the map is created, and `MapLibreLayer` doesn't pass the `maplibre` controller to the application. `flutter_map`'s camera has no pitch, so a map that `flutter_map` controls is always flat. An application that needs these APIs uses `MapLibreMap` from the `maplibre` package directly, without `flutter_map`. This document doesn't compare Mapigrade with that use.

## Summary

With the default configuration, the platform view showed these defects:

- **iOS:** an image captured with `RepaintBoundary.toImage` doesn't contain the map, and `ColorFiltered` and `ShaderMask` have no effect on the map. Overlays move relative to the map during pans (they float), but so little that it is almost imperceptible.
- **Android:** overlays float clearly over the map during pans. Capture, effects and placement in a scroll view work.

The other Android configurations that the `maplibre` package offers add defects: in `hc` with a `SurfaceView`, capture and every effect we tested fail, and in `tlhc_hc` with a `SurfaceView` the map is drawn out of place and over Flutter's widgets. The package's source says that its default, MapLibre's texture mode, "comes at a significant performance penalty". How large that cost is, and so whether applications have a reason to switch from the Android default, is the main open question (Frame rate of the Flutter UI around the map).

## How each one embeds the map

| | Mapigrade | flutter_map_maplibre |
| --- | --- | --- |
| Native map | MapLibre Native through MapLibre Native FFI, one pinned commit for all platforms | MapLibre Native Android 13.5 and iOS 6.29 SDKs, called through JNI and Dart FFI bindings |
| iOS | `Texture` widget | Platform view: `UiKitView` holding an `MLNMapView` |
| Android | `Texture` widget | Platform view. Default mode `tlhc_vd` (Texture Layer Hybrid Composition, falling back to virtual display) with `androidTextureMode: true`, which makes MapLibre render into a `TextureView` |
| `flutter_map` layer | `MapigradeLayer`: Dart knows the camera of each displayed map frame, and the layer draws its children at that camera | `MapLibreLayer`: calls `moveCamera` on every `flutter_map` move event. It doesn't pass the Android mode options, so it always uses the defaults, and it doesn't pass the `maplibre` controller or style layer options |

## How we tested

We built a test app with flutter_map_maplibre, [greensopinion/platform_view_defects](https://github.com/greensopinion/platform_view_defects), and ran a manual test with it on 2026-10-19, with Flutter 3.47.7, in release builds:

- iPhone 15, iOS 26.7.1. iOS has one configuration.
- Pixel 4a (5G), Android 14, in three configurations: the Android default (`tlhc_vd` with texture mode), `tlhc_hc` with `androidTextureMode: false`, and `hc` with `androidTextureMode: false`. With `androidTextureMode: false`, MapLibre renders into a `SurfaceView`. To set these options, the app used a copy of `MapLibreLayer` that passes them to `MapLibreMap`.

The app shows a `flutter_map` map over London with three markers, which are Flutter widgets, on three pages:

- **Share:** a button calls `toImage` on a `RepaintBoundary` around the map and a card, and shows the image.
- **Effects:** switches turn on a blurred sheet over the map (`BackdropFilter`), a grayscale `ColorFiltered`, `Opacity` 0.5 and a fade (`ShaderMask`) on the map, with stripes behind the map. The markers show each effect, so the test is whether the map tiles show it too.
- **Scroll:** the map is the eleventh of 33 cards in a `ListView`, which scrolls under a translucent app bar. We scrolled it across the screen and off it, flung it and overscrolled at both ends.

The repository contains the app, the test script (`TEST_SCRIPT.md`) and the results we recorded, as of commit `b499fdf`. Anyone can repeat the test with it on other devices and Flutter versions.

## Defects observed with a platform view

| | iPhone | Android default (`tlhc_vd`, texture) | Android `tlhc_hc`, `SurfaceView` | Android `hc`, `SurfaceView` |
| --- | --- | --- | --- | --- |
| Overlays stay on the map during pans | almost: they float slightly | no: they float | not judged: the configuration is unusable | no: they float |
| Map in a `toImage` capture | no | yes | no | no |
| Blur over the map | yes | yes | no | no |
| Grayscale and fade on the map | no | yes | no | no |
| Opacity on the map | yes | yes | no | no |
| Placement and clipping in a scroll view | correct | correct | wrong, and the map covers Flutter's widgets | correct |

### Overlays float during camera changes

During pans, the markers floated over the map tiles: clearly on the Pixel in both configurations where we could judge it, and almost imperceptibly on the iPhone. It looked like the displayed map frame lagged the `flutter_map` camera by several frames on Android, and by less on the iPhone.

The platform view causes it, not one layer's code. `MapLibreLayer` sets the native camera on every move event, and the native view renders and composites its frame on its own schedule. Flutter has no information about which camera the displayed frame was rendered at, so no layer can draw the overlays at that camera. Mapigrade's layer can, because the plugin reports each texture frame together with its camera: with the overlays as `MapigradeLayer` children, the alignment benchmark found no Flutter frame with an error over 1 logical px on the Mac and the iPhone, and on the Pixel the overlays stayed on the map in a manual check (`benchmarks.md`, `docs/camera-alignment-options.md`). On the Pixel this lowers the frame rate: Mapigrade displays about 53 map frames per second (`limitations.md`).

This is the reason with the most evidence. It occurs with the default configuration on both platforms, and customers see it as markers, routes and labels that float over the map: clearly on Android, and almost imperceptibly on iOS.

Improves: customer experience. Status: observed for flutter_map_maplibre in the manual test; measured for Mapigrade on macOS and iOS, observed in a manual check on Android.

### Capturing the screen

On iOS the captured image contained the markers and the card, but not the map. This matches Flutter's source: `UiKitView` adds a `PlatformViewLayer`, which the native view is composited into after Flutter rasterizes its frame. The Android default captured the map, because the map is in a `TextureLayer`, the same layer as a `Texture` widget. Neither `SurfaceView` configuration captured it.

An application that lets customers share an image of the map, for example a forecast with the map and its overlays, gets an image without the map on iOS. To make the feature work, the application must take a native snapshot of the map and composite it with the overlays itself, at the same camera and size. On-device golden tests of map screens have the same problem. Host golden tests (`flutter test` on a computer) show neither a platform view nor a `Texture`, so Mapigrade doesn't help there. `toImage` captures Mapigrade's map: the iPhone color measurement (`packages/test_harness/integration_test/color_measurement.dart`) depends on it.

Improves: customer experience (shared images) and developer experience (on-device golden tests). Status: observed on iOS and Android.

### Effects on and over the map

On iOS, the blurred sheet blurred the map and `Opacity` made it translucent, but `ColorFiltered` and `ShaderMask` left the map tiles unchanged while they changed the markers. With the Android default, all four effects worked. In both `SurfaceView` configurations, none of them affected the map. With Mapigrade, all four effects worked on the map; we didn't keep that test.

A texture is part of Flutter's scene, so Flutter applies these effects to it like to any other widget. For applications whose value is the data drawn on the map, effects such as a dark or grayscale tint, a fade while the style loads, or blending data drawn by Flutter (such as weather layers) with the map are a capability, not only a difference in appearance. On iOS, a platform view can't provide the tint or the fade.

Flutter's Android documentation states that Hybrid Composition++ (HCPP) "does not currently support BackdropFilter or ImageFilter effects applied to or over platform views". HCPP needs Android 14 or later, Impeller and Vulkan, and we didn't test it. On the Pixel, Flutter tried Vulkan and then used OpenGL ES (`benchmarks.md`), so it can't run HCPP. We also didn't test `ImageFilter.shader`.

Improves: customer experience, through effects that a platform view can't show, and developer experience, through effects that work the same on every platform. Status: observed for flutter_map_maplibre and for Mapigrade.

### Placement in scroll views

Placement and clipping were correct on the iPhone, in the Android default and in `hc` with a `SurfaceView`. In `tlhc_hc` with a `SurfaceView` the map was drawn out of place and over Flutter's widgets, so the configuration is unusable. This is the defect that Flutter's documentation describes for Texture Layer Hybrid Composition: a `SurfaceView` "will be drawn at the wrong location and/or z-index". The `maplibre` documentation says that this configuration falls back to hybrid composition; the results show that it didn't, because with hybrid composition placement was correct. We didn't check why.

This defect only affects an application that switches from the Android default, so it isn't a reason on its own. If the Android default is too slow, the only other configuration that an application can switch to is `hc` with a `SurfaceView`, which has the capture and effect defects above.

Status: observed on Android.

## Frame rate of the Flutter UI around the map

Mapigrade is unlikely to render the map itself faster than a native view. `MLNMapView` renders into its own Metal layer on its own display link. Mapigrade does the same rendering and then either copies the frame into the buffer Flutter displays or, with copy-free rendering, renders directly into that buffer. Over central London the iPhone 15 Pro Max displays about 100 map frames per second with the copy and about 110 copy-free (`benchmarks.md`).

The frame rate that may differ is that of the Flutter UI around the map:

- On iOS, Flutter composites each Flutter widget that overlaps a platform view in an extra overlay layer.
- On Android, the Android default avoided the capture, effect and placement defects above. The `maplibre` source has a TODO that MapLibre's texture mode, which the Android default uses, "comes at a significant performance penalty" (`maplibre_android/lib/src/map_state.dart`). The alternative that keeps placement correct, `hc` with a `SurfaceView`, uses hybrid composition, which composites Flutter's frames on the platform thread. Flutter's documentation says that this "can significantly impact Flutter's performance", and the configuration loses capture and effects.

A texture adds no composition work to the widgets above it. If platform views cause dropped Flutter frames while overlays are animating above the map, customers see it as stutter in the application's UI. On Android, the result also shows how much the defects of the other configurations matter: if the Android default is fast enough, applications have no reason to switch.

Mapigrade has its own cost on Android: drawing children at the camera of the displayed frame lowers the displayed map frame rate on the Pixel from about 58 to about 53 frames per second (`limitations.md`).

Improves: customer experience. Status: plausible, not measured.

## Who Mapigrade is for

The defects in this document matter most to an application that draws its own data over the map as `flutter_map` layers, for example a weather application that draws forecasts, radar and routes over a base map. For that application, overlays float over the map, a shared image doesn't contain the map, and a tint or fade leaves the map unchanged. We therefore position Mapigrade as the base map layer for `flutter_map` applications, not as an alternative to the `maplibre` package. An application that needs runtime sources and style layers, feature queries or pitch uses the `maplibre` package.

For that audience, the most important missing API is the position of data in the style. A `flutter_map` overlay is drawn above the whole map, labels included, so radar data drawn as an overlay covers the place labels. With a style layer, MapLibre draws the data under the labels. Neither `flutter_map` option supports this. Mapigrade could add it for `flutter_map` applications, for example with an API that adds a source and a style layer at a position in the style.

## Durability

None of the reasons above depends on something that only Mapigrade can have. They depend on rendering the map into a Flutter texture instead of a platform view, and, for the alignment of overlays, on knowing the camera of each displayed frame. The `maplibre` package could do the same. It already calls its SDKs through Dart FFI and JNI, and MapLibre Native FFI is a MapLibre project. In its issue tracker we found no plan to move to textures or to MapLibre Native FFI (searched on 2026-10-11).

We left out one candidate reason because the `maplibre` package can match it directly: one pinned MapLibre Native build on every platform, instead of two SDKs whose versions, defects and exposed features differ. The package could get this by switching both platforms to MapLibre Native FFI. It would then still choose between a platform view, which keeps the defects above, and a texture, which is Mapigrade's design.

What Mapigrade has that a switch to textures doesn't give automatically is the work we did and measured in this repository: the map thread and display pacing, rendering ahead on the iPhone, the iOS lifecycle handling, the workaround for Flutter's texture cache (`docs/flutter-texture-cache-followup.md`), and the display slots that align `flutter_map` overlays with the displayed map frame. Whether to keep Mapigrade separate or offer it as a texture backend for the `maplibre` package is therefore a decision to make after the remaining tests, not an assumption.

## What would not justify further work

- A higher map frame rate alone: Frame rate of the Flutter UI around the map explains why we don't expect it.
- One MapLibre build on every platform alone: see Durability.
- Properties of the design, for example "composites like any other widget", unless they cause defects that customers or developers would see, as in Defects observed with a platform view.

## Remaining tests

1. Flutter frame times with several animated Flutter overlays above the map, with flutter_map_maplibre in the Android default and in `hc` with a `SurfaceView`, on iOS, and with Mapigrade. This decides the frame-rate reason, and whether the defects of the other Android configurations matter.
2. HCPP and `ImageFilter.shader`, on a device that runs Impeller with Vulkan.

## Other findings

- In release builds on Android, R8 code shrinking breaks `maplibre_android` 0.3.6: creating the map view fails with a `NullPointerException`, and the map stays gray. A keep rule for the plugin's Kotlin classes didn't fix it; turning off shrinking did. This affects every application that ships the package, not only platform-view behavior.
- On the iPhone, after the map was scrolled off the top of the screen and back, the map tiles didn't fill the bottom of the map view, which showed a gray strip; the labels were complete. This looks like a defect of `MLNMapView` or the plugin, not of platform views, so it isn't counted above.

## Sources

- [flutter_map_maplibre documentation](https://pub.dev/documentation/flutter_map_maplibre/latest/) and source ([josxha/flutter_map_plugins](https://github.com/josxha/flutter_map_plugins))
- [maplibre documentation](https://pub.dev/documentation/maplibre/latest/) and source ([josxha/flutter-maplibre](https://github.com/josxha/flutter-maplibre))
- [Flutter: Android platform views](https://github.com/flutter/flutter/blob/main/docs/platforms/android/Android-Platform-Views.md)
- The test app and its recorded results: [greensopinion/platform_view_defects](https://github.com/greensopinion/platform_view_defects)
- Flutter's platform view render objects: `packages/flutter/lib/src/rendering/platform_view.dart`
