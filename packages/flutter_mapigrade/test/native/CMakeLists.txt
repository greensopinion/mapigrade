# Unit tests for the parts of the native core that don't call MapLibre.
#   cmake -S test/native -B build/native-tests && cmake --build build/native-tests
#   ctest --test-dir build/native-tests --output-on-failure
cmake_minimum_required(VERSION 3.20)
project(map_texture_core_tests CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(core_tests core_tests.cpp)
target_include_directories(core_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../../src/core)
target_compile_options(core_tests PRIVATE -Wall -Wextra -Werror)

enable_testing()
add_test(NAME core_tests COMMAND core_tests)
