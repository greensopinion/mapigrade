import 'dart:ffi';
import 'dart:io';

/// The value of `nativeLibraryAvailable` on platforms with FFI.
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
