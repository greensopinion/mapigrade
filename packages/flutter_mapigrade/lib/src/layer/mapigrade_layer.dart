// The public layer (design D66 of the public-api change).
import 'package:flutter/widgets.dart';

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
