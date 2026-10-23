enum _Kind { prediction, none }

/// How `MapigradeLayer` aligns the map with the `FlutterMap` overlays while
/// the camera moves. At rest every value aligns them within 1 logical pixel.
final class LayerAlignment {
  /// Extrapolates the `FlutterMap` camera [lead] display refresh intervals
  /// ahead. The default. With a lead of 1, the map trails the overlays by up
  /// to about one frame in steady pans, and runs ahead briefly after an
  /// abrupt stop.
  const LayerAlignment.prediction({double this.lead = 1})
    : assert(lead > 0, 'the lead must be greater than 0'),
      _kind = _Kind.prediction;

  const LayerAlignment._(this._kind) : lead = null;

  /// No prediction: the map trails the overlays by about two frames.
  static const none = LayerAlignment._(_Kind.none);

  final _Kind _kind;

  /// The lead of [LayerAlignment.prediction], otherwise null.
  final double? lead;

  @override
  bool operator ==(Object other) =>
      other is LayerAlignment && other._kind == _kind && other.lead == lead;

  @override
  int get hashCode => Object.hash(_kind, lead);

  @override
  String toString() => switch (_kind) {
    _Kind.prediction => 'LayerAlignment.prediction(lead: $lead)',
    _Kind.none => 'LayerAlignment.none',
  };
}
