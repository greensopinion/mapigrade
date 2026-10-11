import 'package:flutter/widgets.dart';

import 'map_texture_controller.dart';

/// Displays the map of [controller] in a `Texture` widget that fills the
/// available space.
///
/// The widget sends its logical size and the device pixel ratio to the
/// controller, so the map renders one pixel per physical pixel, and the
/// display's refresh rate, which decides when the map renders ahead.
class MapTextureView extends StatelessWidget {
  const MapTextureView({super.key, required this.controller});

  final MapTextureController controller;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (!controller.isDisposed) {
      controller.setDisplayRefreshRate(View.of(context).display.refreshRate);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isFinite && !size.isEmpty && !controller.isDisposed) {
        controller.resize(size, pixelRatio);
      }
      return Texture(textureId: controller.textureId);
    });
  }
}
