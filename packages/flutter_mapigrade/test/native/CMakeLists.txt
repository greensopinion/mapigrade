# Unit tests of the native core.
#   cmake -S test/native -B build/native-tests && cmake --build build/native-tests
#   ctest --test-dir build/native-tests --output-on-failure
#
# core_tests covers the parts that don't call MapLibre. map_texture_tests runs
# MapTexture on the real MapLibre Native FFI with headless Metal targets, and
# ffi_headless_test checks that the FFI renders headless (design D187 of the
# adopt-ffi-core-executor change). Both link against the macOS slice of the
# FFI framework from a local build (scripts/build_maplibre_ffi.sh), or else
# from the pinned release, which scripts/fetch_ffi_release.sh unpacks.
cmake_minimum_required(VERSION 3.20)
project(map_texture_core_tests CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OSX_ARCHITECTURES arm64)

set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../src/core)

add_executable(core_tests core_tests.cpp)
target_include_directories(core_tests PRIVATE ${CORE_DIR})
target_compile_options(core_tests PRIVATE -Wall -Wextra -Werror)

set(FFI_REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../..)
file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/../../maplibre_ffi.lock FFI_VERSION_LINE
     REGEX "^MAPLIBRE_FFI_VERSION=")
string(REPLACE "MAPLIBRE_FFI_VERSION=" "" FFI_VERSION "${FFI_VERSION_LINE}")
if(EXISTS ${FFI_REPO_ROOT}/third_party/maplibre-native-ffi/MaplibreNativeC.xcframework)
  set(FFI_XCFRAMEWORK_DEFAULT ${FFI_REPO_ROOT}/third_party/maplibre-native-ffi/MaplibreNativeC.xcframework)
else()
  set(FFI_XCFRAMEWORK_DEFAULT
      ${FFI_REPO_ROOT}/third_party/maplibre-native-ffi-release/${FFI_VERSION}/MaplibreNativeC.xcframework)
endif()
if(NOT EXISTS ${FFI_XCFRAMEWORK_DEFAULT})
  message(FATAL_ERROR "No MapLibre Native FFI framework at ${FFI_XCFRAMEWORK_DEFAULT}; "
                      "run scripts/fetch_ffi_release.sh")
endif()
set(FFI_XCFRAMEWORK ${FFI_XCFRAMEWORK_DEFAULT} CACHE PATH
    "MaplibreNativeC.xcframework that the tests link against")
set(FFI_FRAMEWORK_DIR ${FFI_XCFRAMEWORK}/macos-arm64)

# Compiles and links `target` against the FFI framework and Metal.
function(use_ffi target)
  target_compile_options(${target} PRIVATE -F${FFI_FRAMEWORK_DIR})
  target_link_options(${target} PRIVATE -F${FFI_FRAMEWORK_DIR}
                      -Wl,-rpath,${FFI_FRAMEWORK_DIR})
  target_link_libraries(${target} PRIVATE "-framework MaplibreNativeC"
                        "-framework Metal" "-framework Foundation")
endfunction()

add_executable(map_texture_tests
  map_texture_tests.mm
  ffi_wrappers.mm
  ${CORE_DIR}/map_texture.cpp
  ${CORE_DIR}/map_texture_api.cpp)
target_include_directories(map_texture_tests PRIVATE ${CORE_DIR})
target_compile_options(map_texture_tests PRIVATE -Wall -Wextra -Werror
                       -Wno-unused-parameter -Wno-missing-field-initializers)
set_source_files_properties(map_texture_tests.mm ffi_wrappers.mm PROPERTIES
                            COMPILE_OPTIONS "-fobjc-arc")
# The core's calls to the functions in ffi_redirect.h go to ffi_wrappers.mm.
set_source_files_properties(${CORE_DIR}/map_texture.cpp
                            ${CORE_DIR}/map_texture_api.cpp PROPERTIES
                            COMPILE_OPTIONS "-include;${CMAKE_CURRENT_SOURCE_DIR}/ffi_redirect.h")
use_ffi(map_texture_tests)

add_executable(ffi_headless_test ffi_headless_test.mm)
target_compile_options(ffi_headless_test PRIVATE -fobjc-arc -Wall -Wextra -Werror)
use_ffi(ffi_headless_test)

enable_testing()
add_test(NAME core_tests COMMAND core_tests)
add_test(NAME map_texture_tests COMMAND map_texture_tests)
add_test(NAME ffi_headless_test COMMAND ffi_headless_test)
