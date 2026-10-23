// Includes the MapLibre Native FFI C API. On Apple platforms it comes from the
// MaplibreNativeC framework; elsewhere from the plain include directory.
#pragma once

#if __has_include(<MaplibreNativeC/maplibre_native_c.h>)
#include <MaplibreNativeC/maplibre_native_c.h>
#else
#include <maplibre_native_c.h>
#endif
