// Camera prediction (designs D32 and D33 of the camera-prediction change).
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../texture/map_texture_controller.dart';
import 'camera_projection.dart';

/// Records older than this are not used for the velocity, so a pause between
/// gestures starts from zero velocity (design D32).
const Duration maxCameraRecordAge = Duration(milliseconds: 50);

/// A converted camera and the vsync target time of the Flutter frame whose
/// build recorded it.
typedef CameraRecord = ({Duration time, ViewCamera camera});

/// The rate of change of a camera, per second: the center in normalized
/// Mercator coordinates, the zoom, and the bearing in degrees.
class CameraVelocity {
  /// A velocity with these rates of change.
  const CameraVelocity(this.center, this.zoom, this.bearing);

  /// No change.
  static const zero = CameraVelocity(Offset.zero, 0, 0);

  /// The rate of change of the center, in normalized Mercator coordinates.
  final Offset center;
  /// The rate of change of the zoom.
  final double zoom;
  /// The rate of change of the bearing, in degrees.
  final double bearing;

  @override
  bool operator ==(Object other) =>
      other is CameraVelocity &&
      other.center == center &&
      other.zoom == zoom &&
      other.bearing == bearing;

  @override
  int get hashCode => Object.hash(center, zoom, bearing);

  @override
  String toString() => 'CameraVelocity($center, $zoom, $bearing)';
}

/// The velocity of the camera of the last record in [records], which are
/// ordered by time: the difference to the camera of two records earlier
/// divided by the time between them, or to the previous record if only that
/// one is recent enough. Records older than [maxCameraRecordAge] before the
/// last one are not used. The velocity is zero if the last camera equals the
/// one before it, or if no earlier record is recent enough.
CameraVelocity cameraVelocity(List<CameraRecord> records) {
  if (records.length < 2) return CameraVelocity.zero;
  final last = records.last;
  if (records[records.length - 2].camera.camera._equals(last.camera.camera)) {
    return CameraVelocity.zero;
  }
  for (final back in [2, 1]) {
    if (records.length <= back) continue;
    final earlier = records[records.length - 1 - back];
    final dt = last.time - earlier.time;
    if (dt > maxCameraRecordAge || dt <= Duration.zero) continue;
    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    final from = earlier.camera.camera;
    final to = last.camera.camera;
    return CameraVelocity(
      _wrap(
            mercator(to.latitude, to.longitude) -
                mercator(from.latitude, from.longitude),
          ) /
          seconds,
      (to.zoom - from.zoom) / seconds,
      _angleDifference(to.bearing, from.bearing) / seconds,
    );
  }
  return CameraVelocity.zero;
}

/// [view] moved by [velocity] for [seconds], with the latitude clamped to the
/// Mercator limit and the longitude normalized to [-180, 180) (design D33).
ViewCamera extrapolateCamera(
  ViewCamera view,
  CameraVelocity velocity,
  double seconds,
) {
  if (velocity == CameraVelocity.zero) return view;
  final camera = view.camera;
  final center =
      mercator(camera.latitude, camera.longitude) + velocity.center * seconds;
  final (latitude, longitude) = latLonOf(center);
  return ViewCamera(
    MapCamera(
      latitude: latitude,
      longitude: longitude,
      zoom: camera.zoom + velocity.zoom * seconds,
      bearing: camera.bearing + velocity.bearing * seconds,
    ),
    view.viewport,
  );
}

/// The latitude and longitude of normalized Mercator coordinates, the inverse
/// of [mercator], with the latitude clamped to the Mercator limit and the
/// longitude normalized to [-180, 180).
(double, double) latLonOf(Offset world) {
  final latitude =
      math.atan(_sinh(math.pi * (1 - 2 * world.dy))) * 180 / math.pi;
  final x = world.dx - world.dx.floorToDouble();
  final longitude = x * 360 - 180;
  return (
    latitude.clamp(-maxMercatorLatitude, maxMercatorLatitude),
    // Rounding can give 180 for an x just below 1.
    longitude >= 180 ? longitude - 360 : longitude,
  );
}

/// Predicts the camera from the converted cameras of the layer's recent
/// builds (designs D32 and D33).
class CameraPredictor {
  final Queue<CameraRecord> _records = Queue();

  /// Records [view] as the converted camera of the build of the Flutter frame
  /// with vsync target time [time], and returns it extrapolated by [seconds]
  /// from its velocity. A second build in the same Flutter frame replaces
  /// the record of the first.
  ViewCamera predict(ViewCamera view, Duration time, double seconds) {
    if (_records.isNotEmpty && _records.last.time >= time) {
      _records.removeLast();
    }
    _records.addLast((time: time, camera: view));
    while (_records.length > 3 ||
        time - _records.first.time > maxCameraRecordAge) {
      _records.removeFirst();
    }
    return extrapolateCamera(view, cameraVelocity(_records.toList()), seconds);
  }
}

extension on MapCamera {
  bool _equals(MapCamera other) =>
      latitude == other.latitude &&
      longitude == other.longitude &&
      zoom == other.zoom &&
      bearing == other.bearing;
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// The signed shorter angle from [from] to [to] in degrees, in [-180, 180).
double _angleDifference(double to, double from) {
  final d = (to - from) % 360;
  return d >= 180 ? d - 360 : d;
}

/// Moves the x of [d] into [-0.5, 0.5) by whole worlds.
Offset _wrap(Offset d) => Offset(d.dx - (d.dx + 0.5).floorToDouble(), d.dy);
