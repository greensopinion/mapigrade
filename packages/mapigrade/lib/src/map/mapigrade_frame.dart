import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../camera_projection.dart';
import '../texture/map_texture_controller.dart';
import 'camera.dart';
import 'mapigrade_camera_controller.dart';

/// The frame that a `MapigradeMap` displays in the current Flutter frame:
/// its camera, its logical size, and conversions between coordinates and
/// logical positions relative to the map's top-left corner (design D241).
///
/// The conversions use the matrix that the frame drew the map with, so they
/// agree with the displayed frame, its pitch included, and don't wait for the
/// map. Read it with [MapigradeFrame.of] in a descendant of the map; that
/// descendant is rebuilt when the displayed frame changes.
@immutable
final class MapigradeFrame {
  const MapigradeFrame._(
    this.camera,
    this.size,
    this._matrix,
    this._inverse,
    this._centerX,
    this._depthFromZero,
    this._id,
  );

  /// The displayed frame of the `MapigradeMap` above [context], or null
  /// before the map has displayed its first frame or outside a
  /// `MapigradeMap`. [context] is rebuilt when the displayed frame changes.
  static MapigradeFrame? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapigradeFrameScope>()?.frame;

  /// The displayed frame of the `MapigradeMap` above [context], which is
  /// rebuilt when the displayed frame changes. Throws a [FlutterError] before
  /// the map has displayed its first frame, or outside a `MapigradeMap`; use
  /// [maybeOf] where that can happen.
  static MapigradeFrame of(BuildContext context) {
    final frame = maybeOf(context);
    if (frame == null) {
      throw FlutterError(
        'MapigradeFrame.of() found no displayed frame: the context is not '
        'below a MapigradeMap, or the map has not displayed a frame yet.',
      );
    }
    return frame;
  }

  /// The camera the frame was drawn with, with every field set.
  final MapigradeCamera camera;

  /// The frame's logical size.
  final Size size;

  final Float64List _matrix;
  final Float64List _inverse;
  // The Web Mercator x of the camera's unwrapped center.
  final double _centerX;
  // Whether clip z runs from 0 to w; otherwise from -w to w.
  final bool _depthFromZero;
  final int _id;

  /// The logical position at which the frame draws [coordinate] at
  /// [altitude] meters, or null when the coordinate is behind the camera. Of
  /// the copies of the world, the one nearest the camera's center is used.
  Offset? project(LatLng coordinate, {double altitude = 0}) {
    final clip = clipOf(coordinate, altitude: altitude);
    if (!(clip.w > 0)) return null;
    return positionOfClip(clip);
  }

  /// The coordinate where the line of sight through [position] meets the
  /// ground plane at altitude 0, or null when it doesn't meet it in front of
  /// the camera, as above the horizon. The ground plane is flat: over terrain
  /// or on a globe this is not where the frame draws the ground.
  LatLng? unproject(Offset position) {
    final world = worldOf(position);
    if (world == null) return null;
    return _latLngOf(world);
  }

  ({double x, double y, double z})? _unprojectNdc(
    double nx,
    double ny,
    double nz,
  ) {
    final m = _inverse;
    final x = m[0] * nx + m[4] * ny + m[8] * nz + m[12];
    final y = m[1] * nx + m[5] * ny + m[9] * nz + m[13];
    final z = m[2] * nx + m[6] * ny + m[10] * nz + m[14];
    final w = m[3] * nx + m[7] * ny + m[11] * nz + m[15];
    if (w == 0) return null;
    return (x: x / w, y: y / w, z: z / w);
  }

  @override
  bool operator ==(Object other) =>
      other is MapigradeFrame &&
      other._id == _id &&
      other.size == size &&
      listEquals(other._matrix, _matrix);

  @override
  int get hashCode => Object.hash(_id, size);
}

/// The members of [MapigradeFrame] that the package's markers, map and tests
/// use; not API.
extension MapigradeFrameInternals on MapigradeFrame {
  /// The frame of [frame], or null when it has no matrix.
  static MapigradeFrame? fromFrame(FrameCamera frame) {
    final view = frame.view;
    if (view == null) return null;
    final inverse = _invert(view.matrix);
    if (inverse == null) return null;
    return MapigradeFrame._(
      frameCameraOf(frame),
      frame.physicalSize / frame.scaleFactor,
      view.matrix,
      inverse,
      (frame.camera.longitude + 180) / 360,
      view.clipDepthRange != 2,
      frame.frameId,
    );
  }

  /// A frame with the clip [matrix] (column-major, from Web Mercator x and y
  /// in [0, 1) and z in meters) of [camera] in a viewport of logical [size],
  /// for tests. [centerLongitude] is the camera's unwrapped center longitude.
  @visibleForTesting
  static MapigradeFrame forTesting({
    required MapigradeCamera camera,
    required Size size,
    required Float64List matrix,
    double? centerLongitude,
    bool zeroToOneDepth = true,
    int id = 0,
  }) => MapigradeFrame._(
    camera,
    size,
    matrix,
    _invert(matrix)!,
    ((centerLongitude ?? camera.center!.longitude) + 180) / 360,
    zeroToOneDepth,
    id,
  );

  /// The frame's clip matrix, column-major.
  Float64List get matrix => _matrix;

  /// The Web Mercator x and y of [coordinate], in the copy of the world
  /// nearest the camera's center.
  Offset clipOfWorldPoint(LatLng coordinate) {
    final world = mercator(coordinate.latitude, coordinate.longitude);
    return Offset(world.dx + (_centerX - world.dx).roundToDouble(), world.dy);
  }

  /// The clip coordinates of [coordinate] at [altitude] meters, in the copy
  /// of the world nearest the camera's center.
  ({double x, double y, double z, double w}) clipOf(
    LatLng coordinate, {
    double altitude = 0,
  }) {
    final world = mercator(coordinate.latitude, coordinate.longitude);
    var x = world.dx;
    x += (_centerX - x).roundToDouble();
    return clipOfWorld(x, world.dy, altitude);
  }

  /// The clip coordinates of Web Mercator [x], [y] and [z] meters.
  ({double x, double y, double z, double w}) clipOfWorld(
    double x,
    double y,
    double z,
  ) {
    final m = _matrix;
    return (
      x: m[0] * x + m[4] * y + m[8] * z + m[12],
      y: m[1] * x + m[5] * y + m[9] * z + m[13],
      z: m[2] * x + m[6] * y + m[10] * z + m[14],
      w: m[3] * x + m[7] * y + m[11] * z + m[15],
    );
  }

  /// The logical position of clip coordinates with a positive w.
  Offset positionOfClip(({double x, double y, double z, double w}) clip) =>
      Offset(
        (clip.x / clip.w + 1) / 2 * size.width,
        (1 - clip.y / clip.w) / 2 * size.height,
      );

  /// Whether clip coordinates lie between the frame's near and far planes.
  bool withinDepth(({double x, double y, double z, double w}) clip) {
    final lowest = _depthFromZero ? 0 : -clip.w;
    return clip.w > 0 && clip.z >= lowest && clip.z <= clip.w;
  }

  /// The Web Mercator x and y, unwrapped, where the line of sight through
  /// [position] meets the ground plane, or null.
  Offset? worldOf(Offset position) {
    final nx = 2 * position.dx / size.width - 1;
    final ny = 1 - 2 * position.dy / size.height;
    final near = _unprojectNdc(nx, ny, _depthFromZero ? 0 : -1);
    final far = _unprojectNdc(nx, ny, 1);
    if (near == null || far == null) return null;
    final dz = near.z - far.z;
    if (dz == 0) return null;
    final t = near.z / dz;
    if (!(t >= 0)) return null;
    final x = near.x + t * (far.x - near.x);
    final y = near.y + t * (far.y - near.y);
    // In front of the camera.
    if (!(clipOfWorld(x, y, 0).w > 0)) return null;
    return Offset(x, y);
  }

  /// The width of the world in logical pixels at the camera's zoom: the
  /// length of one Web Mercator unit on the ground at the camera's center.
  double get worldSizeInPixels => worldSize(camera.zoom!);

  /// The Web Mercator x and y of the camera's center, unwrapped.
  Offset get centerWorld {
    final center = camera.center!;
    final world = mercator(center.latitude, center.longitude);
    return Offset(world.dx + (_centerX - world.dx).roundToDouble(), world.dy);
  }
}

LatLng _latLngOf(Offset world) {
  final longitude = ((world.dx * 360 - 180) + 180) % 360 - 180;
  final n = math.pi - 2 * math.pi * world.dy;
  final latitude =
      180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  return LatLng(latitude.clamp(-90.0, 90.0), longitude);
}

/// The inverse of the column-major 4x4 matrix [m], or null when it is
/// singular.
Float64List? _invert(Float64List m) {
  final inv = Float64List(16);
  inv[0] =
      m[5] * m[10] * m[15] -
      m[5] * m[11] * m[14] -
      m[9] * m[6] * m[15] +
      m[9] * m[7] * m[14] +
      m[13] * m[6] * m[11] -
      m[13] * m[7] * m[10];
  inv[4] =
      -m[4] * m[10] * m[15] +
      m[4] * m[11] * m[14] +
      m[8] * m[6] * m[15] -
      m[8] * m[7] * m[14] -
      m[12] * m[6] * m[11] +
      m[12] * m[7] * m[10];
  inv[8] =
      m[4] * m[9] * m[15] -
      m[4] * m[11] * m[13] -
      m[8] * m[5] * m[15] +
      m[8] * m[7] * m[13] +
      m[12] * m[5] * m[11] -
      m[12] * m[7] * m[9];
  inv[12] =
      -m[4] * m[9] * m[14] +
      m[4] * m[10] * m[13] +
      m[8] * m[5] * m[14] -
      m[8] * m[6] * m[13] -
      m[12] * m[5] * m[10] +
      m[12] * m[6] * m[9];
  inv[1] =
      -m[1] * m[10] * m[15] +
      m[1] * m[11] * m[14] +
      m[9] * m[2] * m[15] -
      m[9] * m[3] * m[14] -
      m[13] * m[2] * m[11] +
      m[13] * m[3] * m[10];
  inv[5] =
      m[0] * m[10] * m[15] -
      m[0] * m[11] * m[14] -
      m[8] * m[2] * m[15] +
      m[8] * m[3] * m[14] +
      m[12] * m[2] * m[11] -
      m[12] * m[3] * m[10];
  inv[9] =
      -m[0] * m[9] * m[15] +
      m[0] * m[11] * m[13] +
      m[8] * m[1] * m[15] -
      m[8] * m[3] * m[13] -
      m[12] * m[1] * m[11] +
      m[12] * m[3] * m[9];
  inv[13] =
      m[0] * m[9] * m[14] -
      m[0] * m[10] * m[13] -
      m[8] * m[1] * m[14] +
      m[8] * m[2] * m[13] +
      m[12] * m[1] * m[10] -
      m[12] * m[2] * m[9];
  inv[2] =
      m[1] * m[6] * m[15] -
      m[1] * m[7] * m[14] -
      m[5] * m[2] * m[15] +
      m[5] * m[3] * m[14] +
      m[13] * m[2] * m[7] -
      m[13] * m[3] * m[6];
  inv[6] =
      -m[0] * m[6] * m[15] +
      m[0] * m[7] * m[14] +
      m[4] * m[2] * m[15] -
      m[4] * m[3] * m[14] -
      m[12] * m[2] * m[7] +
      m[12] * m[3] * m[6];
  inv[10] =
      m[0] * m[5] * m[15] -
      m[0] * m[7] * m[13] -
      m[4] * m[1] * m[15] +
      m[4] * m[3] * m[13] +
      m[12] * m[1] * m[7] -
      m[12] * m[3] * m[5];
  inv[14] =
      -m[0] * m[5] * m[14] +
      m[0] * m[6] * m[13] +
      m[4] * m[1] * m[14] -
      m[4] * m[2] * m[13] -
      m[12] * m[1] * m[6] +
      m[12] * m[2] * m[5];
  inv[3] =
      -m[1] * m[6] * m[11] +
      m[1] * m[7] * m[10] +
      m[5] * m[2] * m[11] -
      m[5] * m[3] * m[10] -
      m[9] * m[2] * m[7] +
      m[9] * m[3] * m[6];
  inv[7] =
      m[0] * m[6] * m[11] -
      m[0] * m[7] * m[10] -
      m[4] * m[2] * m[11] +
      m[4] * m[3] * m[10] +
      m[8] * m[2] * m[7] -
      m[8] * m[3] * m[6];
  inv[11] =
      -m[0] * m[5] * m[11] +
      m[0] * m[7] * m[9] +
      m[4] * m[1] * m[11] -
      m[4] * m[3] * m[9] -
      m[8] * m[1] * m[7] +
      m[8] * m[3] * m[5];
  inv[15] =
      m[0] * m[5] * m[10] -
      m[0] * m[6] * m[9] -
      m[4] * m[1] * m[10] +
      m[4] * m[2] * m[9] +
      m[8] * m[1] * m[6] -
      m[8] * m[2] * m[5];
  final det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  if (det == 0 || !det.isFinite) return null;
  for (var i = 0; i < 16; ++i) {
    inv[i] /= det;
  }
  return inv;
}

/// Provides the displayed [frame] of a `MapigradeMap` to its descendants
/// (design D242), and [listenable], which changes with each displayed frame
/// without rebuilding them, to render objects such as the markers'.
class MapigradeFrameScope extends InheritedWidget {
  /// A scope of [frame].
  const MapigradeFrameScope({
    super.key,
    required this.frame,
    required this.listenable,
    required super.child,
  });

  /// The displayed frame, or null before the first.
  final MapigradeFrame? frame;

  /// The displayed frame, as it changes.
  final ValueListenable<MapigradeFrame?> listenable;

  /// The [listenable] of the map above [context], without depending on the
  /// frame, or null outside a map.
  static ValueListenable<MapigradeFrame?>? listenableOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MapigradeFrameScope>()?.listenable;

  @override
  bool updateShouldNotify(MapigradeFrameScope oldWidget) =>
      frame != oldWidget.frame;
}
