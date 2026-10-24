import 'dart:ffi';
import 'dart:io';

/// The value of `nativeLibraryAvailable` on platforms with FFI.
final bool nativeLibraryAvailable = () {
  try {
    if (Platform.isAndroid) {
      // Opening the library succeeds even where the plugin skipped it, so ask
      // whether the plugin initialized it.
      final initialized = DynamicLibrary.open('libflutter_mapigrade.so')
          .lookupFunction<Int32 Function(), int Function()>(
            'map_texture_android_initialized',
          );
      return initialized() != 0;
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process().providesSymbol('map_texture_create');
    }
    return false;
  } on ArgumentError {
    return false;
  }
}();
