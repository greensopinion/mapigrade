import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

import '../common/panel.dart';
import '../common/style_picker.dart';
import '../common/styles.dart';
import 'feature_panel.dart';
import 'style_patch.dart';

/// The old town of Nice, where roads, buildings and labels are close together.
const _initialCenter = LatLng(43.6967, 7.2747);
const _initialZoom = 16.0;

/// The inspect showcase: a tap queries the features at the tap, highlights
/// the topmost one with feature state and shows its details (design D193).
class InspectScreen extends StatefulWidget {
  const InspectScreen({super.key});

  @override
  State<InspectScreen> createState() => _InspectScreenState();
}

class _InspectScreenState extends State<InspectScreen> {
  final _layerController = LayerController();

  /// The style that the picker shows, and the style whose JSON the layer
  /// shows; they differ while a fetch runs.
  DemoStyle _style = demoStyles.first;
  DemoStyle? _shown;
  final _styles = <DemoStyle, HighlightStyle>{};
  String? _failure;
  Selection? _selected;

  /// Every feature at the last tap, topmost style layer first.
  List<Selection> _hits = const [];
  Offset? _tap;

  @override
  void initState() {
    super.initState();
    _load(_style);
  }

  Future<void> _load(DemoStyle style) async {
    setState(() => _style = style);
    if (!_styles.containsKey(style)) {
      try {
        _styles[style] = await fetchHighlightStyle(Uri.parse(style.url));
      } on Exception catch (e) {
        if (!mounted || _style != style) return;
        _showMessage('${style.name} couldn\'t be loaded: $e');
        setState(() {
          _failure = _shown == null ? '$e' : null;
          _style = _shown ?? style;
        });
        return;
      }
    }
    if (!mounted || _style != style) return;
    setState(() {
      _shown = style;
      _failure = null;
    });
  }

  /// Queries each of the style's own layers, because MapLibre Native doesn't
  /// return the features of several layers in style order (design D193).
  Future<void> _onTap(TapPosition tap, LatLng point) async {
    final position = tap.relative;
    final style = _shown;
    if (position == null || style == null) return;
    final layerIds = _styles[style]!.layerIds;
    final List<List<QueriedFeature>> results;
    try {
      results = await Future.wait([
        for (final id in layerIds)
          _layerController.queryRenderedFeatures(position, layerIds: [id]),
      ]);
    } on LayerQueryException catch (e) {
      _showMessage(e.message);
      return;
    } on StateError {
      // The layer has no map yet.
      return;
    }
    if (!mounted) return;
    _tap = position;
    _hits = [
      for (final (i, features) in results.indexed)
        for (final feature in features)
          (layerId: layerIds[i], feature: feature),
    ];
    _select(_hits.firstOrNull);
  }

  /// Deselects with `selected: false` rather than removing the state, because
  /// MapLibre Native drops one of a removal and a change in one source layer
  /// that reach the same render (design D193).
  void _select(Selection? selection) {
    final previous = _selected?.feature;
    if (previous != null) _setSelected(previous, false);
    final feature = selection?.feature;
    if (feature != null) _setSelected(feature, true);
    setState(() => _selected = selection);
    if (selection != null) _readBack(selection);
  }

  /// Replaces [selection] with the feature that a new query of its layer
  /// returns, so that the panel shows the state read back from the map; the
  /// query that selected it ran before the state was set (design D194).
  Future<void> _readBack(Selection selection) async {
    final tap = _tap;
    final feature = selection.feature;
    if (tap == null || feature.id == null) return;
    final List<QueriedFeature> features;
    try {
      features = await _layerController.queryRenderedFeatures(
        tap,
        layerIds: [selection.layerId],
      );
    } on Exception {
      return;
    } on StateError {
      return;
    }
    if (!mounted || _selected != selection) return;
    final updated = features
        .where(
          (f) =>
              f.sourceId == feature.sourceId &&
              f.sourceLayerId == feature.sourceLayerId &&
              f.id == feature.id,
        )
        .firstOrNull;
    if (updated == null) return;
    final refreshed = (layerId: selection.layerId, feature: updated);
    setState(() {
      _hits = [for (final hit in _hits) hit == selection ? refreshed : hit];
      _selected = refreshed;
    });
  }

  void _setSelected(QueriedFeature feature, bool selected) {
    if (feature.id == null) return;
    try {
      _layerController.setFeatureState(
        sourceId: feature.sourceId,
        sourceLayerId: feature.sourceLayerId,
        id: feature.id,
        state: {'selected': selected},
      );
    } on ArgumentError catch (e) {
      _showMessage('${e.message}');
    }
  }

  /// Shows [message] after the frame, because the layer can report a failure
  /// while it builds.
  void _showMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    final failure = _failure;
    return Scaffold(
      body: Stack(
        children: [
          if (shown != null)
            FlutterMap(
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _initialZoom,
                onTap: _onTap,
              ),
              children: [
                MapigradeLayer(
                  styleJson: _styles[shown]!.json,
                  controller: _layerController,
                  onError: (e) => _showMessage(e.message),
                ),
                attributionOf(shown),
              ],
            )
          else if (failure != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(failure, textAlign: TextAlign.center),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          DemoPanel(
            title: 'Inspect features',
            children: [
              StylePicker(value: _style, onChanged: _load),
              Text(
                'Tap the map to select the topmost feature at the tap.',
                style: theme.textTheme.bodySmall,
              ),
              const Divider(),
              FeatureDetails(
                selection: _selected,
                hits: _hits,
                symbolLayerIds: shown == null
                    ? const {}
                    : _styles[shown]!.symbolLayerIds,
                onSelect: _select,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
