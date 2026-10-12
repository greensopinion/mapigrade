// Layer configurations for the camera-prediction change (designs D31 and
// D34): the compensating transform, neither transform nor prediction, or
// camera prediction with a lead of 1, 2 or 3 refresh intervals.

enum AlignmentMode {
  transform('transform', compensatingTransform: true),
  none('none', compensatingTransform: false),
  predict1('predict1', cameraPrediction: 1),
  predict2('predict2', cameraPrediction: 2),
  predict3('predict3', cameraPrediction: 3);

  const AlignmentMode(
    this.label, {
    this.compensatingTransform = false,
    this.cameraPrediction,
  });

  /// The name in result lines and in `--dart-define=ALIGNMENT_MODE=`.
  final String label;

  /// The values for the layer parameters of the same names.
  final bool compensatingTransform;
  final double? cameraPrediction;

  /// The mode named [label], or null if there is none.
  static AlignmentMode? byLabel(String label) {
    for (final mode in values) {
      if (mode.label == label) return mode;
    }
    return null;
  }
}
