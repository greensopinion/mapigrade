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
  calls.push_back({std::move(name), size});
}

std::string Text(const mln_buffer_view& view) {
  return view.data == nullptr
             ? std::string()
             : std::string(static_cast<const char*>(view.data), view.size);
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

}  // extern "C"
