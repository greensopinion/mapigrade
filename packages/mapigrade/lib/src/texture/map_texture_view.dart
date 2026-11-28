import 'dart:async';

import 'package:flutter/widgets.dart';

import 'map_texture_controller.dart';

/// Displays the map of [controller] in a `Texture` widget that fills the
/// available space.
///
/// The widget sends its logical size and the device pixel ratio to the
/// controller, so the map renders one pixel per physical pixel, and the
/// display's refresh rate, which decides when the map renders ahead.
///
/// With [slot], the view displays that display slot's texture, which the
/// caller has chosen with [MapTextureController.selectNewest]. Without it,
/// the view chooses the newest finished frame itself in each build and
/// displays the slot of [MapTextureController.selectedFrame], and rebuilds
/// when a frame has finished.
class MapTextureView extends StatefulWidget {
  /// A view of the map of [controller].
  const MapTextureView({super.key, required this.controller, this.slot});

  /// The controller of the map that the view displays.
  final MapTextureController controller;

  /// The display slot to show, an index into
  /// [MapTextureController.textureIds], or null for the view to choose.
  final int? slot;

  @override
  State<MapTextureView> createState() => _MapTextureViewState();
}

class _MapTextureViewState extends State<MapTextureView> {
  StreamSubscription<FrameCamera>? _readyFrames;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(MapTextureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) ||
        (widget.slot == null) != (oldWidget.slot == null)) {
      _readyFrames?.cancel();
      _readyFrames = null;
      _listen();
    }
  }

  void _listen() {
    if (widget.slot != null || widget.controller.isDisposed) return;
    _readyFrames = widget.controller.readyFrames.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _readyFrames?.cancel();
    super.dispose();
  }

  int _chooseSlot(MapTextureController controller) {
    if (!controller.isDisposed) controller.selectNewest();
    return controller.selectedFrame?.slot ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (!controller.isDisposed) {
      controller.setDisplayRefreshRate(View.of(context).display.refreshRate);
    }
    final slot = widget.slot ?? _chooseSlot(controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && !size.isEmpty && !controller.isDisposed) {
          controller.resize(size, pixelRatio);
        }
        return Texture(textureId: controller.textureIds[slot]);
      },
    );
  }
}
