import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

import '../common/panel.dart';
import '../common/style_picker.dart';
import '../common/styles.dart';
import 'routes.dart';

/// The Financial District, between Broadway, Wall Street and West Street.
const _initialCenter = LatLng(40.7075, -74.0110);
const _initialZoom = 16.0;

/// The polyline showcase: routes through downtown New York drawn by
/// `MapigradePolylineLayer`, below the 3D buildings and labels or on top
/// (design D204).
class PolylineScreen extends StatefulWidget {
  const PolylineScreen({super.key});

  @override
  State<PolylineScreen> createState() => _PolylineScreenState();
}

class _PolylineScreenState extends State<PolylineScreen> {
  DemoStyle _style = demoStyles.first;
  LayerPlacement _placement = const LayerPlacement.belowLabels();

  /// Shows [exception] after the frame, because the layer can report a
  /// failure while it builds.
  void _showError(LayerException exception) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(exception.message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
            ),
            children: [
              MapigradeLayer(
                styleUrl: _style.url,
                onError: _showError,
                children: [
                  MapigradePolylineLayer(
                    polylines: demoRoutePolylines,
                    placement: _placement,
                  ),
                ],
              ),
              attributionOf(_style),
            ],
          ),
          DemoPanel(
            title: 'Polylines',
            children: [
              StylePicker(
                value: _style,
                onChanged: (style) => setState(() => _style = style),
              ),
              const SizedBox(height: 8),
              SegmentedButton<LayerPlacement>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LayerPlacement.belowLabels(),
                    label: Text('Below buildings and labels'),
                  ),
                  ButtonSegment(
                    value: LayerPlacement.top(),
                    label: Text('On top'),
                  ),
                ],
                selected: {_placement},
                onSelectionChanged: (selected) =>
                    setState(() => _placement = selected.single),
              ),
              const Divider(),
              for (final route in demoRoutes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _Swatch(route.polyline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${route.name}: ${route.drawnAs}',
                          style: small,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short sample of how [polyline] is drawn, for the legend.
class _Swatch extends StatelessWidget {
  const _Swatch(this.polyline);

  final MapigradePolyline polyline;

  @override
  Widget build(BuildContext context) {
    final gradient = polyline.gradientColors;
    return Container(
      width: 24,
      height: 6,
      decoration: BoxDecoration(
        color: gradient == null ? polyline.color : null,
        gradient: gradient == null ? null : LinearGradient(colors: gradient),
        border: polyline.borderStrokeWidth > 0
            ? Border.all(color: polyline.borderColor)
            : null,
      ),
    );
  }
}
