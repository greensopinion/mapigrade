// The public layer (design D66 of the public-api change).
import 'package:flutter/widgets.dart';

import '../texture/map_texture_controller.dart';
import 'layer_alignment.dart';
import 'layer_exception.dart';
import 'map_texture_layer.dart';

/// Displays a MapLibre map as the base layer of a `FlutterMap`, at the
/// `FlutterMap` camera. Place it first among the map's children, so that the
/// layers after it are drawn above it.
///
/// Give exactly one of [styleUrl] and [styleJson]. The layer creates its map
/// when it is inserted and disposes it when it is removed. When the layer is
/// rebuilt with a different style, it loads the new style into the map it
/// has.
///
/// By default the layer sets the map camera predicted one display refresh
/// interval ahead while the camera moves, so that the map displayed then is
/// close to the overlays; [alignment] selects how the layer aligns the map
/// with the overlays during camera changes.
///
/// The layer reports a failure of its map to [onError], and doesn't throw it.
final class MapigradeLayer extends StatelessWidget {
  /// A layer that displays the style at [styleUrl] or the style [styleJson].
  const MapigradeLayer({
    super.key,
    this.styleUrl,
    this.styleJson,
    this.alignment = const LayerAlignment.prediction(),
    this.onStyleLoaded,
    this.onError,
  }) : assert(
         (styleUrl == null) != (styleJson == null),
         'give exactly one of styleUrl and styleJson',
       );

  /// The maximum size in bytes of the tile cache for maps created after it is
  /// set, in the whole process (design D64 of the tile-cache-maximum-size
  /// change).
  ///
  /// MapLibre keeps downloaded tiles, styles, glyphs and sprites in a cache
  /// file on the device and evicts the least recently used resources when the
  /// cache would exceed this maximum size. Until a value is set, the maximum
  /// size is MapLibre's default of 50 MiB (52,428,800 bytes), and the getter
  /// returns that value. With 0 the cache keeps no resources, so the map
  /// downloads tiles again each time it displays them.
  ///
  /// Set the maximum size before the first layer creates its map. Maps that
  /// were created before a set keep the maximum size they were created with.
  /// Maps share the cache file, and each map evicts to its own maximum size:
  /// of maps created with different maximum sizes, the one with the smaller
  /// maximum size evicts resources down to it each time it stores a resource.
  ///
  /// Setting a negative value throws an [ArgumentError] and leaves the maximum
  /// size unchanged. If a map fails to apply the maximum size, it uses 50 MiB
  /// and reports a [LayerRenderException] to [onError].
  static int get maximumCacheSizeBytes => _maximumCacheSizeBytes;

  static set maximumCacheSizeBytes(int bytes) {
    MapTextureController.setMaximumCacheSize(bytes);
    _maximumCacheSizeBytes = bytes;
  }

  static int _maximumCacheSizeBytes = 50 * 1024 * 1024;

  /// The URL of the style, for example
  /// `https://tiles.openfreemap.org/styles/liberty`.
  final String? styleUrl;

  /// The style as JSON, in the MapLibre style format.
  final String? styleJson;

  /// How the layer aligns the map with the overlays while the camera
  /// changes; see [LayerAlignment]. Defaults to camera prediction with a
  /// lead of 1 display refresh interval.
  final LayerAlignment alignment;

  /// Called each time a style has loaded, including after the layer is
  /// rebuilt with a different style.
  final VoidCallback? onStyleLoaded;

  /// Called with each failure of the map: a [LayerLoadException] when the
  /// style or a resource it needs fails to load, a [LayerRenderException]
  /// when rendering fails, and a [LayerCreateException] when the map can't be
  /// created. When null, the layer reports the failure through
  /// [FlutterError.reportError].
  final void Function(LayerException exception)? onError;

  @override
  Widget build(BuildContext context) => MapTextureLayer(
    styleUrl: styleUrl,
    styleJson: styleJson,
    alignment: alignment,
    onStyleLoaded: onStyleLoaded,
    onError: onError,
  );
}
