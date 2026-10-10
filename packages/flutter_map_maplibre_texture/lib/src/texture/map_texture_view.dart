import 'package:flutter/widgets.dart';

import 'map_texture_controller.dart';

/// Displays the map of [controller] in a `Texture` widget that fills the
/// available space.
///
/// The widget sends its logical size and the device pixel ratio to the
/// controller, so the map renders one pixel per physical pixel.
class MapTextureView extends StatelessWidget {
  const MapTextureView({super.key, required this.controller});

  final MapTextureController controller;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isFinite && !size.isEmpty && !controller.isDisposed) {
        controller.resize(size, pixelRatio);
      }
      return Texture(textureId: controller.textureId);
    });
  }
}
