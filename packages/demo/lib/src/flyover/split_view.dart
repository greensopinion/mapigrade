import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// The demo's Android application ID, which the OpenStreetMap tile usage
/// policy requires as the user agent (design D198).
const _userAgentPackageName = 'com.greensopinion.mapigrade_demo';

/// The height of the attribution button, 56 on touch platforms, plus a gap.
const _labelBottom = 64.0;

/// The gap between the seam line and each label.
const _labelGap = 6.0;

/// OpenStreetMap's standard raster tiles (design D198).
TileLayer osmTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: _userAgentPackageName,
  maxNativeZoom: 19,
);

/// [child] clipped to the right half of the map's viewport (design D196).
class RightHalf extends StatelessWidget {
  const RightHalf({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox.fromSize(
      size: constraints.biggest,
      child: ClipRect(clipper: const RightHalfClipper(), child: child),
    ),
  );
}

class RightHalfClipper extends CustomClipper<Rect> {
  const RightHalfClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width / 2, 0, size.width, size.height);

  @override
  bool shouldReclip(RightHalfClipper oldClipper) => false;
}

/// The seam line and the labels of the two halves, in screen coordinates
/// (design D197).
class SplitSeam extends StatelessWidget {
  const SplitSeam({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom + _labelBottom;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final center = size.width / 2;
          return SizedBox.fromSize(
            size: size,
            child: Stack(
              children: [
                Positioned(
                  left: center - 0.5,
                  width: 1,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: theme.colorScheme.onSurface),
                ),
                Positioned(
                  right: size.width - center + _labelGap,
                  bottom: bottom,
                  child: const _Label('Mapigrade'),
                ),
                Positioned(
                  left: center + _labelGap,
                  bottom: bottom,
                  child: const _Label('Raster (OSM)'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A label in the panel's colors, so that it reads on light and dark maps.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: theme.textTheme.bodySmall!.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
