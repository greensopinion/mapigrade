# Unit tests of the native core.
#   cmake -S test/native -B build/native-tests && cmake --build build/native-tests
#   ctest --test-dir build/native-tests --output-on-failure
#
# core_tests covers the parts that don't call MapLibre. map_texture_tests runs
# MapTexture on a fake of the MapLibre Native FFI (fake_mln.cpp), which needs
# the FFI's headers from scripts/build_maplibre_ffi.sh.
cmake_minimum_required(VERSION 3.20)
project(map_texture_core_tests CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../src/core)
set(MLN_FFI_INCLUDE_DIR
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/maplibre-native-ffi/macos-arm64-metal/include
    CACHE PATH "Include directory of an installed MapLibre Native FFI preset")

add_executable(core_tests core_tests.cpp)
target_include_directories(core_tests PRIVATE ${CORE_DIR})
target_compile_options(core_tests PRIVATE -Wall -Wextra -Werror)

add_executable(map_texture_tests
  map_texture_tests.cpp
  fake_mln.cpp
  ${CORE_DIR}/map_texture.cpp
  ${CORE_DIR}/map_texture_api.cpp)
target_include_directories(map_texture_tests PRIVATE ${CORE_DIR} ${MLN_FFI_INCLUDE_DIR})
target_compile_options(map_texture_tests PRIVATE -Wall -Wextra -Werror -Wno-unused-parameter)

enable_testing()
add_test(NAME core_tests COMMAND core_tests)
add_test(NAME map_texture_tests COMMAND map_texture_tests)
