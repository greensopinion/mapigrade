import 'package:flutter/widgets.dart';

import '../texture/map_texture_controller.dart';
import '../texture/native_library.dart';
import 'http_header_rule.dart';
import 'layer_alignment.dart';
import 'layer_exception.dart';
import 'layer_metrics.dart';
import 'map_texture_layer.dart';

/// Displays a MapLibre map as the base layer of a `FlutterMap`. Place it first
/// among the map's children, and give exactly one of [styleUrl] and
/// [styleJson].
///
/// MapLibre renders the map on its own thread, so while the camera moves, for
/// example during a pan or a zoom, the displayed map lags the `flutter_map`
/// camera by one to two frames. Layers placed after this one among the
/// `FlutterMap` children are drawn at the live camera, so they move relative
/// to the map while the camera moves. To keep overlay layers such as a
/// `MarkerLayer` or a `PolylineLayer` aligned with the map, place them in this
/// layer's own [children] instead of the `FlutterMap` children.
final class MapigradeLayer extends StatelessWidget {
  /// A layer that displays [styleUrl] or [styleJson].
  const MapigradeLayer({
    super.key,
    this.styleUrl,
    this.styleJson,
    this.alignment = const LayerAlignment.prediction(),
    this.httpHeaders = const [],
    this.onStyleLoaded,
    this.onError,
    this.metrics,
    this.children = const [],
  }) : assert(
         (styleUrl == null) != (styleJson == null),
         'give exactly one of styleUrl and styleJson',
       );

  /// Whether the layer can create a map in this process: false when the
  /// package's native library isn't available, for example on an Android
  /// device without an arm64 ABI. When it is false, place another layer, such
  /// as a `TileLayer`, in place of this one; this layer would report a
  /// [LayerCreateException] and draw nothing.
  static bool get isSupported => nativeLibraryAvailable;

  /// The maximum size in bytes of the tile cache for maps created after it is
  /// set; 50 MiB by default. Each map evicts from the shared cache file to its
  /// own maximum size; after a reduction, the cache reaches the new maximum
  /// size as the map stores new tiles. The server's cache headers determine
  /// freshness. A negative value throws an [ArgumentError].
  static int get maximumCacheSizeBytes => _maximumCacheSizeBytes;

  static set maximumCacheSizeBytes(int bytes) {
    MapTextureController.setMaximumCacheSize(bytes);
    _maximumCacheSizeBytes = bytes;
  }

  static int _maximumCacheSizeBytes = 50 * 1024 * 1024;

  /// The URL of the style.
  ///
  /// In this URL and in every URL in the style, `asset://<asset key>` refers
  /// to the Flutter asset with that key. An asset of a package `foo` has the
  /// key `packages/foo/<path>`, for example
  /// `asset://packages/foo/assets/style.json`. A PMTiles file bundled as an
  /// asset has the source URL `pmtiles://asset://assets/tiles.pmtiles`.
  /// MBTiles files can't be loaded from assets, because MapLibre opens them
  /// only from an absolute file path.
  ///
  /// On iOS and macOS, the layer reads assets from the main bundle's
  /// `App.framework`. In an add-to-app host that loads Flutter from another
  /// framework, `asset://` URLs fail with a [LayerLoadException].
  final String? styleUrl;

  /// The style as MapLibre style JSON. URLs in the style can refer to Flutter
  /// assets, as described for [styleUrl].
  final String? styleJson;

  /// How the layer aligns the map with the overlays while the camera moves.
  final LayerAlignment alignment;

  /// HTTP header rules, read when the layer creates its map. To change them,
  /// give the layer a new [key].
  final List<HttpHeaderRule> httpHeaders;

  /// Called each time a style has loaded.
  final VoidCallback? onStyleLoaded;

  /// Called with each failure of the map; when null, the layer passes
  /// failures to [FlutterError.reportError].
  final void Function(LayerException exception)? onError;

  /// Reports the frame counts and render time of the layer's map; see
  /// [LayerMetrics]. Give each layer its own object, and a new object with a
  /// new [key].
  final LayerMetrics? metrics;

  /// Layers drawn above the map, in order, such as a `PolylineLayer` or a
  /// `MarkerLayer`. On macOS and iOS the layer draws them at the camera of
  /// the map frame it displays, so that they stay exactly on the map while
  /// the camera moves; they move with the map, about one to two frames behind
  /// the gesture.
  ///
  /// Place widgets that change the camera, or that read it to decide what to
  /// do, after this layer among the `FlutterMap` children instead, because
  /// the children read the camera of the displayed frame.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MapTextureLayer(
    styleUrl: styleUrl,
    styleJson: styleJson,
    alignment: alignment,
    httpHeaders: httpHeaders,
    onStyleLoaded: onStyleLoaded,
    onError: onError,
    metrics: metrics,
    children: children,
  );
}
