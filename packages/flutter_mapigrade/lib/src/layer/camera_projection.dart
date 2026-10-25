import 'dart:math' as math;

import 'package:flutter/painting.dart';

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
      other.camera.pitch == camera.pitch &&
      other.viewport == viewport;

  @override
  int get hashCode => Object.hash(
    camera.latitude,
    camera.longitude,
    camera.zoom,
    camera.bearing,
    camera.pitch,
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
    pitch: camera.pitch,
  ),
  camera.nonRotatedSize,
);

/// The `flutter_map` camera that [viewCameraOf] converts to [camera]: its
/// inverse, with the CRS, viewport size and zoom limits of [live]. The layer
/// builds it for a predicted camera, to draw its children at the camera of the
/// map frame rendered with it.
fm.MapCamera flutterMapCameraOf(MapCamera camera, fm.MapCamera live) =>
    fm.MapCamera(
      crs: live.crs,
      center: LatLng(camera.latitude, camera.longitude),
      zoom: camera.zoom + 1,
      rotation: -camera.bearing,
      nonRotatedSize: live.nonRotatedSize,
      pitch: camera.pitch,
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
Offset screenPosition(ViewCamera view, Offset world) =>
    MatrixUtils.transformPoint(
      _cameraOf(view).pixelToScreenTransform,
      world * worldSize(view.camera.zoom),
    );

/// The normalized Mercator coordinates of the point that MapLibre draws at
/// the logical position [screen] in the viewport of [view]; the inverse of
/// [screenPosition].
Offset worldPosition(ViewCamera view, Offset screen) {
  // On the ground, the transform is the homography of its rows and columns
  // 0, 1 and 3; inverting it doesn't limit the longitude, as unprojecting
  // through the CRS would.
  final m = _cameraOf(view).pixelToScreenTransform.storage;
  final h = [m[0], m[4], m[12], m[1], m[5], m[13], m[3], m[7], m[15]];
  final inverse = _invert3(h);
  final x = inverse[0] * screen.dx + inverse[1] * screen.dy + inverse[2];
  final y = inverse[3] * screen.dx + inverse[4] * screen.dy + inverse[5];
  final w = inverse[6] * screen.dx + inverse[7] * screen.dy + inverse[8];
  return Offset(x / w, y / w) / worldSize(view.camera.zoom);
}

/// The `flutter_map` camera that shows the same map as [view].
fm.MapCamera _cameraOf(ViewCamera view) => fm.MapCamera(
  crs: const fm.Epsg3857(),
  center: LatLng(view.camera.latitude, view.camera.longitude),
  zoom: view.camera.zoom + 1,
  rotation: -view.camera.bearing,
  pitch: view.camera.pitch,
  nonRotatedSize: view.viewport,
);

/// The inverse of the row-major 3 x 3 matrix [m].
List<double> _invert3(List<double> m) {
  final a = m[4] * m[8] - m[5] * m[7];
  final b = m[5] * m[6] - m[3] * m[8];
  final c = m[3] * m[7] - m[4] * m[6];
  final det = m[0] * a + m[1] * b + m[2] * c;
  return [
    a / det,
    (m[2] * m[7] - m[1] * m[8]) / det,
    (m[1] * m[5] - m[2] * m[4]) / det,
    b / det,
    (m[0] * m[8] - m[2] * m[6]) / det,
    (m[2] * m[3] - m[0] * m[5]) / det,
    c / det,
    (m[1] * m[6] - m[0] * m[7]) / det,
    (m[0] * m[4] - m[1] * m[3]) / det,
  ];
}
