// Whether the plugin's native library is available in this process (design
// D86 of the unsupported-architectures change).
import 'dart:ffi';
import 'dart:io';

/// For tests: when not null, [nativeLibraryAvailable] returns this value
/// (design D87).
bool? nativeLibraryAvailableOverride;

/// Whether the native library is available in this process, so that the
/// bindings resolve. On Android the plugin loads the library unless the APK
/// lacks it for the device's ABIs; on macOS and iOS it is linked into the app.
bool get nativeLibraryAvailable =>
    nativeLibraryAvailableOverride ?? _nativeLibraryAvailable;

final bool _nativeLibraryAvailable = () {
  try {
    if (Platform.isAndroid) {
      // Returns the copy that the plugin loaded, if it loaded it.
      DynamicLibrary.open('libflutter_mapigrade.so');
      return true;
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process().providesSymbol('map_texture_create');
    }
    return false;
  } on ArgumentError {
    return false;
  }
}();
