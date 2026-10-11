// Camera conversion (design D22) and the compensating transform (design D23).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show Matrix4, MatrixUtils;
import 'package:flutter_map/flutter_map.dart' as fm;

import '../texture/map_texture_controller.dart';

/// The largest latitude Web Mercator shows, as in MapLibre.
const double maxMercatorLatitude = 85.051128779806604;

/// A MapLibre camera and the logical size of the viewport that shows it.
class ViewCamera {
  const ViewCamera(this.camera, this.viewport);

  /// The camera and logical viewport size that [frame] was rendered with.
  ViewCamera.ofFrame(FrameCamera frame)
    : camera = frame.camera,
      viewport = frame.physicalSize / frame.scaleFactor;

  final MapCamera camera;
  final Size viewport;

  @override
  bool operator ==(Object other) =>
      other is ViewCamera &&
      other.camera.latitude == camera.latitude &&
      other.camera.longitude == camera.longitude &&
      other.camera.zoom == camera.zoom &&
      other.camera.bearing == camera.bearing &&
      other.viewport == viewport;

  @override
  int get hashCode => Object.hash(
    camera.latitude,
    camera.longitude,
    camera.zoom,
    camera.bearing,
    viewport,
  );

  @override
  String toString() =>
      'ViewCamera($camera, ${viewport.width}x${viewport.height})';
}

/// Converts a `flutter_map` camera to the MapLibre camera that shows the same
/// map: MapLibre uses 512 px tiles where `flutter_map` uses 256 px tiles, and
/// MapLibre's bearing turns the map the other way.
ViewCamera viewCameraOf(fm.MapCamera camera) => ViewCamera(
  MapCamera(
    latitude: camera.center.latitude,
    longitude: camera.center.longitude,
    zoom: camera.zoom - 1,
    bearing: -camera.rotation,
  ),
  camera.nonRotatedSize,
);

/// Web Mercator coordinates of a latitude and longitude, normalized so that
/// the world is [0, 1) in both directions, with y increasing southwards.
Offset mercator(double latitude, double longitude) {
  final lat = latitude.clamp(-maxMercatorLatitude, maxMercatorLatitude);
  final phi = lat * math.pi / 180;
  return Offset(
    (longitude + 180) / 360,
    (1 - math.log(math.tan(math.pi / 4 + phi / 2)) / math.pi) / 2,
  );
}

/// The width of the world in logical pixels at MapLibre zoom [zoom].
double worldSize(double zoom) => 512 * math.pow(2, zoom).toDouble();

/// The logical position in the viewport of [view] at which MapLibre draws
/// the point at normalized Mercator coordinates [world].
Offset screenPosition(ViewCamera view, Offset world) {
  final center = mercator(view.camera.latitude, view.camera.longitude);
  final d = (world - center) * worldSize(view.camera.zoom);
  return _rotate(d, -_radians(view.camera.bearing)) +
      view.viewport.center(Offset.zero);
}

/// The transform T(from -> to) that moves a frame rendered at [from] so that
/// each coordinate in it appears where [to] places it (design D23).
///
/// The longitude difference between the two centers is taken the short way
/// round, so a frame on the other side of the antimeridian isn't shifted by a
/// world width.
Matrix4 frameTransform(ViewCamera from, ViewCamera to) {
  final scale = math.pow(2, to.camera.zoom - from.camera.zoom).toDouble();
  final angle = _radians(from.camera.bearing - to.camera.bearing);
  final cos = scale * math.cos(angle);
  final sin = scale * math.sin(angle);
  // The linear part, scale * rotate(angle).
  Offset linear(Offset p) =>
      Offset(cos * p.dx - sin * p.dy, sin * p.dx + cos * p.dy);

  final d =
      _wrap(
        mercator(from.camera.latitude, from.camera.longitude) -
            mercator(to.camera.latitude, to.camera.longitude),
      ) *
      worldSize(from.camera.zoom);
  final t =
      to.viewport.center(Offset.zero) +
      _rotate(d, -_radians(to.camera.bearing)) * scale -
      linear(from.viewport.center(Offset.zero));
  // Column-major: x' = cos x - sin y + t.dx, y' = sin x + cos y + t.dy.
  return Matrix4(
    cos,
    sin,
    0,
    0, //
    -sin,
    cos,
    0,
    0, //
    0,
    0,
    1,
    0, //
    t.dx,
    t.dy,
    0,
    1,
  );
}

/// The transform the layer draws its texture with while the frame rendered
/// at [from] is displayed for the camera [to]: [frameTransform] after
/// undoing the stretch of the `Texture` widget, which scales the frame from
/// its own size to the viewport of [to].
///
/// Returns null, meaning no transform, if the transform would move the frame
/// entirely outside the viewport. Flutter doesn't draw a texture outside its
/// clip, and then never takes a newer frame that would update the transform
/// (design D23).
Matrix4? layerTransform(ViewCamera from, ViewCamera to) {
  final transform = frameTransform(from, to)
    ..multiply(
      Matrix4.diagonal3Values(
        from.viewport.width / to.viewport.width,
        from.viewport.height / to.viewport.height,
        1,
      ),
    );
  final size = to.viewport;
  final corners = [
    Offset.zero,
    Offset(size.width, 0),
    Offset(size.width, size.height),
    Offset(0, size.height),
  ];
  final frame = [
    for (final c in corners) MatrixUtils.transformPoint(transform, c),
  ];
  return _quadsOverlap(frame, corners) ? transform : null;
}

/// True if the convex quadrilaterals [a] and [b], each given by its corners
/// in order, share an area: no edge normal of either separates them.
bool _quadsOverlap(List<Offset> a, List<Offset> b) {
  for (final quad in [a, b]) {
    for (var i = 0; i < 4; i++) {
      final edge = quad[(i + 1) % 4] - quad[i];
      final normal = Offset(-edge.dy, edge.dx);
      double dot(Offset p) => p.dx * normal.dx + p.dy * normal.dy;
      final pa = a.map(dot);
      final pb = b.map(dot);
      if (pa.reduce(math.max) <= pb.reduce(math.min) ||
          pb.reduce(math.max) <= pa.reduce(math.min)) {
        return false;
      }
    }
  }
  return true;
}

/// The normalized Mercator coordinates of the point that MapLibre draws at
/// the logical position [screen] in the viewport of [view]; the inverse of
/// [screenPosition].
Offset worldPosition(ViewCamera view, Offset screen) {
  final center = mercator(view.camera.latitude, view.camera.longitude);
  final d = _rotate(
    screen - view.viewport.center(Offset.zero),
    _radians(view.camera.bearing),
  );
  return center + d / worldSize(view.camera.zoom);
}

double _radians(double degrees) => degrees * math.pi / 180;

/// Rotates [p] by [angle] radians, clockwise on screen for a positive angle.
Offset _rotate(Offset p, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(c * p.dx - s * p.dy, s * p.dx + c * p.dy);
}

/// Moves the x of [d] into [-0.5, 0.5) by whole worlds.
Offset _wrap(Offset d) => Offset(d.dx - (d.dx + 0.5).floorToDouble(), d.dy);
