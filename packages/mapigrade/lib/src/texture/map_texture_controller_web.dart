// The map controller's platform functions on web, which has no native library.
// They aren't reached: MapTextureController.create and
// MapTextureController.setMaximumCacheSize return before they call them,
// because nativeLibraryAvailable is false on web unless a test overrides it.
import 'map_texture_controller.dart';

/// Not reached on web; see the comment at the top of this file.
Future<MapTextureController> createMapTextureController({
  required double pixelRatio,
  required bool copyFree,
  required List<HeaderRule> httpHeaders,
}) => throw StateError('flutter_mapigrade has no native library on web');

/// Not reached on web; see the comment at the top of this file.
void setMaximumCacheSize(int bytes) =>
    throw StateError('flutter_mapigrade has no native library on web');
