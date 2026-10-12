// The flutter_map layer (design D21).
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import '../texture/map_texture_controller.dart';
import '../texture/map_texture_view.dart';
import 'camera_alignment.dart';
import 'camera_prediction.dart';
import 'camera_projection.dart';

/// Displays a MapLibre map as the base layer of a `FlutterMap`, at the
/// `FlutterMap` camera. Place it first among the map's children, so that the
/// layers after it are drawn above it.
///
/// The layer creates its map when it is inserted and disposes it when it is
/// removed. By default it sets the map camera predicted one display refresh
/// interval ahead while the camera moves, so that the map displayed then is
/// close to the overlays; [alignment] selects how the layer aligns the map
/// with the overlays during camera changes.
class MapLibreTextureLayer extends StatefulWidget {
  const MapLibreTextureLayer({
    super.key,
    this.styleUrl,
    this.styleJson,
    this.copyFree = true,
    this.onController,
    this.alignment = const CameraAlignment.prediction(),
  }) : assert(
         (styleUrl == null) != (styleJson == null),
         'give exactly one of styleUrl and styleJson',
       );

  final String? styleUrl;
  final String? styleJson;

  /// Whether the map renders directly into the displayed buffers (the
  /// default); see [MapTextureController.create]. Read when the layer creates
  /// its map.
  final bool copyFree;

  /// Called with the layer's controller after it is created, for tests and
  /// measurements.
  final void Function(MapTextureController controller)? onController;

  /// How the layer aligns the map with the overlays while the camera
  /// changes; see [CameraAlignment]. Defaults to camera prediction with a
  /// lead of 1 display refresh interval.
  final CameraAlignment alignment;

  @override
  State<MapLibreTextureLayer> createState() => _MapLibreTextureLayerState();
}

class _MapLibreTextureLayerState extends State<MapLibreTextureLayer> {
  MapTextureController? _controller;
  StreamSubscription<FrameCamera>? _frames;
  ViewCamera? _sentCamera;
  CameraPredictor _predictor = CameraPredictor();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = MapTextureController.create(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      copyFree: widget.copyFree,
    );
    _controller = controller;
    // With camera prediction, the rebuild after a new displayed frame, once
    // the camera has stopped, finds the camera unchanged and sets the
    // converted camera instead of the last predicted one (design D32).
    _frames = controller.frames.listen((_) => setState(() {}));
    _loadStyle();
    widget.onController?.call(controller);
  }

  @override
  void didUpdateWidget(MapLibreTextureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.styleUrl != oldWidget.styleUrl ||
        widget.styleJson != oldWidget.styleJson) {
      _loadStyle();
    }
    if (widget.alignment != oldWidget.alignment) {
      _predictor = CameraPredictor();
    }
  }

  void _loadStyle() {
    final controller = _controller!;
    if (widget.styleUrl case final url?) {
      controller.loadStyleUrl(url);
    } else {
      controller.loadStyleJson(widget.styleJson!);
    }
  }

  @override
  void dispose() {
    _frames?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
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
