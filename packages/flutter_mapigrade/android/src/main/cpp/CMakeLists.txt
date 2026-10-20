# libflutter_mapigrade.so: the shared core in src/core/ and the Android render
# target, linked against the MapLibre Native FFI library libmaplibre-native-c.so.
# In release mode CMake finds the library and its headers through the Prefab
# module of the FFI runtime AAR. In local mode android/build.gradle.kts sets
# MLN_FFI_LIBRARY_DIR, which holds <abi>/libmaplibre-native-c.so, and
# MLN_FFI_INCLUDE_DIR, which holds the FFI headers.
cmake_minimum_required(VERSION 3.22)
project(flutter_mapigrade CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../src/core)
set(MLN_FFI_LIBRARY_DIR "" CACHE PATH "Directory with <abi>/libmaplibre-native-c.so")
set(MLN_FFI_INCLUDE_DIR "" CACHE PATH "Directory with maplibre_native_c.h")

if(MLN_FFI_LIBRARY_DIR)
  add_library(maplibre_native_c SHARED IMPORTED)
  set_target_properties(maplibre_native_c PROPERTIES
    IMPORTED_LOCATION ${MLN_FFI_LIBRARY_DIR}/${ANDROID_ABI}/libmaplibre-native-c.so
    INTERFACE_INCLUDE_DIRECTORIES ${MLN_FFI_INCLUDE_DIR})
else()
  find_package(maplibre-native-c REQUIRED CONFIG)
  add_library(maplibre_native_c ALIAS maplibre-native-c::maplibre-native-c)
endif()

add_library(flutter_mapigrade SHARED
  ${CORE_DIR}/map_texture.cpp
  ${CORE_DIR}/map_texture_api.cpp
  map_texture_android.cpp)
target_include_directories(flutter_mapigrade PRIVATE ${CORE_DIR})
target_compile_options(flutter_mapigrade PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(flutter_mapigrade PRIVATE maplibre_native_c android EGL GLESv3 log)
