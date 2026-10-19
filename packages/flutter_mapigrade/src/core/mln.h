// Includes the MapLibre Native FFI C API and its callback adapter. On Apple
// platforms they come from the MaplibreNativeC framework; elsewhere from the
// plain include directory.
#pragma once

#if __has_include(<MaplibreNativeC/maplibre_native_c.h>)
#include <MaplibreNativeC/maplibre_native_c.h>
#include <MaplibreNativeC/maplibre_native_c/callback_adapter.h>
#else
#include <maplibre_native_c.h>
#include <maplibre_native_c/callback_adapter.h>
#endif
