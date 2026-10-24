import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

/// A feature and the ID of the style layer that draws it.
typedef Selection = ({String layerId, QueriedFeature feature});

/// The selected feature of a tap and the tap's other features, which
/// [onSelect] selects (design D194).
class FeatureDetails extends StatelessWidget {
  const FeatureDetails({
    super.key,
    required this.selection,
    this.hits = const [],
    this.symbolLayerIds = const {},
    this.onSelect,
  });

  final Selection? selection;

  /// Every feature at the tap, topmost style layer first.
  final List<Selection> hits;

  /// The style layers whose features MapLibre Native returns without feature
  /// state.
  final Set<String> symbolLayerIds;
  final ValueChanged<Selection>? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall!;
    final bold = small.copyWith(fontWeight: FontWeight.bold);
    final selection = this.selection;
    if (selection == null) {
      return Text('No feature selected.', style: small);
    }
    final feature = selection.feature;
    final properties = feature.properties.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final others = [
      for (final hit in hits)
        if (hit != selection) hit,
    ];
    TableRow row(String key, String value, {TextStyle? keyStyle}) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 2),
          child: Text(key, style: keyStyle ?? bold),
        ),
        SelectableText(value, style: small),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          columnWidths: const {0: IntrinsicColumnWidth()},
          children: [
            row('Style layer', selection.layerId),
            row('Source', feature.sourceId),
            row('Source layer', feature.sourceLayerId ?? 'none'),
            row('ID', feature.id?.toString() ?? 'none'),
            row('Geometry', describeGeometry(feature.geometry)),
            row(
              'State',
              symbolLayerIds.contains(selection.layerId)
                  ? 'not returned for labels and icons'
                  : feature.state.isEmpty
                  ? 'none'
                  : jsonEncode(feature.state),
            ),
          ],
        ),
        if (feature.id == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This feature has no ID, so it can\'t be highlighted.',
              style: small.copyWith(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Text('Properties', style: bold),
        if (properties.isEmpty) Text('none', style: small),
        Table(
          columnWidths: const {0: IntrinsicColumnWidth()},
          children: [
            for (final MapEntry(:key, :value) in properties)
              row(
                key,
                value is String ? value : jsonEncode(value),
                keyStyle: small.copyWith(fontStyle: FontStyle.italic),
              ),
          ],
        ),
        if (others.isNotEmpty) ...[
          const Divider(),
          Text('Also at the tap', style: bold),
          for (final hit in others)
            InkWell(
              onTap: onSelect == null ? null : () => onSelect!(hit),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${hit.layerId}  ·  '
                        '${hit.feature.sourceLayerId ?? hit.feature.sourceId}'
                        '  ·  ${hit.feature.id ?? 'no ID'}',
                        style: small,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The type of a GeoJSON [geometry], with the number of parts of a multi
/// geometry, for example "MultiPolygon, 655 polygons".
String describeGeometry(Map<String, Object?> geometry) {
  final type = geometry['type'];
  if (type is! String) return 'none';
  final coordinates = geometry['coordinates'];
  final part = switch (type) {
    'MultiPoint' => 'point',
    'MultiLineString' => 'line',
    'MultiPolygon' => 'polygon',
    _ => null,
  };
  if (part == null || coordinates is! List) return type;
  final n = coordinates.length;
  return '$type, $n ${n == 1 ? part : '${part}s'}';
}
