import 'native_library_ffi.dart'
    if (dart.library.js_interop) 'native_library_web.dart'
    as platform;

/// For tests: when not null, [nativeLibraryAvailable] returns this value.
bool? nativeLibraryAvailableOverride;

/// Whether the native library is available in this process, so that the
/// bindings resolve. On Android the plugin loads and initializes the library
/// from API level 29 when the APK has it for the device's ABIs; on macOS and
/// iOS it is linked into the app.
/// Always false on web.
bool get nativeLibraryAvailable =>
    nativeLibraryAvailableOverride ?? platform.nativeLibraryAvailable;
