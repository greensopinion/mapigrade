// Whether the plugin's native library is available in this process, on
// platforms with FFI (design D86 of the unsupported-architectures change,
// D162 of web-build-compatibility).
import 'dart:ffi';
import 'dart:io';

/// Whether the native library is available in this process, so that the
/// bindings resolve. On Android the plugin loads the library unless the APK
/// lacks it for the device's ABIs; on macOS and iOS it is linked into the app.
final bool nativeLibraryAvailable = () {
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
