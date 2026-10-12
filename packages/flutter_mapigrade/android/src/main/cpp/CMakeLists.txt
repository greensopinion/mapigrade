# libflutter_mapigrade.so: the shared core in src/core/ and the Android render
# target, linked against the MapLibre Native FFI preset in MLN_FFI_DIR.
cmake_minimum_required(VERSION 3.22)
project(flutter_mapigrade CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../src/core)
set(MLN_FFI_DIR "" CACHE PATH "Install directory of the android-arm64-egl FFI preset")

add_library(maplibre_native_c SHARED IMPORTED)
set_target_properties(maplibre_native_c PROPERTIES
  IMPORTED_LOCATION ${MLN_FFI_DIR}/lib/libmaplibre-native-c.so
  INTERFACE_INCLUDE_DIRECTORIES ${MLN_FFI_DIR}/include)

add_library(flutter_mapigrade SHARED
  ${CORE_DIR}/map_texture.cpp
  ${CORE_DIR}/map_texture_api.cpp
  map_texture_android.cpp)
target_include_directories(flutter_mapigrade PRIVATE ${CORE_DIR})
target_compile_options(flutter_mapigrade PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(flutter_mapigrade PRIVATE maplibre_native_c android EGL log)
