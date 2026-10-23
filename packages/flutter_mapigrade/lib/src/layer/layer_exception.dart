/// A failure of a `MapigradeLayer`'s map, passed to its `onError`. Later
/// versions may add subclasses.
abstract final class LayerException implements Exception {
  /// A failure with [message].
  const LayerException(this.message);

  /// The cause of the failure.
  final String message;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is LayerException &&
      other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => '$_typeName: $message';

  String get _typeName;
}

/// Loading the style, or a resource that the style needs, failed.
final class LayerLoadException extends LayerException {
  /// A load failure with [message].
  const LayerLoadException(super.message);

  @override
  String get _typeName => 'LayerLoadException';
}

/// Rendering the map failed.
final class LayerRenderException extends LayerException {
  /// A render failure with [message].
  const LayerRenderException(super.message);

  @override
  String get _typeName => 'LayerRenderException';
}

/// The layer couldn't create its map.
final class LayerCreateException extends LayerException {
  /// A creation failure with [message].
  const LayerCreateException(super.message);

  @override
  String get _typeName => 'LayerCreateException';
}
