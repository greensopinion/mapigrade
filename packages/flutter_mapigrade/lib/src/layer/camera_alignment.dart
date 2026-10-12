// The layer's alignment option (design D43 of the camera-prediction-default
// change).

enum _Kind { prediction, transform, none }

/// How `MapLibreTextureLayer` keeps the map aligned with the `FlutterMap`
/// overlays while the camera changes. At rest every value aligns the map
/// with the overlays within 1 logical pixel.
///
/// The figures below were measured at 1,000 logical px/s on the 120 Hz
/// reference Mac and iPhone (`benchmarks.md`, "Alignment with camera
/// prediction").
final class CameraAlignment {
  /// Sets the map camera to the `FlutterMap` camera extrapolated from its
  /// recent velocity by [lead] display refresh intervals, and draws the map
  /// without a transform. The default, with a lead of 1.
  ///
  /// With a lead of 1, the map trails the overlays in steady pans by up to
  /// about one frame of movement (0.5 to 0.95 frames on average), and runs
  /// ahead of them briefly after an abrupt stop or reversal. No strips are
  /// uncovered at the viewport edges. The camera at rest isn't extrapolated.
  const CameraAlignment.prediction({double this.lead = 1})
    : assert(lead > 0, 'the lead must be greater than 0'),
      _kind = _Kind.prediction;

  const CameraAlignment._(this._kind) : lead = null;

  /// Draws the last displayed map frame with a transform that moves it to
  /// where the current camera places it. The map is about one frame of
  /// movement ahead of the overlays in steady pans, and the viewport edges
  /// show uncovered strips about two frames of movement wide.
  static const transform = CameraAlignment._(_Kind.transform);

  /// Neither prediction nor the transform: the map trails the overlays by
  /// about two frames of movement in steady pans. No strips are uncovered.
  static const none = CameraAlignment._(_Kind.none);

  final _Kind _kind;

  /// The lead in display refresh intervals for [CameraAlignment.prediction],
  /// otherwise null.
  final double? lead;

  /// Whether this is [transform].
  bool get isTransform => _kind == _Kind.transform;

  @override
  bool operator ==(Object other) =>
      other is CameraAlignment && other._kind == _kind && other.lead == lead;

  @override
  int get hashCode => Object.hash(_kind, lead);

  @override
  String toString() => switch (_kind) {
    _Kind.prediction => 'CameraAlignment.prediction(lead: $lead)',
    _Kind.transform => 'CameraAlignment.transform',
    _Kind.none => 'CameraAlignment.none',
  };
}
