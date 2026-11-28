import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../camera_projection.dart';
import '../http_header_rule.dart';
import '../mapigrade_controller.dart';
import '../mapigrade_exception.dart';
import '../mapigrade_metrics.dart';
import '../overlay_host.dart';
import '../texture/map_texture_controller.dart';
import '../texture/map_texture_view.dart';
import 'camera.dart';
import 'gestures/map_gesture_adapter.dart';
import 'gestures/mapigrade_gestures.dart';
import 'mapigrade_camera_controller.dart';
import 'mapigrade_frame.dart';

/// Creates the map of a [MapigradeMap]: [MapTextureController.create] with a
/// map that owns its camera.
typedef MapigradeMapCreate = Future<MapTextureController> Function({
  required double pixelRatio,
  required List<HttpHeaderRule> httpHeaders,
  required NativeCamera initialCamera,
  required NativeLimits limits,
});

/// For tests: when not null, a [MapigradeMap] creates its map with this.
@visibleForTesting
MapigradeMapCreate? debugCreateMapigradeMap;

Future<MapTextureController> _create({
  required double pixelRatio,
  required List<HttpHeaderRule> httpHeaders,
  required NativeCamera initialCamera,
  required NativeLimits limits,
}) => MapTextureController.create(
  pixelRatio: pixelRatio,
  httpHeaders: [
    for (final rule in httpHeaders) (url: rule.url, headers: rule.headers),
  ],
  initialCamera: initialCamera,
  limits: limits,
);

/// The native limits of [limits].
NativeLimits nativeLimits(CameraLimits limits) => NativeLimits(
  minZoom: limits.minZoom,
  maxZoom: limits.maxZoom,
  minPitch: limits.minPitch,
  maxPitch: limits.maxPitch,
  hasBounds: limits.bounds != null,
  south: limits.bounds?.southWest.latitude ?? 0,
  west: limits.bounds?.southWest.longitude ?? 0,
  north: limits.bounds?.northEast.latitude ?? 0,
  east: limits.bounds?.northEast.longitude ?? 0,
);

/// Displays a MapLibre map in its full size. MapLibre owns the camera: the
/// map starts at [initialCamera], within [limits], and gestures and the
/// commands of [cameraController] move it.
///
/// [children] are drawn above the map. They read the frame that the map
/// displays with [MapigradeFrame.of], and a `MapigradeMarkers` among them
/// places widgets at coordinates. A `MapigradePolylineLayer` among them gives
/// the map polylines to draw.
final class MapigradeMap extends StatefulWidget {
  /// A map that displays the style at [styleUrl] or the style [styleJson].
  const MapigradeMap({
    super.key,
    this.styleUrl,
    this.styleJson,
    required this.initialCamera,
    this.limits,
    this.gestures = const MapigradeGestures(),
    this.controller,
    this.cameraController,
    this.httpHeaders = const [],
    this.metrics,
    this.onStyleLoaded,
    this.onError,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.hapticFeedback = true,
    this.children = const [],
  }) : assert(
         (styleUrl == null) != (styleJson == null),
         'give exactly one of styleUrl and styleJson',
       );

  /// The URL of the style. In this URL and in every URL in the style,
  /// `asset://<asset key>` refers to the Flutter asset with that key.
  /// Rebuilding the map with another style keeps the camera.
  final String? styleUrl;

  /// The style as JSON.
  final String? styleJson;

  /// The camera that the map starts at. Fields that it leaves null get
  /// MapLibre's defaults. Read when the map is created.
  final MapigradeCamera initialCamera;

  /// The limits of the camera, or the defaults of [CameraLimits]. Rebuilding
  /// the map with other limits moves a camera outside them to the nearest
  /// camera within them.
  final CameraLimits? limits;

  /// Which gestures move the camera.
  final MapigradeGestures gestures;

  /// Queries the map's features and sets their feature state while the map
  /// is in the tree.
  final MapigradeController? controller;

  /// Moves the camera, and reports it, while the map is in the tree.
  final MapigradeCameraController? cameraController;

  /// Headers for the map's requests; read when the map is created.
  final List<HttpHeaderRule> httpHeaders;

  /// Reports the frame counts of the map.
  final MapigradeMetrics? metrics;

  /// Called each time the map has loaded a style.
  final VoidCallback? onStyleLoaded;

  /// Called with each failure of the map: a [MapigradeLoadException], a
  /// [MapigradeRenderException], or a [MapigradeCreateException] when the map
  /// can't be created, as where `Mapigrade.isSupported` is false. When null,
  /// failures are reported through [FlutterError.reportError].
  final void Function(MapigradeException exception)? onError;

  /// Called for a tap that the map's gesture recognizer recognized. While
  /// [MapigradeGestures.doubleTapZoom] is on, it is called once a second tap
  /// is ruled out, and a double tap doesn't call it.
  final void Function(MapigradeTap tap)? onTap;

  /// Called for a press held still for 500 ms.
  final void Function(MapigradeTap tap)? onLongPress;

  /// Called for a click of the right mouse button without a drag.
  final void Function(MapigradeTap tap)? onSecondaryTap;

  /// Whether gestures that move the bearing to or across north play the
  /// platform's selection feedback on iOS and Android.
  final bool hapticFeedback;

  /// Drawn above the map.
  final List<Widget> children;

  @override
  State<MapigradeMap> createState() => MapigradeMapState();
}

class _ControllerSink implements GestureSink {
  _ControllerSink(this.map);

  final MapTextureController map;

  @override
  GestureResult handle(GestureInput input, double timeMs) =>
      map.isDisposed ? const GestureResult() : map.handleGesture(input, timeMs);

  @override
  GestureResult tick(double timeMs) =>
      map.isDisposed ? const GestureResult() : map.tickGesture(timeMs);
}

/// The state of a [MapigradeMap].
class MapigradeMapState extends State<MapigradeMap> {
  MapTextureController? _map;
  bool _creating = false;
  bool _createFailed = false;
  final Set<String> _loadFailures = {};
  late final OverlayHost _host = OverlayHost(report: _report);
  StreamSubscription<FrameCamera>? _readyFrames;
  StreamSubscription<MapEvent>? _events;
  final _frameNotifier = ValueNotifier<MapigradeFrame?>(null);
  MapigradeFrame? _frame;
  int? _frameId;
  Size _size = Size.zero;
  GestureSink? _sink;
  final _boxZoom = ValueNotifier<Rect?>(null);

  /// The map, once it is created.
  MapTextureController? get map => _map;

  /// The frame displayed in the last build, or null.
  MapigradeFrame? get displayedFrame => _frame;

  CameraLimits get _limits => widget.limits ?? CameraLimits();

  @override
  void initState() {
    super.initState();
    if (widget.controller case final controller?) {
      bindControllerWithWorld(controller, this, _worldOf);
    }
    if (widget.cameraController case final controller?) {
      bindCameraController(controller, this, widget.initialCamera);
    }
  }

  // The normalized Web Mercator point at [position] on the displayed frame,
  // which queries convert positions with. Before the first frame, the initial
  // camera without its pitch.
  Offset? _worldOf(Offset position) {
    if (_frame case final frame?) return frame.worldOf(position);
    final camera = widget.initialCamera;
    final center = camera.center;
    if (center == null) return null;
    return worldPosition(
      ViewCamera(
        MapCamera(
          latitude: center.latitude,
          longitude: center.longitude,
          zoom: camera.zoom ?? 0,
          bearing: camera.bearing ?? 0,
        ),
        _size,
      ),
      position,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_map != null || _creating || _createFailed) return;
    // On Android the first frames can come before the window's metrics, with
    // an empty size and a device pixel ratio of 1. The map's pixel ratio is
    // fixed at creation, so the map is created when the metrics arrive.
    if (MediaQuery.sizeOf(context).isEmpty) return;
    _creating = true;
    _createMap(MediaQuery.devicePixelRatioOf(context));
  }

  Future<void> _createMap(double pixelRatio) async {
    final create = debugCreateMapigradeMap ?? _create;
    final MapTextureController map;
    try {
      map = await create(
        pixelRatio: pixelRatio,
        httpHeaders: widget.httpHeaders,
        initialCamera: nativeCamera(widget.initialCamera),
        limits: nativeLimits(_limits),
      );
    } on MapTextureException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _createFailed = true;
      });
      _report(MapigradeCreateException(e.message));
      return;
    }
    if (!mounted) {
      map.dispose();
      return;
    }
    setState(() {
      _creating = false;
      _map = map;
    });
    if (widget.controller case final controller?) {
      setControllerMap(controller, this, map);
    }
    if (widget.cameraController case final controller?) {
      setCameraControllerMap(controller, this, map);
    }
    if (widget.metrics case final metrics?) bindMetrics(metrics, map);
    _events = map.events.listen(_onEvent);
    _readyFrames = map.readyFrames.listen((_) => setState(() {}));
    _loadStyle();
    _host.attach(map);
    try {
      map.createGestureRecognizer(
        nativeGestureOptions(widget.gestures, defaultTargetPlatform),
      );
      _sink = _ControllerSink(map);
    } on MapTextureException catch (e) {
      _report(MapigradeCreateException('gesture recognizer: ${e.message}'));
    }
  }

  @override
  void didUpdateWidget(MapigradeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final map = _map;
    if (map != null &&
        (widget.styleUrl != oldWidget.styleUrl ||
            widget.styleJson != oldWidget.styleJson)) {
      _loadStyle();
    }
    if (_sink != null && widget.gestures != oldWidget.gestures) {
      map!.setGestureOptions(
        nativeGestureOptions(widget.gestures, defaultTargetPlatform),
      );
    }
    if (map != null && widget.limits != oldWidget.limits) {
      map.setLimits(nativeLimits(_limits));
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      if (oldWidget.controller case final old?) releaseController(old, this);
      if (widget.controller case final controller?) {
        bindControllerWithWorld(controller, this, _worldOf);
        if (map != null) setControllerMap(controller, this, map);
      }
    }
    if (!identical(widget.cameraController, oldWidget.cameraController)) {
      if (oldWidget.cameraController case final old?) {
        releaseCameraController(old, this);
      }
      if (widget.cameraController case final controller?) {
        bindCameraController(controller, this, widget.initialCamera);
        if (map != null) setCameraControllerMap(controller, this, map);
      }
    }
    if (map != null && !identical(widget.metrics, oldWidget.metrics)) {
      if (oldWidget.metrics case final old?) releaseMetrics(old, map);
      if (widget.metrics case final metrics?) bindMetrics(metrics, map);
    }
  }

  void _loadStyle() {
    final map = _map!;
    _loadFailures.clear();
    if (widget.styleUrl case final url?) {
      map.loadStyleUrl(url);
    } else {
      map.loadStyleJson(widget.styleJson!);
    }
  }

  void _onEvent(MapEvent event) {
    switch (event) {
      case StyleLoaded():
        widget.onStyleLoaded?.call();
      // MapLibre retries a request that failed to connect, and reports each
      // failed attempt with the same message.
      case LoadingFailed(:final message):
        if (_loadFailures.add(message)) {
          _report(MapigradeLoadException(message));
        }
      case RenderError(:final message):
        _report(MapigradeRenderException(message));
      case MapIdle() || CameraTransitionEnded() || CameraSettled():
        break;
    }
  }

  void _report(MapigradeException exception) {
    if (widget.onError case final onError?) {
      onError(exception);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: exception,
        library: 'mapigrade',
        context: ErrorDescription('while displaying the MapigradeMap map'),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.controller case final controller?) {
      releaseController(controller, this);
    }
    if (widget.cameraController case final controller?) {
      releaseCameraController(controller, this);
    }
    _host.detach();
    _events?.cancel();
    _readyFrames?.cancel();
    if (_map case final map?) {
      if (widget.metrics case final metrics?) releaseMetrics(metrics, map);
      map.dispose();
    }
    _frameNotifier.dispose();
    _boxZoom.dispose();
    super.dispose();
  }

  // Chooses the newest finished frame for this build, and tells the camera
  // controller and the frame's listeners about a new one.
  FrameCamera? _chooseFrame(MapTextureController map) {
    if (!map.isDisposed) map.selectNewest();
    final chosen = map.selectedFrame;
    if (chosen != null && chosen.frameId != _frameId) {
      _frameId = chosen.frameId;
      _frame = MapigradeFrameInternals.fromFrame(chosen) ?? _frame;
      _frameNotifier.value = _frame;
      if (widget.cameraController case final controller?) {
        cameraControllerFrameDisplayed(controller, this, chosen);
      }
    }
    return chosen;
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    final chosen = map == null ? null : _chooseFrame(map);
    final children = Positioned.fill(
      child: MapigradeFrameScope(
        frame: _frame,
        listenable: _frameNotifier,
        child: OverlayHostScope(
          host: _host,
          child: Stack(
            children: [
              for (var i = 0; i < widget.children.length; i++)
                OverlayChildIndex(
                  key: switch (widget.children[i].key) {
                    final LocalKey key => ValueKey(key),
                    _ => null,
                  },
                  index: i,
                  child: widget.children[i],
                ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return MapGestureAdapter(
          sink: _sink,
          gestures: widget.gestures,
          frame: () => _frame,
          boxZoom: _boxZoom,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          hapticFeedback: widget.hapticFeedback,
          onActiveChanged: (active) {
            if (widget.cameraController case final controller?) {
              cameraControllerInputActive(controller, this, active);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always present, so that the children's elements keep their
              // place in the Stack when the map is created.
              Positioned.fill(
                child: map == null
                    ? const SizedBox()
                    : ClipRect(
                        child: MapTextureView(
                          controller: map,
                          slot: chosen?.slot ?? 0,
                        ),
                      ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<Rect?>(
                    valueListenable: _boxZoom,
                    builder: (context, box, _) =>
                        CustomPaint(painter: _BoxZoomPainter(box)),
                  ),
                ),
              ),
              children,
            ],
          ),
        );
      },
    );
  }
}

// The rectangle of a box zoom (design D245).
class _BoxZoomPainter extends CustomPainter {
  _BoxZoomPainter(this.box);

  final Rect? box;

  @override
  void paint(Canvas canvas, Size size) {
    final box = this.box;
    if (box == null) return;
    canvas.drawRect(box, Paint()..color = const Color(0x33000000));
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xCC000000),
    );
  }

  @override
  bool shouldRepaint(_BoxZoomPainter oldDelegate) => box != oldDelegate.box;
}
