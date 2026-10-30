// Included before everything else in the core's sources of map_texture_tests
// (design D187 of the adopt-ffi-core-executor change). It renames the FFI
// functions whose arguments or failures the tests check, so that the core's
// calls, and the FFI header's prototypes, refer to the wrappers in
// ffi_wrappers.mm. The wrappers record the calls and forward them to the real
// FFI, or return a failure that a test sets.
#pragma once

#define mln_runtime_create test_mln_runtime_create
#define mln_runtime_set_maximum_ambient_cache_size \
  test_mln_runtime_set_maximum_ambient_cache_size
#define mln_runtime_set_http_header_transform \
  test_mln_runtime_set_http_header_transform
#define mln_runtime_create_map test_mln_runtime_create_map
#define mln_map_set_style_url test_mln_map_set_style_url
#define mln_map_set_style_json test_mln_map_set_style_json
#define mln_log_set_callback test_mln_log_set_callback
#define mln_map_add_geojson_source_data test_mln_map_add_geojson_source_data
#define mln_map_set_geojson_source_data test_mln_map_set_geojson_source_data
#define mln_map_remove_style_source test_mln_map_remove_style_source
#define mln_map_add_style_layer_json test_mln_map_add_style_layer_json
#define mln_map_remove_style_layer test_mln_map_remove_style_layer
#define mln_map_move_style_layer test_mln_map_move_style_layer
#define mln_map_set_feature_state test_mln_map_set_feature_state
