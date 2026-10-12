// The layer's alignment option (design D43 of the camera-prediction-default
// change, D47 of the remove-camera-transform change).

enum _Kind { prediction, none }

/// How `MapLibreTextureLayer` keeps the map aligned with the `FlutterMap`
/// overlays while the camera changes. At rest every value aligns the map
/// with the overlays within 1 logical pixel. The layer draws the map without
/// a transform in both cases.
///
/// The figures below were measured at 1,000 logical px/s on the 120 Hz
/// reference Mac and iPhone (`docs/benchmarks.md`, "Alignment with camera
/// prediction").
final class CameraAlignment {
  /// Sets the map camera to the `FlutterMap` camera extrapolated from its
  /// recent velocity by [lead] display refresh intervals. The default, with a
  /// lead of 1.
  ///
  /// With a lead of 1, the map trails the overlays in steady pans by up to
  /// about one frame of movement (0.5 to 0.95 frames on average), and runs
  /// ahead of them briefly after an abrupt stop or reversal. No strips are
  /// uncovered at the viewport edges. The camera at rest isn't extrapolated.
  const CameraAlignment.prediction({double this.lead = 1})
    : assert(lead > 0, 'the lead must be greater than 0'),
      _kind = _Kind.prediction;

  const CameraAlignment._(this._kind) : lead = null;

  /// No prediction: the map trails the overlays by about two frames of
  /// movement in steady pans. No strips are uncovered.
  static const none = CameraAlignment._(_Kind.none);

  final _Kind _kind;

  /// The lead in display refresh intervals for [CameraAlignment.prediction],
  /// otherwise null.
  final double? lead;

  @override
  bool operator ==(Object other) =>
      other is CameraAlignment && other._kind == _kind && other.lead == lead;

  @override
  int get hashCode => Object.hash(_kind, lead);

  @override
  String toString() => switch (_kind) {
    _Kind.prediction => 'CameraAlignment.prediction(lead: $lead)',
    _Kind.none => 'CameraAlignment.none',
  };
}
