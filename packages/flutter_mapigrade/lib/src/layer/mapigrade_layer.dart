// The public layer (design D66 of the public-api change).
import 'package:flutter/widgets.dart';

import '../texture/map_texture_controller.dart';
import 'layer_alignment.dart';
import 'layer_exception.dart';
import 'map_texture_layer.dart';

/// Displays a MapLibre map as the base layer of a `FlutterMap`. Place it first
/// among the map's children, and give exactly one of [styleUrl] and
/// [styleJson].
final class MapigradeLayer extends StatelessWidget {
  /// A layer that displays [styleUrl] or [styleJson].
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
  /// set; 50 MiB by default. Each map evicts from the shared cache file to its
  /// own maximum size. A negative value throws an [ArgumentError].
  static int get maximumCacheSizeBytes => _maximumCacheSizeBytes;

  static set maximumCacheSizeBytes(int bytes) {
    MapTextureController.setMaximumCacheSize(bytes);
    _maximumCacheSizeBytes = bytes;
  }

  static int _maximumCacheSizeBytes = 50 * 1024 * 1024;

  /// The URL of the style.
  final String? styleUrl;

  /// The style as MapLibre style JSON.
  final String? styleJson;

  /// How the layer aligns the map with the overlays while the camera moves.
  final LayerAlignment alignment;

  /// Called each time a style has loaded.
  final VoidCallback? onStyleLoaded;

  /// Called with each failure of the map; when null, failures go to
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
