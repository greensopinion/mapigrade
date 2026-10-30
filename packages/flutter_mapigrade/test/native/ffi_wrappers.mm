// The wrappers that ffi_redirect.h directs the core's calls to. This file
// isn't compiled with ffi_redirect.h, so its calls reach the real FFI.
#include "ffi_wrappers.h"

#include <cstdio>
#include <mutex>
#include <optional>

namespace ffi_wrappers {
namespace {

std::mutex mutex;
std::vector<Call> calls;
mln_status cache_size_status = MLN_STATUS_OK;
mln_status runtime_create_status = MLN_STATUS_OK;
std::string runtime_create_message;
std::vector<HeaderRule> header_rules;
std::string last_asset_path = "<null>";
int log_registrations = 0;
std::optional<mln_log_handler> log_handler;

void Record(std::string name, uint64_t size = 0) {
  std::lock_guard lock(mutex);
  calls.push_back({std::move(name), size, {}, {}});
}

std::string Text(const mln_buffer_view& view) {
  return view.data == nullptr
             ? std::string()
             : std::string(static_cast<const char*>(view.data), view.size);
}

void RecordStyleCall(std::string name, const mln_buffer_view& id,
                     const mln_buffer_view& before = {}) {
  std::lock_guard lock(mutex);
  calls.push_back({std::move(name), 0, Text(id), Text(before)});
}

// The id member of a layer JSON object, as the test's layers write it.
std::string LayerJsonId(const mln_buffer_view& json) {
  std::string text = Text(json);
  size_t key = text.find("\"id\"");
  if (key == std::string::npos) return {};
  size_t open = text.find('"', text.find(':', key) + 1);
  size_t close = text.find('"', open + 1);
  if (open == std::string::npos || close == std::string::npos) return {};
  return text.substr(open + 1, close - open - 1);
}

void SetDiagnostic(mln_diagnostic* diagnostic, const std::string& message) {
  if (diagnostic == nullptr) return;
  std::snprintf(diagnostic->message, sizeof(diagnostic->message), "%s",
                message.c_str());
}

}  // namespace

void Reset() {
  std::lock_guard lock(mutex);
  calls.clear();
  cache_size_status = MLN_STATUS_OK;
  runtime_create_status = MLN_STATUS_OK;
  runtime_create_message.clear();
  header_rules.clear();
  last_asset_path = "<null>";
}

std::vector<Call> Calls() {
  std::lock_guard lock(mutex);
  return calls;
}

std::vector<std::string> CallNames(const std::string& prefix) {
  std::lock_guard lock(mutex);
  std::vector<std::string> names;
  for (const Call& call : calls) {
    if (call.name.starts_with(prefix)) names.push_back(call.name);
  }
  return names;
}

void SetMaximumCacheSizeStatus(mln_status status) {
  std::lock_guard lock(mutex);
  cache_size_status = status;
}

void SetRuntimeCreateResult(mln_status status, std::string message) {
  std::lock_guard lock(mutex);
  runtime_create_status = status;
  runtime_create_message = std::move(message);
}

std::vector<HeaderRule> HeaderRules() {
  std::lock_guard lock(mutex);
  return header_rules;
}

std::string LastAssetPath() {
  std::lock_guard lock(mutex);
  return last_asset_path;
}

int LogCallbackRegistrations() {
  std::lock_guard lock(mutex);
  return log_registrations;
}

bool Log(const LogRecord& record) {
  std::optional<mln_log_handler> handler;
  {
    std::lock_guard lock(mutex);
    handler = log_handler;
  }
  if (!handler || handler->callback == nullptr) return false;
  handler->callback(handler->user_data, record.severity, record.event, 0,
                    record.message.c_str());
  return true;
}

}  // namespace ffi_wrappers

using namespace ffi_wrappers;

extern "C" {

mln_status test_mln_runtime_create(const mln_runtime_options* options,
                                   mln_runtime* out_runtime,
                                   mln_diagnostic* out_diagnostic) {
  Record("mln_runtime_create");
  {
    std::lock_guard lock(mutex);
    last_asset_path =
        options == nullptr || options->asset_path.data == nullptr
            ? "<null>"
            : Text(options->asset_path);
    if (runtime_create_status != MLN_STATUS_OK) {
      SetDiagnostic(out_diagnostic, runtime_create_message);
      return runtime_create_status;
    }
  }
  return mln_runtime_create(options, out_runtime, out_diagnostic);
}

mln_status test_mln_runtime_set_maximum_ambient_cache_size(
    mln_runtime runtime, uint64_t size, const mln_completion* completion,
    mln_diagnostic* out_diagnostic) {
  Record("mln_runtime_set_maximum_ambient_cache_size", size);
  mln_status status;
  {
    std::lock_guard lock(mutex);
    status = cache_size_status;
  }
  if (status != MLN_STATUS_OK) {
    SetDiagnostic(out_diagnostic, "set by the test");
    return status;
  }
  return mln_runtime_set_maximum_ambient_cache_size(runtime, size, completion,
                                                    out_diagnostic);
}

mln_status test_mln_runtime_set_http_header_transform(
    mln_runtime runtime, const mln_http_header_transform* transform,
    const mln_completion* completion, mln_diagnostic* out_diagnostic) {
  Record("mln_runtime_set_http_header_transform");
  {
    std::lock_guard lock(mutex);
    for (size_t i = 0; transform != nullptr && i < transform->rule_count;
         ++i) {
      const mln_http_header_rule& rule = transform->rules[i];
      HeaderRule copy{rule.kinds, rule.flags, Text(rule.url), {}};
      for (size_t h = 0; h < rule.header_count; ++h) {
        copy.headers.push_back(
            {Text(rule.headers[h].name), Text(rule.headers[h].value)});
      }
      header_rules.push_back(std::move(copy));
    }
  }
  return mln_runtime_set_http_header_transform(runtime, transform, completion,
                                               out_diagnostic);
}

mln_status test_mln_runtime_create_map(mln_runtime runtime,
                                       const mln_map_options* options,
                                       const mln_completion* completion,
                                       mln_diagnostic* out_diagnostic) {
  Record("mln_runtime_create_map");
  return mln_runtime_create_map(runtime, options, completion, out_diagnostic);
}

mln_status test_mln_map_set_style_url(mln_map map, mln_buffer_view url,
                                      const mln_completion* completion,
                                      mln_diagnostic* out_diagnostic) {
  Record("mln_map_set_style_url");
  return mln_map_set_style_url(map, url, completion, out_diagnostic);
}

mln_status test_mln_map_set_style_json(mln_map map, mln_buffer_view json,
                                       const mln_completion* completion,
                                       mln_diagnostic* out_diagnostic) {
  Record("mln_map_set_style_json");
  return mln_map_set_style_json(map, json, completion, out_diagnostic);
}

mln_status test_mln_log_set_callback(const mln_log_handler* handler,
                                     mln_diagnostic* out_diagnostic) {
  {
    std::lock_guard lock(mutex);
    ++log_registrations;
    if (handler != nullptr) log_handler = *handler;
  }
  return mln_log_set_callback(handler, out_diagnostic);
}

mln_status test_mln_map_add_geojson_source_data(
    mln_map map, mln_buffer_view source_id, mln_geojson_source_data data,
    const mln_completion* completion, mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_add_geojson_source_data", source_id);
  return mln_map_add_geojson_source_data(map, source_id, data, completion,
                                         out_diagnostic);
}

mln_status test_mln_map_set_geojson_source_data(
    mln_map map, mln_buffer_view source_id, mln_geojson_source_data data,
    const mln_completion* completion, mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_set_geojson_source_data", source_id);
  return mln_map_set_geojson_source_data(map, source_id, data, completion,
                                         out_diagnostic);
}

mln_status test_mln_map_remove_style_source(mln_map map,
                                            mln_buffer_view source_id,
                                            const mln_completion* completion,
                                            mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_remove_style_source", source_id);
  return mln_map_remove_style_source(map, source_id, completion,
                                     out_diagnostic);
}

mln_status test_mln_map_add_style_layer_json(mln_map map,
                                             mln_buffer_view layer_json,
                                             mln_buffer_view before_layer_id,
                                             const mln_completion* completion,
                                             mln_diagnostic* out_diagnostic) {
  std::string id = LayerJsonId(layer_json);
  RecordStyleCall("mln_map_add_style_layer_json", {id.data(), id.size()},
                  before_layer_id);
  return mln_map_add_style_layer_json(map, layer_json, before_layer_id,
                                      completion, out_diagnostic);
}

mln_status test_mln_map_remove_style_layer(mln_map map, mln_buffer_view layer_id,
                                           const mln_completion* completion,
                                           mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_remove_style_layer", layer_id);
  return mln_map_remove_style_layer(map, layer_id, completion, out_diagnostic);
}

mln_status test_mln_map_move_style_layer(mln_map map, mln_buffer_view layer_id,
                                         mln_buffer_view before_layer_id,
                                         const mln_completion* completion,
                                         mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_move_style_layer", layer_id, before_layer_id);
  return mln_map_move_style_layer(map, layer_id, before_layer_id, completion,
                                  out_diagnostic);
}

}  // extern "C"
