import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:mapigrade/src/texture/map_texture_controller.dart';

/// A map controller without a native map, which records the camera commands
/// and gesture calls and lets a test send events.
class FakeMapController implements MapTextureController {
  final _events = StreamController<MapEvent>.broadcast(sync: true);
  final _readyFrames = StreamController<FrameCamera>.broadcast(sync: true);
  final styles = <String>[];
  final sizes = <Size>[];
  final overlayLayers = <(int, String)>[];
  final overlaySources = <(int, int)>[];
  final queries = <List<Offset>>[];
  List<Map<String, Object?>> queryResult = const [];
  FrameCamera? _ready;
  FrameCamera? _selected;

  /// Finishes [frame], which the next selectNewest chooses.
  void finish(FrameCamera frame) {
    _ready = frame;
    _readyFrames.add(frame);
  }

  final commands = <(int, int, NativeCamera, double)>[];
  final fits = <(int, int, NativeFit, double)>[];
  final limits = <NativeLimits>[];
  final gestureOptions = <NativeGestureOptions>[];
  final inputs = <GestureInput>[];
  int cancels = 0;
  bool _disposed = false;

  /// The result of each [handleGesture], or the default result.
  GestureResult Function(GestureInput input, double timeMs) onGesture = (
    _,
    _,
  ) => const GestureResult(handled: true);
  GestureResult Function(double timeMs) onTick = (_) => const GestureResult();

  void send(MapEvent event) => _events.add(event);

  @override
  Stream<MapEvent> get events => _events.stream;

  @override
  bool get isDisposed => _disposed;

  @override
  List<int> get textureIds => const [1, 2, 3, 4];

  @override
  Stream<FrameCamera> get readyFrames => _readyFrames.stream;

  @override
  Stream<FrameCamera> get frames => const Stream.empty();

  @override
  FrameCamera? get selectedFrame => _selected;

  @override
  FrameCamera? selectNewest() {
    final ready = _ready;
    if (ready == null || identical(ready, _selected)) return null;
    return _selected = ready;
  }

  @override
  void loadStyleUrl(String url) => styles.add(url);

  @override
  void loadStyleJson(String json) => styles.add(json);

  @override
  void resize(Size logicalSize, double pixelRatio) => sizes.add(logicalSize);

  @override
  void setDisplayRefreshRate(double hz) {}

  @override
  void setOverlayLayers(
    int overlayId, {
    required String layersJson,
    required int placementKind,
    String? belowLayerId,
    required int orderChild,
    required int orderSeq,
  }) => overlayLayers.add((overlayId, layersJson));

  @override
  void setOverlaySource(
    int overlayId,
    int sourceIndex,
    Uint8List geoJson, {
    required bool lineMetrics,
  }) => overlaySources.add((overlayId, sourceIndex));

  @override
  Future<void> setOverlaySourceInBackground(
    int overlayId,
    int sourceIndex,
    Uint8List Function() encode, {
    required bool lineMetrics,
  }) async => overlaySources.add((overlayId, sourceIndex));

  @override
  void removeOverlay(int overlayId) {}

  @override
  void removeOverlaySource(int overlayId, int sourceIndex) {}

  @override
  Future<List<Map<String, Object?>>> queryRenderedFeatures(
    List<Offset> worldCorners, {
    List<String>? layerIds,
    String? filterJson,
  }) async {
    queries.add(worldCorners);
    return queryResult;
  }

  @override
  void cameraCommand(
    int requestId,
    int mode,
    NativeCamera camera, {
    double durationMs = -1,
  }) {
    if (_disposed) throw const MapTextureDisposedException();
    commands.add((requestId, mode, camera, durationMs));
  }

  @override
  void fitBounds(
    int requestId,
    int mode,
    NativeFit fit, {
    double durationMs = -1,
  }) => fits.add((requestId, mode, fit, durationMs));

  @override
  void cancelTransitions() => cancels++;

  @override
  void setLimits(NativeLimits value) => limits.add(value);

  @override
  void createGestureRecognizer(NativeGestureOptions options) =>
      gestureOptions.add(options);

  @override
  void setGestureOptions(NativeGestureOptions options) =>
      gestureOptions.add(options);

  @override
  GestureResult handleGesture(GestureInput input, double timeMs) {
    inputs.add(input);
    return onGesture(input, timeMs);
  }

  @override
  GestureResult tickGesture(double timeMs) => onTick(timeMs);

  @override
  void dispose() {
    _disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A frame with [camera] fields, the [source] of its camera, and the map
/// update [generation].
FrameCamera fakeFrame({
  int id = 1,
  double latitude = 0,
  double longitude = 0,
  double zoom = 3,
  double bearing = 0,
  double pitch = 0,
  NativeCameraSource source = NativeCameraSource.command,
  int generation = 1,
  Float64List? matrix,
  Size logicalSize = const Size(400, 300),
}) => FrameCamera(
  frameId: id,
  camera: MapCamera(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    bearing: bearing,
  ),
  physicalSize: logicalSize * 2,
  scaleFactor: 2,
  displayTime: null,
  slot: id % 4,
  view: FrameView(
    pitch: pitch,
    centerAltitude: 0,
    paddingTop: 0,
    paddingLeft: 0,
    paddingBottom: 0,
    paddingRight: 0,
    roll: 0,
    fieldOfView: 36.86989764584402,
    matrix: matrix ?? Float64List(16),
    clipDepthRange: 1,
    cameraSource: source,
    mapUpdateGeneration: generation,
  ),
);
