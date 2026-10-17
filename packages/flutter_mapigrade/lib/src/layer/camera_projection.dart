// Camera conversion (design D22) and the Web Mercator projection that camera
// prediction and the alignment error use.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import '../texture/map_texture_controller.dart';

/// The largest latitude Web Mercator shows, as in MapLibre.
const double maxMercatorLatitude = 85.051128779806604;

/// A MapLibre camera and the logical size of the viewport that shows it.
class ViewCamera {
  /// [camera] shown in a viewport of logical size [viewport].
  const ViewCamera(this.camera, this.viewport);

  /// The camera and logical viewport size that [frame] was rendered with.
  ViewCamera.ofFrame(FrameCamera frame)
    : camera = frame.camera,
      viewport = frame.physicalSize / frame.scaleFactor;

  /// The MapLibre camera.
  final MapCamera camera;

  /// The logical size of the viewport.
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

/// The `flutter_map` camera that [viewCameraOf] converts to [camera]: its
/// inverse, with the CRS, viewport size and zoom limits of [live] (design D125
/// of the layer-children-alignment change). The layer builds it for a
/// predicted camera, to draw its children at the camera of the map frame
/// rendered with it.
fm.MapCamera flutterMapCameraOf(MapCamera camera, fm.MapCamera live) =>
    fm.MapCamera(
      crs: live.crs,
      center: LatLng(camera.latitude, camera.longitude),
      zoom: camera.zoom + 1,
      rotation: -camera.bearing,
      nonRotatedSize: live.nonRotatedSize,
      minZoom: live.minZoom,
      maxZoom: live.maxZoom,
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
