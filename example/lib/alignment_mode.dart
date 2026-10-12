// Layer configurations for the alignment benchmark and the flutter_map page
// (design D34 of the camera-prediction change, D45 of the
// camera-prediction-default change): the compensating transform, neither
// transform nor prediction, or camera prediction with a lead of 1, 2 or 3
// refresh intervals.
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

enum AlignmentMode {
  transform('transform', CameraAlignment.transform),
  none('none', CameraAlignment.none),
  predict1('predict1', CameraAlignment.prediction(lead: 1)),
  predict2('predict2', CameraAlignment.prediction(lead: 2)),
  predict3('predict3', CameraAlignment.prediction(lead: 3));

  const AlignmentMode(this.label, this.alignment);

  /// The name in result lines and in `--dart-define=ALIGNMENT_MODE=`.
  final String label;

  /// The layer's alignment in this mode.
  final CameraAlignment alignment;

  /// The mode named [label], or null if there is none.
  static AlignmentMode? byLabel(String label) {
    for (final mode in values) {
      if (mode.label == label) return mode;
    }
    return null;
  }
}
