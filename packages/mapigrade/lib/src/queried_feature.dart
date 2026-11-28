/// A feature that the map renders where a query of a `LayerController`
/// looked.
final class QueriedFeature {
  /// A feature with the given values, for example to test code that handles
  /// query results.
  const QueriedFeature({
    this.id,
    this.properties = const {},
    this.geometry = const {},
    required this.sourceId,
    this.sourceLayerId,
    this.state = const {},
  });

  /// The feature's ID: an `int`, a `double` or a `String`, or null when the
  /// feature has none. Vector tiles have integer IDs; an ID of 2^63 or more
  /// is a `double` and loses precision, so it can't select the feature in
  /// `LayerController.setFeatureState`.
  final Object? id;

  /// The feature's properties. Values are `String`, `num`, `bool`, null,
  /// `List<Object?>` or `Map<String, Object?>`.
  final Map<String, Object?> properties;

  /// The feature's geometry as a GeoJSON geometry object, for example
  /// `{"type": "LineString", "coordinates": [[lon, lat], ...]}`. Positions
  /// are longitude first. For a feature of a vector tile, the geometry is
  /// clipped to the tile, so a line that crosses tiles is returned once per
  /// tile.
  final Map<String, Object?> geometry;

  /// The ID of the style source that contains the feature.
  final String sourceId;

  /// The source layer that contains the feature, or null for a source without
  /// layers, such as a GeoJSON source.
  final String? sourceLayerId;

  /// The feature's feature state, empty when none is set.
  final Map<String, Object?> state;

  @override
  String toString() =>
      'QueriedFeature(id: $id, source: $sourceId'
      '${sourceLayerId == null ? '' : '/$sourceLayerId'}, '
      'properties: $properties)';
}

/// The feature of one entry of a query result, as the native side encodes it:
/// `feature` (a GeoJSON Feature), `source`, `sourceLayer` and `state`.
QueriedFeature queriedFeatureOf(Map<String, Object?> entry) {
  final feature = entry['feature'] as Map<String, Object?>? ?? const {};
  return QueriedFeature(
    id: feature['id'],
    properties: feature['properties'] as Map<String, Object?>? ?? const {},
    geometry: feature['geometry'] as Map<String, Object?>? ?? const {},
    sourceId: entry['source'] as String? ?? '',
    sourceLayerId: entry['sourceLayer'] as String?,
    state: entry['state'] as Map<String, Object?>? ?? const {},
  );
}
