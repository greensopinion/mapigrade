// The flutter_map layer (design D21).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import '../texture/map_texture_controller.dart';
import '../texture/map_texture_view.dart';
import 'camera_transform.dart';

/// Displays a MapLibre map as the base layer of a `FlutterMap`, at the
/// `FlutterMap` camera. Place it first among the map's children, so that the
/// layers after it are drawn above it.
///
/// The layer creates its map when it is inserted and disposes it when it is
/// removed. Until the map has displayed a frame for the current camera, the
/// layer moves the last displayed frame to where the current camera places it
/// (design D23).
class MapLibreTextureLayer extends StatefulWidget {
  const MapLibreTextureLayer({
    super.key,
    this.styleUrl,
    this.styleJson,
    this.onController,
  }) : assert(
         (styleUrl == null) != (styleJson == null),
         'give exactly one of styleUrl and styleJson',
       );

  final String? styleUrl;
  final String? styleJson;

  /// Called with the layer's controller after it is created, for tests and
  /// measurements.
  final void Function(MapTextureController controller)? onController;

  @override
  State<MapLibreTextureLayer> createState() => _MapLibreTextureLayerState();
}

class _MapLibreTextureLayerState extends State<MapLibreTextureLayer> {
  MapTextureController? _controller;
  StreamSubscription<FrameCamera>? _frames;
  ViewCamera? _sentCamera;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = MapTextureController.create(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    _controller = controller;
    // A new displayed frame changes the transform.
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
    // Setting the camera here instead of after the frame starts the render
    // about one frame earlier; setCamera only stores the camera and wakes the
    // map thread (design D22).
    if (target != _sentCamera && !target.viewport.isEmpty) {
      controller.setCamera(target.camera);
      _sentCamera = target;
    }

    Widget texture = MapTextureView(controller: controller);
    final frame = controller.displayedFrame;
    final transform = frame == null
        ? null
        : layerTransform(ViewCamera.ofFrame(frame), target);
    if (transform != null) {
      texture = Transform(transform: transform, child: texture);
    }
    return SizedBox.fromSize(
      size: target.viewport,
      child: ClipRect(child: texture),
    );
  }
}
