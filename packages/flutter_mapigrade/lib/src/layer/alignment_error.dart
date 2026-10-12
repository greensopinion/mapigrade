// Alignment error of one Flutter frame (design D26 of the flutter-map-layer
// change, D49 of the remove-camera-transform change).
import 'dart:math' as math;
import 'dart:ui';

import 'camera_projection.dart';

/// How far the displayed map is from the overlays in one Flutter frame, in
/// logical pixels: the largest distance, over the viewport corners and
/// center, between where the overlays draw a coordinate and where the map, as
/// the layer draws it, draws it.
class AlignmentError {
  const AlignmentError({required this.error, this.center = Offset.zero});

  /// The largest distance over the viewport corners and center.
  final double error;

  /// Where the map draws the coordinate that the overlays draw at the
  /// viewport center, relative to the center.
  final Offset center;

  @override
  String toString() => 'AlignmentError($error, center: $center)';
}

/// The alignment error of a Flutter frame whose overlays use [target] (C_N)
/// and in which Flutter displayed the frame [shown] (k_shown).
AlignmentError alignmentError({
  required ViewCamera target,
  required ViewCamera shown,
}) {
  final stretch = Offset(
    target.viewport.width / shown.viewport.width,
    target.viewport.height / shown.viewport.height,
  );
  final size = target.viewport;
  var error = 0.0;
  var centerOffset = Offset.zero;
  final center = size.center(Offset.zero);
  for (final q in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
    center,
  ]) {
    final g = worldPosition(target, q);
    // Where the texture widget draws g: the frame's own position, stretched
    // to the widget's size.
    final p = screenPosition(shown, g);
    final drawn = Offset(p.dx * stretch.dx, p.dy * stretch.dy);
    error = math.max(error, (drawn - q).distance);
    if (q == center) centerOffset = drawn - q;
  }
  return AlignmentError(error: error, center: centerOffset);
}
