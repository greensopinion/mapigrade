// Includes the MapLibre Native FFI C API and its callback adapter. On Apple
// platforms they come from the MapLibreNativeC framework; elsewhere from the
// plain include directory.
#pragma once

#if __has_include(<MapLibreNativeC/maplibre_native_c.h>)
#include <MapLibreNativeC/maplibre_native_c.h>
#include <MapLibreNativeC/maplibre_native_c/callback_adapter.h>
#else
#include <maplibre_native_c.h>
#include <maplibre_native_c/callback_adapter.h>
#endif
