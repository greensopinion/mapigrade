import 'package:flutter/foundation.dart';

enum _Kind { belowLabels, belowLayer, top }

/// Where an overlay that the map draws, such as a `MapigradePolylineLayer`,
/// goes among the style's own layers.
@immutable
final class LayerPlacement {
  /// Directly above the last style layer that isn't a `symbol` layer, so that
  /// the overlay is drawn above the style's lines and fills and below its
  /// labels. When a `fill-extrusion` layer, such as 3D buildings, comes
  /// before that place, the overlay is drawn directly below the first one, so
  /// that the buildings are drawn above it. In a style of only `symbol`
  /// layers the overlay is drawn below the first layer, and in a style
  /// without `symbol` layers above all layers. Layers that the package adds
  /// are ignored. This is the default.
  const LayerPlacement.belowLabels() : this._(_Kind.belowLabels, null);

  /// Directly below the style layer with the ID [id]. When the style has no
  /// such layer, the overlay is drawn above all style layers, and the
  /// `MapigradeLayer` reports a `LayerLoadException` that names [id], once
  /// for each style load.
  const LayerPlacement.belowLayer(String id) : this._(_Kind.belowLayer, id);

  /// Above all style layers.
  const LayerPlacement.top() : this._(_Kind.top, null);

  const LayerPlacement._(this._kind, this._belowLayerId);

  final _Kind _kind;
  final String? _belowLayerId;

  @override
  bool operator ==(Object other) =>
      other is LayerPlacement &&
      other._kind == _kind &&
      other._belowLayerId == _belowLayerId;

  @override
  int get hashCode => Object.hash(_kind, _belowLayerId);

  @override
  String toString() => switch (_kind) {
    _Kind.belowLabels => 'LayerPlacement.belowLabels()',
    _Kind.belowLayer => "LayerPlacement.belowLayer('$_belowLayerId')",
    _Kind.top => 'LayerPlacement.top()',
  };
}

/// The `placement_kind` and `below_layer_id` of `map_texture_overlay_set_layers`.
extension LayerPlacementNative on LayerPlacement {
  /// 0 for below the labels, 1 for below a layer, 2 for the top.
  int get kind => _kind.index;

  /// The ID that [LayerPlacement.belowLayer] was given, or null.
  String? get belowLayerId => _belowLayerId;
}
