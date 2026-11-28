import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';

import '../texture/map_texture_controller.dart';
import 'camera.dart';

/// MapLibre's default vertical field of view in degrees.
const double defaultFieldOfView = 36.86989764584402;

/// Controls the camera of a `MapigradeMap`: create one, give it to the map
/// through its `cameraController`, and call it while the map is in the tree.
///
/// A controller is attached to the map it was given to while that map is in
/// the tree, and to at most one map at a time; giving it to a second map
/// while it is attached fails an assertion in debug builds. A camera command
/// on a controller that is not attached, or whose map isn't created yet or
/// couldn't be created, completes with a [StateError], and [camera] throws
/// one.
final class MapigradeCameraController {
  /// A controller to give to one `MapigradeMap`.
  MapigradeCameraController();

  Object? _owner;
  MapTextureController? _map;
  StreamSubscription<MapEvent>? _events;
  MapigradeCamera? _initial;
  MapigradeCamera? _displayed;
  int _nextRequest = 1;
  final _pending = <int, Completer<CameraTransitionOutcome>>{};
  // Asynchronous, because the map adds to them while it builds.
  final _changes = StreamController<CameraChange>.broadcast();
  final _rests = StreamController<MapigradeCamera>.broadcast();

  // The rest stream (design D243): the generation of the last settle report
  // that hasn't led to a rest, whether input still moves the camera, and the
  // generation of the displayed frame.
  int? _settledGeneration;
  bool _inputActive = false;
  int _displayedGeneration = 0;

  /// The camera of the frame that the map displayed in the last Flutter frame
  /// it built, with every field set, or the initial camera, with MapLibre's
  /// defaults for the fields it omits, before the first displayed frame.
  /// Throws a [StateError] when the controller is not attached.
  MapigradeCamera get camera {
    if (_owner == null) throw _detached();
    return _displayed ?? _completed(_initial!);
  }

  /// A [CameraChange] for each displayed frame whose camera differs from the
  /// previous displayed frame's.
  Stream<CameraChange> get cameraChanges => _changes.stream;

  /// The camera each time it comes to rest: when no gesture, glide, snap or
  /// camera transition moves it any more, and a frame that shows it has been
  /// displayed. Emits once per rest.
  Stream<MapigradeCamera> get rests => _rests.stream;

  /// Moves the camera to [camera] at once. Fields that [camera] leaves null
  /// keep their values. Completes with [CameraTransitionOutcome.completed]
  /// once the map has moved the camera.
  Future<CameraTransitionOutcome> jumpTo(MapigradeCamera camera) =>
      _command((map, id) => map.cameraCommand(id, 0, nativeCamera(camera)));

  /// Animates the camera straight to [camera] over [duration], or MapLibre's
  /// default duration. Fields that [camera] leaves null keep their values.
  Future<CameraTransitionOutcome> easeTo(
    MapigradeCamera camera, {
    Duration? duration,
  }) => _command(
    (map, id) => map.cameraCommand(
      id,
      1,
      nativeCamera(camera),
      durationMs: _milliseconds(duration),
    ),
  );

  /// Zooms out, travels to [camera] and zooms back in, over [duration] or a
  /// duration that MapLibre chooses from the distance. Fields that [camera]
  /// leaves null keep their values.
  Future<CameraTransitionOutcome> flyTo(
    MapigradeCamera camera, {
    Duration? duration,
  }) => _command(
    (map, id) => map.cameraCommand(
      id,
      2,
      nativeCamera(camera),
      durationMs: _milliseconds(duration),
    ),
  );

  /// Moves the camera so that [bounds] fills the widget less [padding], at
  /// [bearing] and [pitch] or at the current ones. Without [duration] the
  /// camera jumps; with it, it eases over [duration]. Padding that leaves no
  /// room for the bounds completes with [CameraTransitionOutcome.cancelled]
  /// and doesn't move the camera.
  Future<CameraTransitionOutcome> fitBounds(
    GeoBounds bounds, {
    EdgeInsets padding = EdgeInsets.zero,
    double? bearing,
    double? pitch,
    Duration? duration,
  }) => _command(
    (map, id) => map.fitBounds(
      id,
      duration == null ? 0 : 1,
      NativeFit(
        south: bounds.southWest.latitude,
        west: bounds.southWest.longitude,
        north: bounds.northEast.latitude,
        east: bounds.northEast.longitude,
        fields: 1 | (bearing != null ? 2 : 0) | (pitch != null ? 4 : 0),
        paddingTop: padding.top,
        paddingLeft: padding.left,
        paddingBottom: padding.bottom,
        paddingRight: padding.right,
        bearing: bearing ?? 0,
        pitch: pitch ?? 0,
      ),
      durationMs: _milliseconds(duration),
    ),
  );

  /// Stops every running camera transition where it is; their commands
  /// complete with [CameraTransitionOutcome.cancelled]. Throws a
  /// [StateError] when the controller is not attached.
  void cancelTransitions() {
    final map = _attachedMap();
    try {
      map.cancelTransitions();
    } on MapTextureDisposedException {
      throw _detached();
    }
  }

  Future<CameraTransitionOutcome> _command(
    void Function(MapTextureController map, int requestId) send,
  ) {
    final MapTextureController map;
    try {
      map = _attachedMap();
    } on StateError catch (e) {
      return Future.error(e);
    }
    final id = _nextRequest++;
    final completer = Completer<CameraTransitionOutcome>();
    _pending[id] = completer;
    try {
      send(map, id);
    } on MapTextureDisposedException {
      _pending.remove(id);
      return Future.error(_detached());
    } on MapTextureException catch (e) {
      _pending.remove(id);
      return Future.error(ArgumentError(e.message));
    }
    return completer.future;
  }

  MapTextureController _attachedMap() {
    final map = _map;
    if (_owner == null || map == null || map.isDisposed) throw _detached();
    return map;
  }

  StateError _detached() => StateError(
    _owner == null
        ? 'the MapigradeCameraController is not attached to a MapigradeMap in '
              'the tree'
        : 'the MapigradeMap of the MapigradeCameraController has no map',
  );

  void _onEvent(MapEvent event) {
    switch (event) {
      case CameraTransitionEnded(:final requestId, :final outcome):
        _pending.remove(requestId)?.complete(switch (outcome) {
          0 => CameraTransitionOutcome.completed,
          3 => CameraTransitionOutcome.replaced,
          _ => CameraTransitionOutcome.cancelled,
        });
      case CameraSettled(:final mapUpdateGeneration):
        _settledGeneration = mapUpdateGeneration;
        _maybeRest();
      default:
        break;
    }
  }

  void _maybeRest() {
    final settled = _settledGeneration;
    if (settled == null ||
        _inputActive ||
        _displayed == null ||
        _displayedGeneration < settled) {
      return;
    }
    _settledGeneration = null;
    _rests.add(_displayed!);
  }

  void _detach() {
    _events?.cancel();
    _events = null;
    _map = null;
    _owner = null;
    _displayed = null;
    _settledGeneration = null;
    _inputActive = false;
    for (final completer in _pending.values) {
      completer.complete(CameraTransitionOutcome.cancelled);
    }
    _pending.clear();
  }
}

double _milliseconds(Duration? duration) =>
    duration == null ? -1 : duration.inMicroseconds / 1000;

MapigradeCamera _completed(MapigradeCamera camera) => MapigradeCamera(
  center: camera.center ?? const LatLng(0, 0),
  centerAltitude: camera.centerAltitude ?? 0,
  zoom: camera.zoom ?? 0,
  bearing: camera.bearing ?? 0,
  pitch: camera.pitch ?? 0,
  roll: camera.roll ?? 0,
  fieldOfView: camera.fieldOfView ?? defaultFieldOfView,
  padding: camera.padding ?? EdgeInsets.zero,
);

/// The native camera of [camera], with the fields that it sets.
NativeCamera nativeCamera(MapigradeCamera camera) {
  final padding = camera.padding;
  return NativeCamera(
    fields:
        (camera.center != null ? 1 : 0) |
        (camera.zoom != null ? 2 : 0) |
        (camera.bearing != null ? 4 : 0) |
        (camera.pitch != null ? 8 : 0) |
        (camera.centerAltitude != null ? 16 : 0) |
        (padding != null ? 32 : 0) |
        (camera.roll != null ? 128 : 0) |
        (camera.fieldOfView != null ? 256 : 0),
    latitude: camera.center?.latitude ?? 0,
    longitude: camera.center?.longitude ?? 0,
    centerAltitude: camera.centerAltitude ?? 0,
    paddingTop: padding?.top ?? 0,
    paddingLeft: padding?.left ?? 0,
    paddingBottom: padding?.bottom ?? 0,
    paddingRight: padding?.right ?? 0,
    zoom: camera.zoom ?? 0,
    bearing: camera.bearing ?? 0,
    pitch: camera.pitch ?? 0,
    roll: camera.roll ?? 0,
    fieldOfView: camera.fieldOfView ?? 0,
  );
}

/// The camera of [frame], with every field. The center's longitude is wrapped
/// to [-180, 180).
MapigradeCamera frameCameraOf(FrameCamera frame) {
  final view = frame.view;
  final longitude = (frame.camera.longitude + 180) % 360 - 180;
  return MapigradeCamera(
    center: LatLng(frame.camera.latitude.clamp(-90.0, 90.0), longitude),
    centerAltitude: view?.centerAltitude ?? 0,
    zoom: frame.camera.zoom,
    bearing: frame.camera.bearing,
    pitch: view?.pitch ?? 0,
    roll: view?.roll ?? 0,
    fieldOfView: view?.fieldOfView ?? defaultFieldOfView,
    padding: view == null
        ? EdgeInsets.zero
        : EdgeInsets.fromLTRB(
            view.paddingLeft,
            view.paddingTop,
            view.paddingRight,
            view.paddingBottom,
          ),
  );
}

/// Attaches [controller] to the state [owner] of a `MapigradeMap` with the
/// initial camera [initial]. Fails an assertion if another map has it.
void bindCameraController(
  MapigradeCameraController controller,
  Object owner,
  MapigradeCamera initial,
) {
  assert(
    controller._owner == null || identical(controller._owner, owner),
    'a MapigradeCameraController can be given to one MapigradeMap at a time',
  );
  controller._owner = owner;
  controller._initial = initial;
}

/// Gives [controller] the map of [owner], once it has one.
void setCameraControllerMap(
  MapigradeCameraController controller,
  Object owner,
  MapTextureController map,
) {
  if (!identical(controller._owner, owner)) return;
  controller._events?.cancel();
  controller._map = map;
  controller._events = map.events.listen(controller._onEvent);
}

/// Tells [controller] that [owner] displays [frame] in the Flutter frame it
/// builds. Adds a [CameraChange] when the camera differs from the previous
/// displayed frame's.
void cameraControllerFrameDisplayed(
  MapigradeCameraController controller,
  Object owner,
  FrameCamera frame,
) {
  if (!identical(controller._owner, owner)) return;
  final camera = frameCameraOf(frame);
  final previous = controller._displayed;
  controller._displayed = camera;
  controller._displayedGeneration = frame.view?.mapUpdateGeneration ?? 0;
  if (previous != null && previous != camera) {
    final source = switch (frame.view?.cameraSource) {
      NativeCameraSource.gesture ||
      NativeCameraSource.momentum => CameraChangeSource.gesture,
      _ => CameraChangeSource.command,
    };
    controller._changes.add(CameraChange(camera, source));
  }
  controller._maybeRest();
}

/// Tells [controller] whether input of [owner] may still move the camera: a
/// pointer is down on the map, or the recognizer asks for a tick.
void cameraControllerInputActive(
  MapigradeCameraController controller,
  Object owner,
  bool active,
) {
  if (!identical(controller._owner, owner)) return;
  controller._inputActive = active;
  if (!active) controller._maybeRest();
}

/// Detaches [controller] from [owner], if [owner] has it. Pending commands
/// complete with [CameraTransitionOutcome.cancelled].
void releaseCameraController(
  MapigradeCameraController controller,
  Object owner,
) {
  if (identical(controller._owner, owner)) controller._detach();
}
