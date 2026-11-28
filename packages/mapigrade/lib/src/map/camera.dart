import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

/// A map camera, with the fields of MapLibre's camera in MapLibre's
/// conventions.
///
/// The cameras that a `MapigradeCameraController` reports have every field.
/// A camera given to a camera command, or as a `MapigradeMap`'s initial
/// camera, may leave fields null: a command keeps their values, and an initial
/// camera gets MapLibre's defaults for them.
@immutable
final class MapigradeCamera {
  /// A camera with the given fields.
  const MapigradeCamera({
    this.center,
    this.centerAltitude,
    this.zoom,
    this.bearing,
    this.pitch,
    this.roll,
    this.fieldOfView,
    this.padding,
  });

  /// The coordinate at the center of the area that [padding] leaves.
  final LatLng? center;

  /// The altitude of [center] in meters above sea level.
  final double? centerAltitude;

  /// The zoom of 512-pixel tiles: at zoom 0 the world is 512 logical pixels
  /// wide.
  final double? zoom;

  /// The bearing in degrees clockwise from north.
  final double? bearing;

  /// The pitch in degrees from looking straight down.
  final double? pitch;

  /// The roll in degrees.
  final double? roll;

  /// The vertical field of view in degrees.
  final double? fieldOfView;

  /// The insets in logical pixels from the widget's edges of the area in
  /// which the camera centers.
  final EdgeInsets? padding;

  /// A copy with the fields that [other] sets replaced.
  MapigradeCamera merge(MapigradeCamera other) => MapigradeCamera(
    center: other.center ?? center,
    centerAltitude: other.centerAltitude ?? centerAltitude,
    zoom: other.zoom ?? zoom,
    bearing: other.bearing ?? bearing,
    pitch: other.pitch ?? pitch,
    roll: other.roll ?? roll,
    fieldOfView: other.fieldOfView ?? fieldOfView,
    padding: other.padding ?? padding,
  );

  @override
  bool operator ==(Object other) =>
      other is MapigradeCamera &&
      other.center == center &&
      other.centerAltitude == centerAltitude &&
      other.zoom == zoom &&
      other.bearing == bearing &&
      other.pitch == pitch &&
      other.roll == roll &&
      other.fieldOfView == fieldOfView &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(
    center,
    centerAltitude,
    zoom,
    bearing,
    pitch,
    roll,
    fieldOfView,
    padding,
  );

  @override
  String toString() {
    final fields = [
      if (center case final c?) 'center: ${c.latitude}, ${c.longitude}',
      if (centerAltitude != null) 'centerAltitude: $centerAltitude',
      if (zoom != null) 'zoom: $zoom',
      if (bearing != null) 'bearing: $bearing',
      if (pitch != null) 'pitch: $pitch',
      if (roll != null) 'roll: $roll',
      if (fieldOfView != null) 'fieldOfView: $fieldOfView',
      if (padding != null) 'padding: $padding',
    ];
    return 'MapigradeCamera(${fields.join(', ')})';
  }
}

/// A rectangle of coordinates, from its south-west to its north-east corner.
@immutable
final class GeoBounds {
  /// The bounds from [southWest] to [northEast]. The latitude of [southWest]
  /// must not be above that of [northEast]. A west longitude above the east
  /// one crosses the antimeridian.
  GeoBounds(this.southWest, this.northEast) {
    if (southWest.latitude > northEast.latitude) {
      throw ArgumentError.value(
        southWest,
        'southWest',
        'is north of northEast',
      );
    }
  }

  /// The smallest bounds that contain [points], which must not be empty.
  factory GeoBounds.fromPoints(Iterable<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'must not be empty');
    }
    var south = 90.0, west = 180.0, north = -90.0, east = -180.0;
    for (final point in points) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }
    return GeoBounds(LatLng(south, west), LatLng(north, east));
  }

  /// The south-west corner.
  final LatLng southWest;

  /// The north-east corner.
  final LatLng northEast;

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.southWest == southWest &&
      other.northEast == northEast;

  @override
  int get hashCode => Object.hash(southWest, northEast);

  @override
  String toString() => 'GeoBounds($southWest, $northEast)';
}

/// The limits of a `MapigradeMap`'s camera: gestures, camera commands and
/// the initial camera keep the camera within them.
@immutable
final class CameraLimits {
  /// Limits with the given ranges and, with [bounds], an area that the
  /// camera's center stays within. Each minimum must not be above its maximum,
  /// and the pitch range must be within 0 to 85 degrees.
  CameraLimits({
    this.minZoom = 0,
    this.maxZoom = 22,
    this.minPitch = 0,
    this.maxPitch = 60,
    this.bounds,
  }) {
    if (!minZoom.isFinite || !maxZoom.isFinite || minZoom > maxZoom) {
      throw ArgumentError('minZoom $minZoom and maxZoom $maxZoom are invalid');
    }
    if (!(minPitch >= 0) || !(maxPitch <= 85) || minPitch > maxPitch) {
      throw ArgumentError(
        'minPitch $minPitch and maxPitch $maxPitch are invalid',
      );
    }
  }

  /// The minimum zoom.
  final double minZoom;

  /// The maximum zoom.
  final double maxZoom;

  /// The minimum pitch in degrees.
  final double minPitch;

  /// The maximum pitch in degrees.
  final double maxPitch;

  /// The area that the camera's center stays within, or null for none.
  final GeoBounds? bounds;

  @override
  bool operator ==(Object other) =>
      other is CameraLimits &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.minPitch == minPitch &&
      other.maxPitch == maxPitch &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom, minPitch, maxPitch, bounds);

  @override
  String toString() =>
      'CameraLimits(zoom: $minZoom-$maxZoom, pitch: $minPitch-$maxPitch, '
      'bounds: $bounds)';
}

/// What moved the camera.
enum CameraChangeSource {
  /// A gesture, or its glide or snap.
  gesture,

  /// A camera command, or the map itself, as when new limits move the camera.
  command,
}

/// A displayed frame whose camera differs from the previous displayed frame's.
@immutable
final class CameraChange {
  /// A change to [camera], which [source] moved.
  const CameraChange(this.camera, this.source);

  /// The camera of the displayed frame.
  final MapigradeCamera camera;

  /// What moved the camera.
  final CameraChangeSource source;

  @override
  bool operator ==(Object other) =>
      other is CameraChange && other.camera == camera && other.source == source;

  @override
  int get hashCode => Object.hash(camera, source);

  @override
  String toString() => 'CameraChange($camera, $source)';
}

/// How a camera command's transition ended.
enum CameraTransitionOutcome {
  /// The camera reached the command's target.
  completed,

  /// A cancel, a gesture or the map's disposal stopped it.
  cancelled,

  /// A later command set every field that it was still animating.
  replaced,
}
