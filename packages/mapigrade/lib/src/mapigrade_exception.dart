/// A failure of a `MapigradeLayer`'s map, passed to its `onError`, or for a
/// [MapigradeQueryException], to the `Future` of the failed query. Later versions
/// may add subclasses.
abstract final class MapigradeException implements Exception {
  /// A failure with [message].
  const MapigradeException(this.message);

  /// The cause of the failure.
  final String message;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is MapigradeException &&
      other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => '$_typeName: $message';

  String get _typeName;
}

/// Loading the style, or a resource that the style needs, failed.
final class MapigradeLoadException extends MapigradeException {
  /// A load failure with [message].
  const MapigradeLoadException(super.message);

  @override
  String get _typeName => 'MapigradeLoadException';
}

/// Rendering the map failed.
final class MapigradeRenderException extends MapigradeException {
  /// A render failure with [message].
  const MapigradeRenderException(super.message);

  @override
  String get _typeName => 'MapigradeRenderException';
}

/// The layer couldn't create its map.
final class MapigradeCreateException extends MapigradeException {
  /// A creation failure with [message].
  const MapigradeCreateException(super.message);

  @override
  String get _typeName => 'MapigradeCreateException';
}

/// A query of a `MapigradeController` failed, for example because MapLibre
/// rejected its filter.
final class MapigradeQueryException extends MapigradeException {
  /// A query failure with [message].
  const MapigradeQueryException(super.message);

  @override
  String get _typeName => 'MapigradeQueryException';
}
