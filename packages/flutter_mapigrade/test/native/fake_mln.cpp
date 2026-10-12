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

}  // namespace fake_mln

extern "C" {

mln_runtime_options mln_runtime_options_default(void) MLN_NOEXCEPT {
  mln_runtime_options options{};
  options.size = sizeof(options);
  return options;
}

mln_status mln_runtime_create(const mln_runtime_options*,
                              mln_runtime* out_runtime) MLN_NOEXCEPT {
  *out_runtime = next_handle++;
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
  return MLN_STATUS_OK;
}

mln_status mln_map_destroy(mln_map) MLN_NOEXCEPT { return MLN_STATUS_OK; }

mln_status mln_map_set_style_url(mln_map, const char*) MLN_NOEXCEPT {
  return MLN_STATUS_OK;
}

mln_status mln_map_set_style_json(mln_map, mln_buffer_view) MLN_NOEXCEPT {
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

const char* mln_thread_last_error_message(void) MLN_NOEXCEPT { return ""; }

}  // extern "C"
