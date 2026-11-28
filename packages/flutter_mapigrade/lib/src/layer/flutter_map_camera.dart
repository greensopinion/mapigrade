import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
// ignore: implementation_imports
import 'package:mapigrade/src/integration.dart';

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
      minZoom: live.minZoom,
      maxZoom: live.maxZoom,
    );
