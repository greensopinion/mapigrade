import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/src/camera_projection.dart';
import 'package:mapigrade/src/map/camera.dart';
import 'package:mapigrade/src/map/mapigrade_frame.dart';

/// A clip matrix built as MapLibre's transform builds it, without padding or
/// roll, with OpenGL's clip depth from -w to w: from Web Mercator x and y in
/// [0, 1) and z in meters to clip space.
Float64List testMatrix({
  required LatLng center,
  required double zoom,
  required Size size,
  double bearing = 0,
  double pitch = 0,
  double fieldOfView = 36.86989764584402,
}) {
  final fov = fieldOfView * math.pi / 180;
  final distance = 0.5 * size.height / math.tan(fov / 2);
  const near = 1.0;
  final far = distance * 100;
  final f = 1 / math.tan(fov / 2);
  final projection = Matrix4.zero()
    ..setEntry(0, 0, f / (size.width / size.height))
    ..setEntry(1, 1, f)
    ..setEntry(2, 2, (far + near) / (near - far))
    ..setEntry(3, 2, -1)
    ..setEntry(2, 3, 2 * far * near / (near - far));
  final world = worldSize(zoom);
  final c = mercator(center.latitude, center.longitude);
  final metersPerPixel =
      40075016.68557849 * math.cos(center.latitude * math.pi / 180) / world;
  final m = projection
    ..scaleByDouble(1, -1, 1, 1)
    ..translateByDouble(0, 0, -distance, 1)
    ..rotateX(pitch * math.pi / 180)
    ..rotateZ(-bearing * math.pi / 180)
    ..translateByDouble(-c.dx * world, -c.dy * world, 0, 1)
    ..scaleByDouble(world, world, 1 / metersPerPixel, 1);
  return Float64List.fromList(m.storage);
}

/// A frame of [testMatrix].
MapigradeFrame testFrame({
  LatLng center = const LatLng(48.2, 16.37),
  double zoom = 14,
  Size size = const Size(400, 600),
  double bearing = 0,
  double pitch = 0,
  int id = 0,
}) => MapigradeFrameInternals.forTesting(
  camera: MapigradeCamera(
    center: center,
    centerAltitude: 0,
    zoom: zoom,
    bearing: bearing,
    pitch: pitch,
    roll: 0,
    fieldOfView: 36.86989764584402,
    padding: EdgeInsets.zero,
  ),
  size: size,
  matrix: testMatrix(
    center: center,
    zoom: zoom,
    size: size,
    bearing: bearing,
    pitch: pitch,
  ),
  zeroToOneDepth: false,
  id: id,
);
