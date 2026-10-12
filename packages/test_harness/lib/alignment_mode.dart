// Layer configurations for the alignment benchmark and the flutter_map page
// (design D34 of the camera-prediction change, D45 of the
// camera-prediction-default change, D50 of the remove-camera-transform
// change): no prediction, or camera prediction with a lead of 1, 2 or 3
// refresh intervals.
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

enum AlignmentMode {
  none('none', LayerAlignment.none),
  predict1('predict1', LayerAlignment.prediction(lead: 1)),
  predict2('predict2', LayerAlignment.prediction(lead: 2)),
  predict3('predict3', LayerAlignment.prediction(lead: 3));

  const AlignmentMode(this.label, this.alignment);

  /// The name in result lines and in `--dart-define=ALIGNMENT_MODE=`.
  final String label;

  /// The layer's alignment in this mode.
  final LayerAlignment alignment;

  /// The mode named [label], or null if there is none.
  static AlignmentMode? byLabel(String label) {
    for (final mode in values) {
      if (mode.label == label) return mode;
    }
    return null;
  }
}
