import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../layer/layer_placement.dart';
import '../layer/overlay_host.dart';
import 'mapigrade_polyline.dart';
import 'polyline_translation.dart';

/// The number of points above which the GeoJSON of the polylines is encoded
/// and prepared on a background isolate.
const polylineBackgroundPointThreshold = 20000;

/// Polylines that the map of the `MapigradeLayer` above it draws among the
/// style's own layers.
///
/// Place it in the `children` of a `MapigradeLayer`, at any depth below a
/// child. It draws nothing in Flutter. The map draws the polylines in its
/// frames, so they are exactly where the frame draws their coordinates and
/// below every Flutter child of the `MapigradeLayer`, whatever the polyline
/// layer's position in `children`. [placement] sets where they go among the
/// style's layers. Polyline layers with the same placement are drawn in the
/// order of `children`: a later one is drawn above an earlier one.
///
/// A polyline layer that isn't below a `MapigradeLayer` fails an assertion in
/// debug builds and draws nothing in release builds. While the map doesn't
/// exist or couldn't be created, the polyline layer does nothing; when the map
/// is created, it draws the polylines that the layer has then.
///
/// To switch from `flutter_map`'s `PolylineLayer`, change the class name and
/// turn each `Polyline` into a [MapigradePolyline]. `PolylineLayer`'s
/// culling, simplification and hit-test parameters have no counterpart: the
/// map doesn't hit test polylines. Translucent polylines that overlap are
/// darker where they overlap, because MapLibre blends each polyline with
/// what is below it, where `PolylineLayer` composites translucent polylines
/// through one saved layer.
///
/// When the layer is rebuilt with an equal list of equal polylines, it sends
/// nothing to the map. Otherwise it sends the polylines again, the polylines
/// with a gradient apart from the others, and a change in one group doesn't
/// send the other. Put polylines that change and polylines that don't in
/// separate polyline layers, so that a change doesn't send the others again.
/// Keep polylines with the same `strokeCap` and `dashes` next to each other
/// in [polylines]: such polylines share style layers, and alternating them
/// adds style layers.
///
/// With more than 20,000 points in all, the layer encodes the polylines and
/// the map prepares them on a background isolate, and an update that arrives
/// meanwhile replaces the one waiting, so the map can draw a change a few
/// frames after the rebuild. The polylines with a gradient are prepared on a
/// background isolate of their own.
final class MapigradePolylineLayer extends StatefulWidget {
  /// A layer that draws [polylines] at [placement].
  const MapigradePolylineLayer({
    super.key,
    required this.polylines,
    this.placement = const LayerPlacement.belowLabels(),
  });

  /// The polylines, drawn in list order: a later polyline is drawn above an
  /// earlier one in the same layer.
  final List<MapigradePolyline> polylines;

  /// Where the polylines go among the style's layers.
  final LayerPlacement placement;

  @override
  State<MapigradePolylineLayer> createState() => _MapigradePolylineLayerState();
}

Uint8List Function() _geoJsonEncoder(List<PolylineFeature> features) =>
    () => polylineGeoJson(features);

class _MapigradePolylineLayerState extends State<MapigradePolylineLayer> {
  OverlayRegistration? _registration;
  List<PolylineRun> _runs = const [];
  String _layersJson = '[]';
  final _sentFeatures = <PolylineSource, List<PolylineFeature>>{};

  @override
  void initState() {
    super.initState();
    final host = OverlayHostScope.maybeOf(context);
    assert(
      host != null,
      'a MapigradePolylineLayer must be below a MapigradeLayer',
    );
    _registration = host?.register(
      childIndex: OverlayChildIndex.of(context, listen: false),
    );
    _send();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registration?.childIndex = OverlayChildIndex.of(context);
  }

  @override
  void didUpdateWidget(MapigradePolylineLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final polylinesChanged =
        !identical(widget.polylines, oldWidget.polylines) &&
        !listEquals(widget.polylines, oldWidget.polylines);
    if (polylinesChanged) {
      _send();
    } else if (widget.placement != oldWidget.placement) {
      _registration?.setLayers(_layersJson, widget.placement);
    }
  }

  void _send() {
    final registration = _registration;
    if (registration == null) return;
    final polylines = widget.polylines;
    final runs = polylineRuns(polylines);
    if (!listEquals(runs, _runs)) {
      _runs = runs;
      _layersJson = polylineLayersJson(registration.ids, runs);
    }
    var points = 0;
    for (final polyline in polylines) {
      points += polyline.points.length;
    }
    final sources = polylineSources(runs);
    for (final source in sources) {
      final features = polylineFeatures(polylines, source);
      if (listEquals(features, _sentFeatures[source])) continue;
      _sentFeatures[source] = features;
      registration.setSource(
        source.index,
        _geoJsonEncoder(features),
        lineMetrics: source.lineMetrics,
        inBackground: points > polylineBackgroundPointThreshold,
      );
    }
    registration.setLayers(_layersJson, widget.placement);
    for (final source in PolylineSource.values) {
      if (sources.contains(source)) continue;
      _sentFeatures.remove(source);
      registration.removeSource(source.index);
    }
  }

  @override
  void dispose() {
    _registration?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
