/// Displays a MapLibre Native map as the base layer of a `flutter_map` map.
///
/// Place a [MapigradeLayer] first among the children of a `FlutterMap`, so
/// that the layers after it are drawn above it:
///
/// ```dart
/// FlutterMap(
///   options: const MapOptions(
///     initialCenter: LatLng(49.25, -123.1),
///     initialZoom: 11,
///   ),
///   children: [
///     MapigradeLayer(
///       styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
///       onError: (exception) => debugPrint('$exception'),
///     ),
///     MarkerLayer(
///       markers: [
///         Marker(
///           point: const LatLng(49.25, -123.1),
///           child: const Icon(Icons.place),
///         ),
///       ],
///     ),
///   ],
/// )
/// ```
library;

export 'src/layer/layer_alignment.dart' show LayerAlignment;
export 'src/layer/layer_exception.dart'
    show
        LayerCreateException,
        LayerException,
        LayerLoadException,
        LayerRenderException;
export 'src/layer/mapigrade_layer.dart' show MapigradeLayer;
