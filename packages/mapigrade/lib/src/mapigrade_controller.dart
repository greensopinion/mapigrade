import 'dart:convert';
import 'dart:ui';

import '../texture/map_texture_controller.dart';
import 'camera_projection.dart';
import 'layer_exception.dart';
import 'queried_feature.dart';

/// Queries the features that the map of a `MapigradeLayer` renders, and sets
/// their feature state. Create one, give it to the layer's `controller`, and
/// call it while the layer is in the tree, for example from `flutter_map`'s
/// `MapOptions.onTap`:
///
/// ```dart
/// onTap: (position, _) async {
///   final features = await controller.queryRenderedFeatures(
///     position.relative!,
///     layerIds: ['poi'],
///   );
/// }
/// ```
///
/// A controller is attached to the layer it was given to while that layer is
/// in the tree, and to at most one layer at a time. Calls on a controller that
/// is not attached, or whose layer has no map because it isn't created yet or
/// couldn't be created, fail with a [StateError].
final class LayerController {
  /// A controller to give to one `MapigradeLayer`.
  LayerController();

  Object? _owner;
  MapTextureController? _map;
  ViewCamera Function()? _displayedCamera;

  /// The features that the displayed map frame draws within [radius] logical
  /// pixels of [point]: those whose rendered shape intersects the square of
  /// side `2 * radius` centered on [point], aligned with the screen axes.
  ///
  /// [point] is a logical position relative to the top-left corner of the
  /// `flutter_map` map widget, as `TapPosition.relative` gives it. The query
  /// looks where the map frame on screen draws the features, also while the
  /// camera moves. Labels and icons are an exception: MapLibre matches them
  /// where it placed them last, which can be behind the displayed frame while
  /// the camera moves.
  ///
  /// With [layerIds], only features drawn by those style layers are returned;
  /// IDs that the style doesn't contain are ignored. [filter] is a MapLibre
  /// style-spec filter expression as a JSON value, for example
  /// `['==', ['get', 'class'], 'primary']`. The results don't say which style
  /// layer drew each feature; to tell layers apart, query once per group of
  /// layer IDs.
  ///
  /// Completes with the features, those of the topmost style layer first, or
  /// with a [LayerQueryException] when MapLibre rejects the query. Queries
  /// complete in the order they were called. A negative [radius] throws an
  /// [ArgumentError].
  Future<List<QueriedFeature>> queryRenderedFeatures(
    Offset point, {
    double radius = 8,
    List<String>? layerIds,
    Object? filter,
  }) {
    if (!(radius >= 0) || !radius.isFinite) {
      throw ArgumentError.value(radius, 'radius', 'must be finite and >= 0');
    }
    return _query(
      Rect.fromCenter(center: point, width: 2 * radius, height: 2 * radius),
      layerIds,
      _encodeFilter(filter),
    );
  }

  /// The features that the displayed map frame draws in [rect], given in the
  /// coordinates of [queryRenderedFeatures]. A rectangle that extends past
  /// the viewport is clipped to it; one entirely outside it returns no
  /// features. See [queryRenderedFeatures] for [layerIds], [filter] and the
  /// result.
  Future<List<QueriedFeature>> queryRenderedFeaturesInRect(
    Rect rect, {
    List<String>? layerIds,
    Object? filter,
  }) => _query(rect, layerIds, _encodeFilter(filter));

  /// Sets the keys of [state] in the feature state of one feature, merging
  /// them with the keys it has. Style expressions that read
  /// `["feature-state", key]` then draw the feature accordingly, for example
  /// to highlight it:
  ///
  /// ```json
  /// "line-color": ["case", ["boolean", ["feature-state", "selected"], false],
  ///                "#e00", "#888"]
  /// ```
  ///
  /// The feature is selected by [sourceId], [sourceLayerId] for a source with
  /// layers, and [id], as a [QueriedFeature] gives them. [id] is an `int`, a
  /// `double` with an integral value, or a `String`. A feature without an ID
  /// can't take state; the source's `promoteId` in the style gives features
  /// IDs from one of their properties.
  ///
  /// Feature state belongs to the layer's map, not to its style: when the
  /// layer is given a different style, the state is kept and applies to the
  /// features of the new style with the same source ID, source-layer ID and
  /// ID, for example when switching between a light and a dark style.
  ///
  /// Returns without waiting for the map. A later displayed map frame shows
  /// the change, and a later query returns it. Throws an [ArgumentError] for
  /// an empty [sourceId], an [id] that is null or not as above, or a [state]
  /// that isn't encodable as JSON.
  void setFeatureState({
    required String sourceId,
    String? sourceLayerId,
    required Object? id,
    required Map<String, Object?> state,
  }) {
    _checkSourceId(sourceId);
    final featureId = _featureIdOf(id);
    final String stateJson;
    try {
      stateJson = jsonEncode(state);
    } on JsonUnsupportedObjectError catch (e) {
      throw ArgumentError.value(state, 'state', 'is not encodable as JSON: $e');
    }
    _call(
      (map) => map.setFeatureState(
        sourceId: sourceId,
        sourceLayerId: sourceLayerId,
        featureId: featureId,
        stateJson: stateJson,
      ),
    );
  }

  /// Removes feature state: the key [key] of the feature [id], all state of
  /// the feature [id] without [key], or the state of every feature of the
  /// source [sourceId], or of its source layer [sourceLayerId], without [id].
  /// See [setFeatureState] for how features are selected. Throws an
  /// [ArgumentError] for an empty [sourceId], an [id] that
  /// [setFeatureState] rejects, or a [key] without an [id].
  void removeFeatureState({
    required String sourceId,
    String? sourceLayerId,
    Object? id,
    String? key,
  }) {
    _checkSourceId(sourceId);
    if (key != null && id == null) {
      throw ArgumentError.value(key, 'key', 'needs an id');
    }
    final featureId = id == null ? null : _featureIdOf(id);
    _call(
      (map) => map.removeFeatureState(
        sourceId: sourceId,
        sourceLayerId: sourceLayerId,
        featureId: featureId,
        key: key,
      ),
    );
  }

  Future<List<QueriedFeature>> _query(
    Rect rect,
    List<String>? layerIds,
    String? filterJson,
  ) async {
    final map = _attachedMap();
    final camera = _displayedCamera!();
    final corners = [
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ])
        worldPosition(camera, corner),
    ];
    try {
      final entries = await map.queryRenderedFeatures(
        corners,
        layerIds: layerIds,
        filterJson: filterJson,
      );
      return [for (final entry in entries) queriedFeatureOf(entry)];
    } on MapTextureException catch (e) {
      throw LayerQueryException(e.message);
    } on MapTextureDisposedException {
      throw _detached();
    }
  }

  void _call(void Function(MapTextureController map) call) {
    final map = _attachedMap();
    try {
      call(map);
    } on MapTextureDisposedException {
      throw _detached();
    }
  }

  MapTextureController _attachedMap() {
    final map = _map;
    if (_owner == null || map == null || map.isDisposed) throw _detached();
    return map;
  }

  StateError _detached() => StateError(
    _owner == null
        ? 'the LayerController is not attached to a MapigradeLayer in the tree'
        : 'the MapigradeLayer of the LayerController has no map',
  );
}

void _checkSourceId(String sourceId) {
  if (sourceId.isEmpty) {
    throw ArgumentError.value(sourceId, 'sourceId', 'must not be empty');
  }
}

String? _encodeFilter(Object? filter) {
  if (filter == null) return null;
  try {
    return jsonEncode(filter);
  } on JsonUnsupportedObjectError catch (e) {
    throw ArgumentError.value(filter, 'filter', 'is not a JSON value: $e');
  }
}

/// The FFI's feature ID: the decimal text of a numeric ID.
String _featureIdOf(Object? id) => switch (id) {
  null => throw ArgumentError.value(
    id,
    'id',
    'is null: the feature has no ID. The source\'s promoteId in the style '
        'can give its features IDs',
  ),
  int() => id.toString(),
  double() when id.isFinite && id == id.truncateToDouble() => BigInt.from(
    id,
  ).toString(),
  String() => id,
  _ => throw ArgumentError.value(
    id,
    'id',
    'must be an int, a double with an integral value, or a String',
  ),
};

/// Attaches [controller] to the layer state [owner], which gives queries the
/// camera of its displayed map frame with [displayedCamera]. Fails an
/// assertion if another layer has it.
void bindLayerController(
  LayerController controller,
  Object owner,
  ViewCamera Function() displayedCamera,
) {
  assert(
    controller._owner == null || identical(controller._owner, owner),
    'a LayerController can be given to one MapigradeLayer at a time',
  );
  controller._owner = owner;
  controller._displayedCamera = displayedCamera;
}

/// Gives [controller] the map of its layer [owner], once the layer has one.
void setLayerControllerMap(
  LayerController controller,
  Object owner,
  MapTextureController map,
) {
  if (identical(controller._owner, owner)) controller._map = map;
}

/// Detaches [controller] from [owner], if [owner] has it.
void releaseLayerController(LayerController controller, Object owner) {
  if (!identical(controller._owner, owner)) return;
  controller._owner = null;
  controller._map = null;
  controller._displayedCamera = null;
}
