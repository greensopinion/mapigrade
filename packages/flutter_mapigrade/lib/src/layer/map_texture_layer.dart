/// Only files in `lib/src/layer/` may import `package:flutter_map`.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
// flutter_map doesn't export MapInheritedModel, which its layers read the
// camera from. This is the only file that imports it; a test builds it, so
// that a flutter_map release that changes it fails the tests.
// ignore: implementation_imports
import 'package:flutter_map/src/map/inherited_model.dart';

import '../texture/map_texture_controller.dart';
import '../texture/map_texture_view.dart';
import 'camera_prediction.dart';
import 'camera_projection.dart';
import 'http_header_rule.dart';
import 'layer_alignment.dart';
import 'layer_controller.dart';
import 'layer_exception.dart';
import 'layer_metrics.dart';

/// Creates the map of a [MapTextureLayer]; the signature of
/// [MapTextureController.create], with [HttpHeaderRule]s.
typedef MapTextureControllerFactory = Future<MapTextureController> Function({
  required double pixelRatio,
  required bool copyFree,
  required List<HttpHeaderRule> httpHeaders,
});

/// The widget that `MapigradeLayer` builds, with the parameters that only
/// tests and measurements use. See `MapigradeLayer` for the parameters they
/// share.
class MapTextureLayer extends StatefulWidget {
  /// A layer that displays the style at [styleUrl] or the style [styleJson].
  const MapTextureLayer({
    super.key,
    this.styleUrl,
    this.styleJson,
    this.alignment = const LayerAlignment.prediction(),
    this.onStyleLoaded,
    this.onError,
    this.httpHeaders = const [],
    this.copyFree = true,
    this.metrics,
    this.children = const [],
    this.controller,
    this.onController,
    this.createController,
    this.onChildCamera,
  }) : assert(
         (styleUrl == null) != (styleJson == null),
         'give exactly one of styleUrl and styleJson',
       );

  /// The URL of the style.
  final String? styleUrl;

  /// The style as JSON.
  final String? styleJson;

  /// How the layer aligns the map with the overlays while the camera
  /// changes; see [LayerAlignment].
  final LayerAlignment alignment;

  /// Called each time a style has loaded.
  final VoidCallback? onStyleLoaded;

  /// Called with each failure of the map. When null, the layer reports the
  /// failure through [FlutterError.reportError].
  final void Function(LayerException exception)? onError;

  /// Read when the layer creates its map.
  final List<HttpHeaderRule> httpHeaders;

  /// Whether the map renders directly into the displayed buffers (the
  /// default); see [MapTextureController.create]. Read when the layer creates
  /// its map. Has no effect on Android.
  final bool copyFree;

  /// Reports the frame counts of the layer's map.
  final LayerMetrics? metrics;

  /// Drawn above the map at the `flutter_map` camera of the displayed map
  /// frame.
  final List<Widget> children;

  /// Queries the layer's map and sets its feature state while the layer is
  /// in the tree.
  final LayerController? controller;

  /// Called with the layer's controller after it is created, for tests and
  /// measurements.
  final void Function(MapTextureController controller)? onController;

  /// Creates the map instead of [MapTextureController.create], so that a test
  /// can make creation fail.
  final MapTextureControllerFactory? createController;

  /// Called in each build with the id of the map frame the layer chose, or
  /// null if it chose none, and the camera it gives [children], for tests and
  /// measurements.
  final void Function(int? frameId, fm.MapCamera camera)? onChildCamera;

  @override
  State<MapTextureLayer> createState() => _MapTextureLayerState();
}

Future<MapTextureController> _createController({
  required double pixelRatio,
  required bool copyFree,
  required List<HttpHeaderRule> httpHeaders,
}) => MapTextureController.create(
  pixelRatio: pixelRatio,
  copyFree: copyFree,
  httpHeaders: [
    for (final rule in httpHeaders) (url: rule.url, headers: rule.headers),
  ],
);

const _sentCameraCount = 32;

class _MapTextureLayerState extends State<MapTextureLayer> {
  MapTextureController? _controller;
  bool _creating = false;
  bool _createFailed = false;
  final Set<String> _loadFailures = {};
  StreamSubscription<FrameCamera>? _frames;
  StreamSubscription<FrameCamera>? _readyFrames;
  StreamSubscription<MapEvent>? _events;
  ViewCamera? _sentCamera;
  CameraPredictor _predictor = CameraPredictor();
  // The flutter_map camera of each of the last sent cameras, by sequence
  // number, oldest first.
  final _sentCameras = <int, fm.MapCamera>{};
  // The live flutter_map camera of the last build.
  fm.MapCamera? _live;

  @override
  void initState() {
    super.initState();
    if (widget.controller case final controller?) {
      bindLayerController(controller, this, _displayedCamera);
    }
  }

  // The camera of the map frame that the last build displayed, which
  // queries convert positions with.
  ViewCamera _displayedCamera() {
    if (_controller?.selectedFrame case final frame?) {
      return ViewCamera.ofFrame(frame);
    }
    return viewCameraOf(_live ?? fm.MapCamera.of(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || _creating || _createFailed) return;
    // On Android the first frames can come before the window's metrics, with
    // an empty size and a device pixel ratio of 1. The map's pixel ratio is
    // fixed at creation, so the map is created when the metrics have arrived,
    // which runs this method again.
    if (MediaQuery.sizeOf(context).isEmpty) return;
    _creating = true;
    _create(MediaQuery.devicePixelRatioOf(context));
  }

  Future<void> _create(double pixelRatio) async {
    final create = widget.createController ?? _createController;
    final MapTextureController controller;
    try {
      controller = await create(
        pixelRatio: pixelRatio,
        copyFree: widget.copyFree,
        httpHeaders: widget.httpHeaders,
      );
    } on MapTextureException catch (e) {
      if (!mounted) return;
      // Not retried while the layer is in the tree, so that the failure is
      // reported once.
      setState(() {
        _creating = false;
        _createFailed = true;
      });
      _report(LayerCreateException(e.message));
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _creating = false;
      _controller = controller;
    });
    if (widget.controller case final layerController?) {
      setLayerControllerMap(layerController, this, controller);
    }
    if (widget.metrics case final metrics?) bindMetrics(metrics, controller);
    _events = controller.events.listen(_onEvent);
    // With camera prediction, the rebuild after a new displayed frame, once
    // the camera has stopped, finds the camera unchanged and sets the
    // converted camera instead of the last predicted one.
    _frames = controller.frames.listen((_) => setState(() {}));
    // Each finished frame starts a build, which chooses the newest finished
    // frame.
    _readyFrames = controller.readyFrames.listen((_) => setState(() {}));
    _loadStyle();
    widget.onController?.call(controller);
  }

  @override
  void didUpdateWidget(MapTextureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null &&
        (widget.styleUrl != oldWidget.styleUrl ||
            widget.styleJson != oldWidget.styleJson)) {
      _loadStyle();
    }
    if (widget.alignment != oldWidget.alignment) {
      _predictor = CameraPredictor();
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      if (oldWidget.controller case final old?) {
        releaseLayerController(old, this);
      }
      if (widget.controller case final controller?) {
        bindLayerController(controller, this, _displayedCamera);
        if (_controller case final map?) {
          setLayerControllerMap(controller, this, map);
        }
      }
    }
    if (_controller case final controller?
        when !identical(widget.metrics, oldWidget.metrics)) {
      if (oldWidget.metrics case final old?) releaseMetrics(old, controller);
      if (widget.metrics case final metrics?) bindMetrics(metrics, controller);
    }
  }

  void _loadStyle() {
    final controller = _controller!;
    _loadFailures.clear();
    if (widget.styleUrl case final url?) {
      controller.loadStyleUrl(url);
    } else {
      controller.loadStyleJson(widget.styleJson!);
    }
  }

  // The callbacks are read from the current widget, so that a rebuild with a
  // new callback takes effect for the next event.
  void _onEvent(MapEvent event) {
    switch (event) {
      case StyleLoaded():
        widget.onStyleLoaded?.call();
      // MapLibre retries a request that failed to connect, and reports each
      // failed attempt with the same message.
      case LoadingFailed(:final message):
        if (_loadFailures.add(message)) _report(LayerLoadException(message));
      case RenderError(:final message):
        _report(LayerRenderException(message));
      case MapIdle():
        break;
    }
  }

  void _report(LayerException exception) {
    if (widget.onError case final onError?) {
      onError(exception);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: exception,
        library: 'flutter_mapigrade',
        context: ErrorDescription('while displaying the MapigradeLayer map'),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.controller case final controller?) {
      releaseLayerController(controller, this);
    }
    _events?.cancel();
    _frames?.cancel();
    _readyFrames?.cancel();
    if (_controller case final controller?) {
      if (widget.metrics case final metrics?) {
        releaseMetrics(metrics, controller);
      }
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      if (_createFailed) {
        return SizedBox.fromSize(size: fm.MapCamera.of(context).nonRotatedSize);
      }
      return const SizedBox.shrink();
    }
    final live = fm.MapCamera.of(context);
    _live = live;
    final target = viewCameraOf(live);
    final lead = widget.alignment.lead;
    var camera = target;
    if (lead != null) {
      final refreshRate = View.of(context).display.refreshRate;
      camera = _predictor.predict(
        target,
        SchedulerBinding.instance.currentSystemFrameTimeStamp,
        lead / (refreshRate > 0 ? refreshRate : 60),
      );
    }
    // Setting the camera here instead of after the frame starts the render
    // about one frame earlier; setCamera only stores the camera and wakes the
    // map thread.
    if (camera != _sentCamera && !camera.viewport.isEmpty) {
      final seq = controller.setCamera(camera.camera);
      _sentCamera = camera;
      _sentCameras[seq] = camera == target
          ? live
          : flutterMapCameraOf(camera.camera, live);
      while (_sentCameras.length > _sentCameraCount) {
        _sentCameras.remove(_sentCameras.keys.first);
      }
    }

    // The map chooses its newest finished frame, which can be newer than the
    // last frame reported to Dart.
    controller.selectNewest();
    final chosen = controller.selectedFrame;
    // A chosen frame without a sent camera was rendered before the first
    // setCamera; any other miss is a bug.
    final childCamera =
        (chosen == null ? null : _sentCameras[chosen.seq]) ?? live;
    widget.onChildCamera?.call(chosen?.frameId, childCamera);

    return SizedBox.fromSize(
      size: target.viewport,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: MapTextureView(
                controller: controller,
                slot: chosen?.slot ?? 0,
              ),
            ),
          ),
          if (widget.children.isNotEmpty)
            // Positioned.fill gives the inner Stack the viewport's size, and
            // the inner Stack gives its children the loose constraints that
            // FlutterMap's Stack gives its children.
            Positioned.fill(
              child: MapInheritedModel(
                camera: childCamera,
                controller: fm.MapController.of(context),
                options: fm.MapOptions.of(context),
                child: Stack(children: widget.children),
              ),
            ),
        ],
      ),
    );
  }
}
