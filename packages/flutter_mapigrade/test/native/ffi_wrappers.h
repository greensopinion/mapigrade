// The test side of the wrappers that ffi_redirect.h directs the core's calls
// to (design D187 of the adopt-ffi-core-executor change): what the core
// passed to the FFI, and failures that a test makes the next calls return.
// Every other call goes to the real FFI.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <MaplibreNativeC/maplibre_native_c.h>

namespace ffi_wrappers {

// Clears the recorded calls and the failures.
void Reset();

// The redirected calls since the last Reset(), in order. For
// mln_runtime_set_maximum_ambient_cache_size, `size` is the size. For the
// style source and layer commands, `id` is the source or layer ID (for
// mln_map_add_style_layer_json, the layer JSON's id member) and `before` the
// layer the layer goes before.
struct Call {
  std::string name;
  uint64_t size = 0;
  std::string id;
  std::string before;
};
std::vector<Call> Calls();
// The names of Calls() that start with `prefix`, in order.
std::vector<std::string> CallNames(const std::string& prefix = "");

// Makes the next mln_runtime_set_maximum_ambient_cache_size calls return
// `status` without calling the FFI, until set back to MLN_STATUS_OK.
void SetMaximumCacheSizeStatus(mln_status status);

// Makes the next mln_runtime_create calls fail with `status` and the
// diagnostic `message`, until set back to MLN_STATUS_OK.
void SetRuntimeCreateResult(mln_status status, std::string message);

// The header rules of the header transforms registered since the last Reset().
struct Header {
  std::string name;
  std::string value;
  bool operator==(const Header&) const = default;
};
struct HeaderRule {
  uint32_t kinds = 0;
  uint32_t flags = 0;
  std::string url;
  std::vector<Header> headers;
};
std::vector<HeaderRule> HeaderRules();

// The asset path of the last runtime created, or "<null>" for none.
std::string LastAssetPath();

// How often the core registered its log handler in the process.
int LogCallbackRegistrations();

// Calls the log handler that the core registered, on the calling thread, as
// the FFI does when MapLibre logs. Returns false if no handler is registered.
struct LogRecord {
  uint32_t severity = MLN_LOG_SEVERITY_ERROR;
  uint32_t event = MLN_LOG_EVENT_STYLE;
  std::string message;
};
bool Log(const LogRecord& record);

}  // namespace ffi_wrappers
