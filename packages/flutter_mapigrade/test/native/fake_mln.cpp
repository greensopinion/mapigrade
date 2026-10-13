#include "fake_mln.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>

namespace {

std::mutex mutex;
std::condition_variable cv;
bool woken = false;
int pending_render_updates = 0;
std::vector<mln_runtime_event> drained;
int render_count = 0;
std::vector<int64_t> render_starts;
std::atomic<int64_t (*)()> clock_fn{nullptr};
std::atomic<uint64_t> next_handle{1};
mln_camera_options camera{};
std::vector<fake_mln::Call> calls;
std::atomic<mln_status> cache_size_status{MLN_STATUS_OK};
int header_transform_registrations = 0;
mln_http_header_transform header_transform{};
std::string validate_name;
std::string validate_message;
std::string runtime_create_message;
mln_status validate_status = MLN_STATUS_OK;
mln_status runtime_create_status = MLN_STATUS_OK;
std::string last_asset_path;
// What mln_thread_last_error_message returns.
thread_local std::string last_error;

void Record(const char* name, uint64_t size = 0) {
  std::lock_guard lock(mutex);
  calls.push_back({name, size});
}

int64_t Now() {
  if (auto clock = clock_fn.load()) return clock();
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

void Wake() {
  {
    std::lock_guard lock(mutex);
    woken = true;
  }
  cv.notify_all();
}

}  // namespace

namespace fake_mln {

void Reset() {
  std::lock_guard lock(mutex);
  pending_render_updates = 0;
  render_count = 0;
  render_starts.clear();
  calls.clear();
  header_transform_registrations = 0;
  header_transform = {};
  last_asset_path.clear();
}

void QueueRenderUpdate() {
  {
    std::lock_guard lock(mutex);
    ++pending_render_updates;
  }
  Wake();
}

int RenderCount() {
  std::lock_guard lock(mutex);
  return render_count;
}

std::vector<int64_t> RenderStarts() {
  std::lock_guard lock(mutex);
  return render_starts;
}

void SetClock(int64_t (*now_ns)()) { clock_fn.store(now_ns); }

std::vector<Call> Calls() {
  std::lock_guard lock(mutex);
  return calls;
}

void SetMaximumCacheSizeStatus(mln_status status) {
  cache_size_status.store(status);
}

int HeaderTransformRegistrations() {
  std::lock_guard lock(mutex);
  return header_transform_registrations;
}

bool HeaderTransformUsesAdapter() {
  std::lock_guard lock(mutex);
  return header_transform.callback ==
         &mln_adapter_http_header_transform_callback;
}

std::vector<HeaderRule> HeaderRules() {
  std::lock_guard lock(mutex);
  std::vector<HeaderRule> rules;
  const auto* table = static_cast<const mln_adapter_http_header_transform_rules*>(
      header_transform.user_data);
  if (table == nullptr) return rules;
  for (size_t i = 0; i < table->count; ++i) {
    const auto& rule = table->rules[i];
    HeaderRule copy{rule.kind, rule.flags, rule.url, {}};
    for (size_t j = 0; j < rule.header_count; ++j) {
      copy.headers.push_back({rule.headers[j].name, rule.headers[j].value});
    }
    rules.push_back(std::move(copy));
  }
  return rules;
}

void SetHeaderValidateResult(std::string name, mln_status status,
                             std::string message) {
  std::lock_guard lock(mutex);
  validate_name = std::move(name);
  validate_status = status;
  validate_message = std::move(message);
}

std::string LastAssetPath() {
  std::lock_guard lock(mutex);
  return last_asset_path;
}

void SetRuntimeCreateResult(mln_status status, std::string message) {
  std::lock_guard lock(mutex);
  runtime_create_status = status;
  runtime_create_message = std::move(message);
}

}  // namespace fake_mln

extern "C" {

mln_runtime_options mln_runtime_options_default(void) MLN_NOEXCEPT {
  mln_runtime_options options{};
  options.size = sizeof(options);
  return options;
}

mln_status mln_runtime_create(const mln_runtime_options* options,
                              mln_runtime* out_runtime) MLN_NOEXCEPT {
  Record("mln_runtime_create");
  std::lock_guard lock(mutex);
  last_asset_path =
      options->asset_path == nullptr ? "<null>" : options->asset_path;
  if (runtime_create_status != MLN_STATUS_OK) {
    last_error = runtime_create_message;
    return runtime_create_status;
  }
  *out_runtime = next_handle++;
  return MLN_STATUS_OK;
}

mln_status mln_runtime_set_http_header_transform(
    mln_runtime, const mln_http_header_transform* transform) MLN_NOEXCEPT {
  Record("mln_runtime_set_http_header_transform");
  std::lock_guard lock(mutex);
  ++header_transform_registrations;
  header_transform = *transform;
  return MLN_STATUS_OK;
}

mln_status mln_adapter_http_header_transform_callback(
    void*, uint32_t, const char*,
    mln_http_header_transform_response*) MLN_NOEXCEPT {
  return MLN_STATUS_OK;
}

mln_status mln_adapter_http_header_validate(const char* name,
                                            const char*) MLN_NOEXCEPT {
  std::lock_guard lock(mutex);
  last_error.clear();
  if (validate_status != MLN_STATUS_OK && validate_name == name) {
    last_error = validate_message;
    return validate_status;
  }
  return MLN_STATUS_OK;
}

mln_status mln_runtime_set_maximum_ambient_cache_size_start(
    mln_runtime, uint64_t size,
    mln_offline_operation_id* out_operation_id) MLN_NOEXCEPT {
  Record("mln_runtime_set_maximum_ambient_cache_size_start", size);
  mln_status status = cache_size_status.load();
  if (status == MLN_STATUS_OK) *out_operation_id = next_handle++;
  return status;
}

mln_status mln_runtime_offline_operation_discard(mln_runtime,
                                                 mln_offline_operation_id)
    MLN_NOEXCEPT {
  Record("mln_runtime_offline_operation_discard");
  return MLN_STATUS_OK;
}

mln_status mln_runtime_destroy(mln_runtime) MLN_NOEXCEPT {
  return MLN_STATUS_OK;
}

mln_status mln_runtime_wake_source_acquire(mln_runtime,
                                           mln_wake_source* out) MLN_NOEXCEPT {
  *out = next_handle++;
  return MLN_STATUS_OK;
}

mln_status mln_wake_source_signal(mln_wake_source) MLN_NOEXCEPT {
  Wake();
  return MLN_STATUS_OK;
}

void mln_wake_source_destroy(mln_wake_source) MLN_NOEXCEPT {}

mln_status mln_runtime_pump(mln_runtime, int64_t timeout_ms,
                            int64_t) MLN_NOEXCEPT {
  std::unique_lock lock(mutex);
  cv.wait_for(lock, std::chrono::milliseconds(timeout_ms),
              [] { return woken || pending_render_updates > 0; });
  woken = false;
  return MLN_STATUS_OK;
}

mln_runtime_event_batch mln_runtime_event_batch_default(void) MLN_NOEXCEPT {
  mln_runtime_event_batch batch{};
  batch.size = sizeof(batch);
  return batch;
}

mln_status mln_runtime_drain_events(mln_runtime, size_t,
                                    mln_runtime_event_batch* out) MLN_NOEXCEPT {
  std::lock_guard lock(mutex);
  drained.clear();
  for (; pending_render_updates > 0; --pending_render_updates) {
    mln_runtime_event event{};
    event.type = MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE;
    drained.push_back(event);
  }
  out->event_size = sizeof(mln_runtime_event);
  out->events = drained.empty() ? nullptr : drained.data();
  out->event_count = drained.size();
  out->messages = nullptr;
  out->messages_size = 0;
  out->remaining_count = 0;
  return MLN_STATUS_OK;
}

mln_map_options mln_map_options_default(void) MLN_NOEXCEPT {
  mln_map_options options{};
  options.size = sizeof(options);
  return options;
}

mln_status mln_map_create(mln_runtime, const mln_map_options*,
                          mln_map* out_map) MLN_NOEXCEPT {
  *out_map = next_handle++;
  Record("mln_map_create");
  return MLN_STATUS_OK;
}

mln_status mln_map_destroy(mln_map) MLN_NOEXCEPT { return MLN_STATUS_OK; }

mln_status mln_map_set_style_url(mln_map, const char*) MLN_NOEXCEPT {
  Record("mln_map_set_style_url");
  return MLN_STATUS_OK;
}

mln_status mln_map_set_style_json(mln_map, mln_buffer_view) MLN_NOEXCEPT {
  Record("mln_map_set_style_json");
  return MLN_STATUS_OK;
}

mln_camera_options mln_camera_options_default(void) MLN_NOEXCEPT {
  mln_camera_options options{};
  options.size = sizeof(options);
  return options;
}

mln_status mln_map_jump_to(mln_map, const mln_camera_options* options)
    MLN_NOEXCEPT {
  std::lock_guard lock(mutex);
  camera = *options;
  ++pending_render_updates;
  return MLN_STATUS_OK;
}

mln_status mln_render_session_render_update(mln_render_session,
                                            mln_render_result* out_result,
                                            bool* out_needs_repaint)
    MLN_NOEXCEPT {
  int64_t start = Now();
  std::lock_guard lock(mutex);
  ++render_count;
  render_starts.push_back(start);
  *out_result = MLN_RENDER_RESULT_RENDERED;
  *out_needs_repaint = false;
  return MLN_STATUS_OK;
}

mln_status mln_render_session_projection_create(
    mln_render_session, mln_map_projection* out) MLN_NOEXCEPT {
  *out = next_handle++;
  return MLN_STATUS_OK;
}

mln_status mln_map_projection_get_camera(mln_map_projection,
                                         mln_camera_options* out) MLN_NOEXCEPT {
  std::lock_guard lock(mutex);
  *out = camera;
  return MLN_STATUS_OK;
}

mln_status mln_map_projection_destroy(mln_map_projection) MLN_NOEXCEPT {
  return MLN_STATUS_OK;
}

mln_status mln_render_session_reduce_memory_use(mln_render_session)
    MLN_NOEXCEPT {
  return MLN_STATUS_OK;
}

mln_status mln_render_session_destroy(mln_render_session) MLN_NOEXCEPT {
  return MLN_STATUS_OK;
}

const char* mln_thread_last_error_message(void) MLN_NOEXCEPT {
  return last_error.c_str();
}

}  // extern "C"
