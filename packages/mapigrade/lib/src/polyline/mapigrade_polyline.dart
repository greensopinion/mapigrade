import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A line through [points] that `MapigradePolylineLayer` draws in the map.
///
/// The properties that `flutter_map`'s `Polyline` also has keep its names,
/// types and defaults. To switch from `Polyline`, change the class name,
/// replace `pattern` with [dashes] and `colorsStop` with [gradientStops], and
/// check each gradient, because [gradientColors] run along the line.
@immutable
final class MapigradePolyline {
  /// In debug builds, asserts that the widths aren't negative; that [dashes]
  /// has an even number of entries, none negative and not all zero; that
  /// [gradientStops] is given only with [gradientColors], has one entry for
  /// each color, and doesn't decrease from 0 to 1; and that [gradientColors]
  /// and [dashes] aren't both given, because MapLibre can't draw a gradient
  /// on a dashed line.
  MapigradePolyline({
    required this.points,
    this.strokeWidth = 1.0,
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.useStrokeWidthInMeter = false,
    this.dashes,
    this.gradientColors,
    this.gradientStops,
  }) {
    assert(strokeWidth >= 0, 'strokeWidth must not be negative');
    assert(borderStrokeWidth >= 0, 'borderStrokeWidth must not be negative');
    assert(_validDashes(dashes), _dashesMessage);
    assert(
      gradientColors == null || dashes == null,
      'gradientColors and dashes must not both be given: MapLibre can not '
      'draw a gradient on a dashed line',
    );
    assert(
      _validGradient(gradientColors, gradientStops),
      'gradientStops must only be given with gradientColors, have one entry '
      'for each color, and not decrease, from 0 to 1',
    );
  }

  /// The coordinates of the line, in order. The line takes the shorter way
  /// around the world between consecutive points. A polyline with fewer than
  /// two points draws nothing.
  final List<LatLng> points;

  /// The width of the line, in logical pixels, or in meters when
  /// [useStrokeWidthInMeter] is true.
  final double strokeWidth;

  /// The color of the line, including its alpha. [gradientColors] replaces it.
  final Color color;

  /// The width of the border on both sides of the line together, in logical
  /// pixels. The border isn't drawn under the line, and it is solid on a
  /// dashed line.
  final double borderStrokeWidth;

  /// The color of the border.
  final Color borderColor;

  /// The caps at the ends of the line.
  final StrokeCap strokeCap;

  /// The joins between the segments of the line.
  final StrokeJoin strokeJoin;

  /// Whether [strokeWidth] is in meters at the latitude of the first point.
  /// The line then scales with the zoom level.
  final bool useStrokeWidthInMeter;

  /// Alternating dash and gap lengths in multiples of the line's width,
  /// starting with a dash, or null for a solid line.
  ///
  /// `flutter_map`'s `StrokePattern.dashed` takes lengths in logical pixels:
  /// divide them by the line's width in logical pixels. A dash of length 0
  /// with a round [strokeCap] draws a dot, in place of
  /// `StrokePattern.dotted`. MapLibre repeats the pattern as given and has no
  /// `PatternFit`, so the pattern isn't scaled to fit the line. It measures
  /// the pattern from the start of the line in each tile, so the pattern
  /// restarts where a line crosses a tile boundary.
  final List<double>? dashes;

  /// The colors of a gradient along the length of the line, from the first
  /// point to the last, or null for a line of [color].
  ///
  /// `flutter_map`'s `Polyline` draws its gradient in a straight screen
  /// direction from the first point to the last. This gradient follows the
  /// line, so a line that turns back changes color along its path.
  final List<Color>? gradientColors;

  /// The position of each of [gradientColors] along the line, from 0 for the
  /// first point to 1 for the last, in place of `Polyline.colorsStop`. Two
  /// equal consecutive stops give a hard edge. When null, the colors are
  /// spaced evenly from 0 to 1.
  final List<double>? gradientStops;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MapigradePolyline &&
          strokeWidth == other.strokeWidth &&
          color == other.color &&
          borderStrokeWidth == other.borderStrokeWidth &&
          borderColor == other.borderColor &&
          strokeCap == other.strokeCap &&
          strokeJoin == other.strokeJoin &&
          useStrokeWidthInMeter == other.useStrokeWidthInMeter &&
          listEquals(dashes, other.dashes) &&
          listEquals(gradientColors, other.gradientColors) &&
          listEquals(gradientStops, other.gradientStops) &&
          (identical(points, other.points) ||
              listEquals(points, other.points)));

  @override
  late final int hashCode = Object.hashAll([
    ...points,
    strokeWidth,
    color,
    borderStrokeWidth,
    borderColor,
    strokeCap,
    strokeJoin,
    useStrokeWidthInMeter,
    ...?dashes,
    ...?gradientColors,
    ...?gradientStops,
  ]);

  @override
  String toString() => 'MapigradePolyline(${points.length} points)';
}

const _dashesMessage =
    'dashes must have an even number of entries, none negative, '
    'and at least one above zero';

bool _validDashes(List<double>? dashes) =>
    dashes == null ||
    (dashes.length.isEven &&
        dashes.every((d) => d >= 0) &&
        dashes.any((d) => d > 0));

bool _validGradient(List<Color>? colors, List<double>? stops) {
  if (colors == null) return stops == null;
  if (colors.isEmpty) return false;
  if (stops == null) return true;
  if (stops.length != colors.length) return false;
  for (var i = 0; i < stops.length; i++) {
    if (!(stops[i] >= 0 && stops[i] <= 1)) return false;
    if (i > 0 && stops[i] < stops[i - 1]) return false;
  }
  return true;
}
