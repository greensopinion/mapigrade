// Alignment error of one Flutter frame (design D26).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show MatrixUtils;

import 'camera_transform.dart';

/// How far the displayed map is from the overlays in one Flutter frame, in
/// logical pixels: the largest distance, over the viewport corners and
/// center, between where the overlays draw a coordinate and where the map
/// draws it.
class AlignmentError {
  const AlignmentError({
    required this.withTransform,
    required this.withoutTransform,
  });

  /// With the transform the layer applied (the last-reported-frame transform,
  /// design D23).
  final double withTransform;

  /// If the layer had drawn the texture without a transform.
  final double withoutTransform;

  @override
  String toString() =>
      'AlignmentError(with: $withTransform, without: $withoutTransform)';
}

/// The alignment error of a Flutter frame whose overlays use [target] (C_N),
/// whose layer built its transform from the frame [used] (k_used, or null if
/// no frame had been displayed), and in which
/// Flutter displayed the frame [shown] (k_shown).
AlignmentError alignmentError({
  required ViewCamera target,
  required ViewCamera? used,
  required ViewCamera shown,
}) {
  final transform = used == null ? null : layerTransform(used, target);
  final stretch = Offset(
    target.viewport.width / shown.viewport.width,
    target.viewport.height / shown.viewport.height,
  );
  final size = target.viewport;
  var withT = 0.0, withoutT = 0.0;
  for (final q in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
    size.center(Offset.zero),
  ]) {
    final g = worldPosition(target, q);
    // Where the texture widget draws g: the frame's own position, stretched
    // to the widget's size.
    final p = screenPosition(shown, g);
    final drawn = Offset(p.dx * stretch.dx, p.dy * stretch.dy);
    withoutT = math.max(withoutT, (drawn - q).distance);
    final moved = transform == null
        ? drawn
        : MatrixUtils.transformPoint(transform, drawn);
    withT = math.max(withT, (moved - q).distance);
  }
  return AlignmentError(withTransform: withT, withoutTransform: withoutT);
}
