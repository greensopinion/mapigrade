import '../texture/map_texture_controller.dart';
import '../texture/native_library.dart';

/// The settings of `mapigrade` that apply to every map in the process (design
/// D244).
abstract final class Mapigrade {
  /// Whether a map can be created in this process: false when the package's
  /// native library isn't available, for example on web or on an Android
  /// device with none of the ABIs `arm64-v8a`, `armeabi-v7a` and `x86_64`.
  /// Where it is false, a `MapigradeMap` reports a `MapigradeCreateException`,
  /// draws nothing and still builds its children.
  static bool get isSupported => nativeLibraryAvailable;

  /// The maximum size in bytes of the tile cache for maps created after it is
  /// set; 50 MiB by default. Each map evicts from the shared cache file to its
  /// own maximum size; after a reduction, the cache reaches the new maximum
  /// size as the map stores new tiles. The server's cache headers determine
  /// freshness. A negative value throws an [ArgumentError].
  static int get maximumCacheSizeBytes => _maximumCacheSizeBytes;

  static set maximumCacheSizeBytes(int bytes) {
    MapTextureController.setMaximumCacheSize(bytes);
    _maximumCacheSizeBytes = bytes;
  }

  static int _maximumCacheSizeBytes = 50 * 1024 * 1024;
}
