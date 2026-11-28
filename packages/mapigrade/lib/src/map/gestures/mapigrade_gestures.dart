import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// Which gestures move the camera of a `MapigradeMap`. Every part is on by
/// default. A part that is off doesn't move the camera, and its input goes to
/// other gesture recognizers. Rebuilding the map with other gestures applies
/// them from the next input.
@immutable
final class MapigradeGestures {
  /// Gestures with the given parts on or off.
  const MapigradeGestures({
    this.pan = true,
    this.zoom = true,
    this.rotate = true,
    this.pitch = true,
    this.glides = true,
    this.doubleTapZoom = true,
    this.twoFingerTapZoom = true,
    this.snapToNorth = true,
    this.keyboard = true,
  });

  /// No gesture moves the camera.
  const MapigradeGestures.none()
    : pan = false,
      zoom = false,
      rotate = false,
      pitch = false,
      glides = false,
      doubleTapZoom = false,
      twoFingerTapZoom = false,
      snapToNorth = false,
      keyboard = false;

  /// Whether one or two fingers, a trackpad scroll and a mouse drag pan.
  final bool pan;

  /// Whether a pinch, a trackpad pinch, a mouse wheel and a box zoom zoom.
  final bool zoom;

  /// Whether a twist, a trackpad rotation and a right-drag turn the bearing.
  final bool rotate;

  /// Whether two fingers moving up or down together and a right-drag change
  /// the pitch.
  final bool pitch;

  /// Whether a release that is fast enough glides on.
  final bool glides;

  /// Whether a double tap zooms in by a level. While it is on, `onTap` waits
  /// until a second tap is ruled out.
  final bool doubleTapZoom;

  /// Whether a two-finger tap zooms out by a level.
  final bool twoFingerTapZoom;

  /// Whether a bearing within 7 degrees of north when a gesture ends eases
  /// to north.
  final bool snapToNorth;

  /// Whether the arrow keys, `+` and `-` move the camera while the map has
  /// keyboard focus.
  final bool keyboard;

  /// A copy with the given parts replaced.
  MapigradeGestures copyWith({
    bool? pan,
    bool? zoom,
    bool? rotate,
    bool? pitch,
    bool? glides,
    bool? doubleTapZoom,
    bool? twoFingerTapZoom,
    bool? snapToNorth,
    bool? keyboard,
  }) => MapigradeGestures(
    pan: pan ?? this.pan,
    zoom: zoom ?? this.zoom,
    rotate: rotate ?? this.rotate,
    pitch: pitch ?? this.pitch,
    glides: glides ?? this.glides,
    doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
    twoFingerTapZoom: twoFingerTapZoom ?? this.twoFingerTapZoom,
    snapToNorth: snapToNorth ?? this.snapToNorth,
    keyboard: keyboard ?? this.keyboard,
  );

  @override
  bool operator ==(Object other) =>
      other is MapigradeGestures &&
      other.pan == pan &&
      other.zoom == zoom &&
      other.rotate == rotate &&
      other.pitch == pitch &&
      other.glides == glides &&
      other.doubleTapZoom == doubleTapZoom &&
      other.twoFingerTapZoom == twoFingerTapZoom &&
      other.snapToNorth == snapToNorth &&
      other.keyboard == keyboard;

  @override
  int get hashCode => Object.hash(
    pan,
    zoom,
    rotate,
    pitch,
    glides,
    doubleTapZoom,
    twoFingerTapZoom,
    snapToNorth,
    keyboard,
  );
}

/// A tap, long press or secondary tap on a `MapigradeMap`.
@immutable
final class MapigradeTap {
  /// A tap at [position] over [coordinate].
  const MapigradeTap({required this.position, required this.coordinate});

  /// The logical position relative to the map's top-left corner, the
  /// coordinate space of `MapigradeController.queryRenderedFeatures`.
  final Offset position;

  /// The coordinate at [position] on the ground plane of the frame that was
  /// displayed when the tap happened, or null above the horizon or before the
  /// first displayed frame.
  final LatLng? coordinate;

  @override
  String toString() => 'MapigradeTap($position, $coordinate)';
}
