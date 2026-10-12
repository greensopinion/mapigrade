/// The `flutter_map` layer (designs D21 and D22 of the flutter-map-layer
/// change), its camera prediction (D31 to D33 of the camera-prediction
/// change), its alignment option (D43 of the camera-prediction-default
/// change, D47 of the remove-camera-transform change, which removed the
/// compensating transform of D23), and its callbacks and failure reports (D66
/// and D67 of the public-api change).
///
/// Only files in `lib/src/layer/` may import `package:flutter_map` (design
/// D9).
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import '../texture/map_texture_controller.dart';
import '../texture/map_texture_view.dart';
import 'camera_prediction.dart';
import 'camera_projection.dart';
import 'layer_alignment.dart';
import 'layer_exception.dart';

/// Creates the map of a [MapTextureLayer]; the signature of
/// [MapTextureController.create].
typedef MapTextureControllerFactory = MapTextureController Function({
  required double pixelRatio,
  required bool copyFree,
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
    this.copyFree = true,
    this.onController,
    this.createController,
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

  /// Whether the map renders directly into the displayed buffers (the
  /// default); see [MapTextureController.create]. Read when the layer creates
  /// its map. Has no effect on Android.
  final bool copyFree;

  /// Called with the layer's controller after it is created, for tests and
  /// measurements.
  final void Function(MapTextureController controller)? onController;

  /// Creates the map instead of [MapTextureController.create], so that a test
  /// can make creation fail.
  final MapTextureControllerFactory? createController;

  @override
  State<MapTextureLayer> createState() => _MapTextureLayerState();
}

class _MapTextureLayerState extends State<MapTextureLayer> {
  MapTextureController? _controller;
  bool _createFailed = false;
  // The messages of the load failures reported since the last style load.
  final Set<String> _loadFailures = {};
  StreamSubscription<FrameCamera>? _frames;
  StreamSubscription<MapEvent>? _events;
  ViewCamera? _sentCamera;
  CameraPredictor _predictor = CameraPredictor();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || _createFailed) return;
    // On Android the first frames can come before the window's metrics, with
    // an empty size and a device pixel ratio of 1. The map's pixel ratio is
    // fixed at creation, so the map is created when the metrics have arrived,
    // which runs this method again.
    if (MediaQuery.sizeOf(context).isEmpty) return;
    final create = widget.createController ?? MapTextureController.create;
    final MapTextureController controller;
    try {
      controller = create(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
        copyFree: widget.copyFree,
      );
    } on MapTextureException catch (e) {
      // Not retried while the layer is in the tree, so that the failure is
      // reported once (design D67).
      _createFailed = true;
      _report(LayerCreateException(e.message));
      return;
    }
    _controller = controller;
    _events = controller.events.listen(_onEvent);
    // With camera prediction, the rebuild after a new displayed frame, once
    // the camera has stopped, finds the camera unchanged and sets the
    // converted camera instead of the last predicted one (design D32).
    _frames = controller.frames.listen((_) => setState(() {}));
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
  // new callback takes effect for the next event (design D67).
  void _onEvent(MapEvent event) {
    switch (event) {
      case StyleLoaded():
        widget.onStyleLoaded?.call();
      // MapLibre retries a request that failed to connect, and reports each
      // failed attempt with the same message (design D67).
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
    _events?.cancel();
    _frames?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      // While creation has failed, the layer occupies the viewport without
      // drawing anything (design D67).
      if (_createFailed) {
        return SizedBox.fromSize(size: fm.MapCamera.of(context).nonRotatedSize);
      }
      return const SizedBox.shrink();
    }
    final target = viewCameraOf(fm.MapCamera.of(context));
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
    // map thread (design D22).
    if (camera != _sentCamera && !camera.viewport.isEmpty) {
      controller.setCamera(camera.camera);
      _sentCamera = camera;
    }

    return SizedBox.fromSize(
      size: target.viewport,
      child: ClipRect(child: MapTextureView(controller: controller)),
    );
  }
}
