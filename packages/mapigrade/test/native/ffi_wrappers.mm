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
std::function<mln_status(const std::string&)> feature_state_hook;
std::vector<uint32_t> event_types;
std::vector<uint32_t> demand_flags;
std::vector<std::string> frame_log;
std::optional<mln_gpu_sync_kind> producer_sync_kind;
std::function<void(mln_acquired_frame)> release_hook;
std::vector<mln_frame_projection> rendered_projections;

// The core's event handler, which RecordEvents forwards each batch to.
struct EventHandler {
  mln_runtime_event_callback callback;
  void* user_data;
};

void RecordEvents(void* user_data, const mln_event_batch_view* events) {
  {
    std::lock_guard lock(mutex);
    const auto* base = reinterpret_cast<const char*>(events->events);
    for (size_t i = 0; i < events->event_count; ++i) {
      event_types.push_back(reinterpret_cast<const mln_runtime_event*>(
                                base + i * events->event_size)
                                ->type);
    }
  }
  auto* handler = static_cast<EventHandler*>(user_data);
  handler->callback(handler->user_data, events);
}

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
  feature_state_hook = nullptr;
  event_types.clear();
  demand_flags.clear();
  frame_log.clear();
  producer_sync_kind.reset();
  release_hook = nullptr;
  rendered_projections.clear();
}

std::vector<std::string> FrameLog() {
  std::lock_guard lock(mutex);
  return frame_log;
}

void Note(std::string step) {
  std::lock_guard lock(mutex);
  frame_log.push_back(std::move(step));
}

void SetProducerSyncKind(mln_gpu_sync_kind kind) {
  std::lock_guard lock(mutex);
  producer_sync_kind = kind;
}

void SetReleaseHook(std::function<void(mln_acquired_frame)> hook) {
  std::lock_guard lock(mutex);
  release_hook = std::move(hook);
}

std::vector<mln_frame_projection> RenderedProjections() {
  std::lock_guard lock(mutex);
  return rendered_projections;
}

std::vector<uint32_t> DemandFlags() {
  std::lock_guard lock(mutex);
  return demand_flags;
}

std::vector<uint32_t> EventTypes() {
  std::lock_guard lock(mutex);
  return event_types;
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

void SetFeatureStateHook(
    std::function<mln_status(const std::string& feature_id)> hook) {
  std::lock_guard lock(mutex);
  feature_state_hook = std::move(hook);
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
  // As the FFI does, the message has a NUL byte after its bytes.
  handler->callback(handler->user_data, record.severity, record.event, 0,
                    {record.message.c_str(), record.message.size()});
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

// Interposes RecordEvents for a handler without release_user_data, as the
// core's is; RecordEvents' own user_data is released with the registration.
mln_status test_mln_runtime_set_event_handler(
    mln_runtime runtime, const mln_runtime_event_handler* handler,
    const mln_completion* completion, mln_diagnostic* out_diagnostic) {
  if (handler == nullptr || handler->callback == nullptr ||
      handler->release_user_data != nullptr) {
    return mln_runtime_set_event_handler(runtime, handler, completion,
                                         out_diagnostic);
  }
  mln_runtime_event_handler recording = *handler;
  recording.callback = &RecordEvents;
  recording.user_data = new EventHandler{handler->callback, handler->user_data};
  recording.release_user_data = [](void* user_data) {
    delete static_cast<EventHandler*>(user_data);
  };
  mln_status status = mln_runtime_set_event_handler(
      runtime, &recording, completion, out_diagnostic);
  // A rejected call leaves user_data with the caller.
  if (status != MLN_STATUS_OK) {
    delete static_cast<EventHandler*>(recording.user_data);
  }
  return status;
}

mln_status test_mln_render_session_demand_frame(
    mln_render_session session, const mln_frame_demand* demand,
    mln_diagnostic* out_diagnostic) {
  if (demand != nullptr) {
    std::lock_guard lock(mutex);
    demand_flags.push_back(demand->flags);
  }
  return mln_render_session_demand_frame(session, demand, out_diagnostic);
}

mln_status test_mln_render_session_drain_frame_results(
    mln_render_session session, mln_render_frame_batch* out_batch,
    mln_render_frame_batch_view* out_view, mln_diagnostic* out_diagnostic) {
  mln_status status = mln_render_session_drain_frame_results(
      session, out_batch, out_view, out_diagnostic);
  if (status == MLN_STATUS_OK && out_view != nullptr) {
    std::lock_guard lock(mutex);
    const auto* base = reinterpret_cast<const char*>(out_view->results);
    for (size_t i = 0; i < out_view->result_count; ++i) {
      const auto& result = *reinterpret_cast<const mln_render_frame_result*>(
          base + i * out_view->result_size);
      if (result.disposition == MLN_RENDER_RESULT_RENDERED) {
        rendered_projections.push_back(result.frame_projection);
      }
    }
  }
  return status;
}

mln_status test_mln_acquired_frame_get_producer_sync(
    mln_acquired_frame frame, mln_gpu_sync* out_sync,
    mln_diagnostic* out_diagnostic) {
  mln_status status =
      mln_acquired_frame_get_producer_sync(frame, out_sync, out_diagnostic);
  std::lock_guard lock(mutex);
  frame_log.push_back("producer_sync");
  if (status == MLN_STATUS_OK && producer_sync_kind) {
    out_sync->kind = *producer_sync_kind;
  }
  return status;
}

mln_status test_mln_acquired_frame_release(
    mln_acquired_frame frame, const mln_gpu_sync* consumer_completion,
    mln_diagnostic* out_diagnostic) {
  std::function<void(mln_acquired_frame)> hook;
  {
    std::lock_guard lock(mutex);
    frame_log.push_back("release");
    hook = release_hook;
  }
  if (hook) hook(frame);
  return mln_acquired_frame_release(frame, consumer_completion, out_diagnostic);
}

mln_status test_mln_runtime_create_map(mln_runtime runtime,
                                       const mln_map_options* options,
                                       mln_map* out_map,
                                       const mln_completion* completion,
                                       mln_diagnostic* out_diagnostic) {
  Record("mln_runtime_create_map");
  return mln_runtime_create_map(runtime, options, out_map, completion,
                                out_diagnostic);
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

mln_status test_mln_map_add_geo_json_source(
    mln_map map, mln_buffer_view source_id,
    const mln_geo_json_source_options* options, mln_buffer_view attribution,
    const mln_completion* completion, mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_add_geo_json_source", source_id);
  return mln_map_add_geo_json_source(map, source_id, options, attribution,
                                     completion, out_diagnostic);
}

mln_status test_mln_map_set_geo_json_source_data(
    mln_map map, mln_buffer_view source_id, mln_buffer_view data,
    const mln_completion* completion, mln_diagnostic* out_diagnostic) {
  RecordStyleCall("mln_map_set_geo_json_source_data", source_id);
  return mln_map_set_geo_json_source_data(map, source_id, data, completion,
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

mln_status test_mln_map_set_feature_state(
    mln_map map, const mln_feature_state_selector* selector,
    mln_buffer_view state, const mln_completion* completion,
    mln_diagnostic* out_diagnostic) {
  std::function<mln_status(const std::string&)> hook;
  {
    std::lock_guard lock(mutex);
    hook = feature_state_hook;
  }
  if (hook) {
    bool has_id =
        (selector->fields & MLN_FEATURE_STATE_SELECTOR_FEATURE_ID) != 0;
    mln_status status =
        hook(has_id ? Text(selector->feature_id.data.string_value) : "");
    if (status != MLN_STATUS_OK) {
      SetDiagnostic(out_diagnostic, "set by the test");
      return status;
    }
  }
  return mln_map_set_feature_state(map, selector, state, completion,
                                   out_diagnostic);
}

}  // extern "C"
