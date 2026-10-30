#include "map_texture.h"

#if defined(__ANDROID__)
#include <android/log.h>
#endif

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>

namespace map_texture {

namespace {
std::atomic<RenderAheadMode> render_ahead_mode{RenderAheadMode::kAuto};
std::atomic<int64_t (*)()> test_clock{nullptr};
}  // namespace

void SetRenderAheadModeForTesting(RenderAheadMode mode) {
  render_ahead_mode.store(mode);
}

void SetClockForTesting(int64_t (*now_ns)()) { test_clock.store(now_ns); }

namespace {

// The FFI has no render-update-available event: an armed frame demand waits
// for the map's next update instead.
constexpr uint64_t kMapEventMask =
    MLN_RUNTIME_EVENT_MASK_MAP_STYLE_LOADED |
    MLN_RUNTIME_EVENT_MASK_MAP_LOADING_FAILED |
    MLN_RUNTIME_EVENT_MASK_MAP_RENDER_ERROR | MLN_RUNTIME_EVENT_MASK_MAP_IDLE;

// Park bound with nothing to do. Wakes come from the session's wakes and from
// commands, so this only bounds a missed wake.
constexpr int64_t kIdleWaitMs = 250;
// The refresh interval a surface target paces by until the display's refresh
// rate is set: 60 Hz.
constexpr int64_t kDefaultIntervalNs = 1'000'000'000 / 60;
// Delay after the last resize before Flutter is told once more that a frame
// is available. Longer than the default maximum texture age (1 s) of a
// CVMetalTextureCache; see MaybeNotifyAfterResize().
constexpr int64_t kResizeSettledNs = 1'100'000'000;

// The map whose map thread this is; null on other threads. MapLibre logs
// error records synchronously, on the thread that runs the failed work.
// Resource responses run on the runtime's scheduler thread, where this is
// null.
thread_local MapTexture* map_thread_owner = nullptr;

// Sets map_thread_owner for the lifetime of the map thread.
struct MapThreadOwnerScope {
  explicit MapThreadOwnerScope(MapTexture* map) { map_thread_owner = map; }
  ~MapThreadOwnerScope() { map_thread_owner = nullptr; }
};

// The start of the error record of MapLibre's RenderOrchestrator::
// onGlyphsError. MapLibre has no map event for a failed glyph load, and the
// FFI's map observer doesn't forward onGlyphsError.
constexpr std::string_view kGlyphFailurePrefix = "Failed to load glyph range";

std::once_flag log_callback_once;

int64_t NowNs() {
  if (auto clock = test_clock.load()) return clock();
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

uint32_t RoundToPixels(double value) {
  return static_cast<uint32_t>(std::max(1.0, std::round(value)));
}

// The size the map renders at for `viewport`, or false for an empty viewport.
bool SizeForViewport(const Viewport& viewport, TargetSize* size) {
  if (!(viewport.logical_width > 0) || !(viewport.logical_height > 0) ||
      !(viewport.pixel_ratio > 0)) {
    return false;
  }
  size->physical_width =
      RoundToPixels(viewport.logical_width * viewport.pixel_ratio);
  size->physical_height =
      RoundToPixels(viewport.logical_height * viewport.pixel_ratio);
  size->extent.width = RoundToPixels(viewport.logical_width);
  size->extent.height = RoundToPixels(viewport.logical_height);
  size->extent.scale_factor = viewport.pixel_ratio;
  return true;
}

// Completion of a target task that a caller waits for.
struct TaskDone {
  std::mutex mutex;
  std::condition_variable cv;
  bool done = false;

  void Set() {
    {
      std::lock_guard lock(mutex);
      done = true;
    }
    cv.notify_all();
  }
};

mln_diagnostic NewDiagnostic() {
  mln_diagnostic diagnostic{};
  diagnostic.size = sizeof(diagnostic);
  return diagnostic;
}

// The result of an asynchronous FFI call that the map thread waits for.
struct Waiter {
  std::mutex mutex;
  std::condition_variable cv;
  bool done = false;
  int32_t status = MLN_STATUS_OK;
  std::string diagnostic;
  // The first element of the result's value, if any.
  std::vector<uint8_t> value;

  // A completion that records its result in `waiter`.
  static mln_completion For(const std::shared_ptr<Waiter>& waiter) {
    mln_completion completion{};
    completion.size = sizeof(completion);
    completion.callback = &Waiter::OnComplete;
    completion.user_data = new std::shared_ptr<Waiter>(waiter);
    completion.release_user_data = &Waiter::Release;
    return completion;
  }

  // Frees the user data of a completion that its call rejected.
  static void Discard(const mln_completion& completion) {
    Release(completion.user_data);
  }

  bool Done() {
    std::lock_guard lock(mutex);
    return done;
  }

  // Waits until the completion has run, at most `timeout_ns`.
  bool WaitFor(int64_t timeout_ns) {
    std::unique_lock lock(mutex);
    return cv.wait_for(lock, std::chrono::nanoseconds(timeout_ns),
                       [this] { return done; });
  }

 private:
  static void OnComplete(void* user_data, const mln_completion_result* result) {
    auto& waiter = **static_cast<std::shared_ptr<Waiter>*>(user_data);
    {
      std::lock_guard lock(waiter.mutex);
      waiter.status = result->status;
      if (result->diagnostic.size > 0) {
        waiter.diagnostic.assign(
            static_cast<const char*>(result->diagnostic.data),
            result->diagnostic.size);
      }
      if (result->value != nullptr && result->value_size > 0) {
        const auto* bytes = static_cast<const uint8_t*>(result->value);
        waiter.value.assign(bytes, bytes + result->value_size);
      }
      waiter.done = true;
    }
    waiter.cv.notify_all();
  }

  static void Release(void* user_data) {
    delete static_cast<std::shared_ptr<Waiter>*>(user_data);
  }
};

// A completion that runs a function on the completing thread.
using CompletionFunction = std::function<void(const mln_completion_result&)>;

void RunCompletionFunction(void* user_data,
                           const mln_completion_result* result) {
  (*static_cast<CompletionFunction*>(user_data))(*result);
}

void DeleteCompletionFunction(void* user_data) {
  delete static_cast<CompletionFunction*>(user_data);
}

mln_completion FunctionCompletion(CompletionFunction function) {
  mln_completion completion{};
  completion.size = sizeof(completion);
  completion.callback = &RunCompletionFunction;
  completion.user_data = new CompletionFunction(std::move(function));
  completion.release_user_data = &DeleteCompletionFunction;
  return completion;
}

// Frees the user data of a FunctionCompletion() that its call rejected.
void DiscardFunctionCompletion(const mln_completion& completion) {
  DeleteCompletionFunction(completion.user_data);
}

mln_buffer_view View(const std::string& text) {
  return mln_buffer_view{text.data(), text.size()};
}

std::string_view ViewOf(const mln_buffer_view& view) {
  return {static_cast<const char*>(view.data), view.size};
}

std::string StatusMessage(const char* what, mln_status status,
                          const char* detail) {
  std::string message = std::string(what) + " failed with status " +
                        std::to_string(static_cast<int>(status));
  if (detail != nullptr && detail[0] != '\0') {
    message += ": ";
    message += detail;
  }
  return message;
}

}  // namespace

std::shared_ptr<MapTexture> MapTexture::Create(
    int64_t handle, int64_t engine, double pixel_ratio, bool copy_free,
    std::optional<uint64_t> maximum_cache_size,
    std::vector<HttpHeaderRule> header_rules,
    map_texture_event_callback callback, std::string* out_error) {
  if (!(pixel_ratio > 0) || !std::isfinite(pixel_ratio)) {
    *out_error = "invalid pixel ratio";
    return nullptr;
  }
  std::shared_ptr<MapTexture> texture(
      new MapTexture(handle, engine, pixel_ratio, maximum_cache_size,
                     std::move(header_rules), callback));
  if (!texture->Start(copy_free, out_error)) return nullptr;
  return texture;
}

MapTexture::MapTexture(int64_t handle, int64_t engine, double pixel_ratio,
                       std::optional<uint64_t> maximum_cache_size,
                       std::vector<HttpHeaderRule> header_rules,
                       map_texture_event_callback callback)
    : handle_(handle),
      engine_(engine),
      initial_pixel_ratio_(pixel_ratio),
      maximum_cache_size_(maximum_cache_size),
      header_rules_(std::move(header_rules)),
      callback_(callback) {}

MapTexture::~MapTexture() {
  // Dispose() joins the thread; this only covers a failed Start().
  if (thread_.joinable()) {
    commands_.Push(Command::Dispose());
    Signal();
    thread_.join();
  }
}

bool MapTexture::Start(bool copy_free, std::string* out_error) {
  std::string target_error;
  target_ = CreatePlatformRenderTarget(weak_from_this(), copy_free, engine_,
                                       &target_error);
  if (!target_) {
    *out_error = target_error.empty() ? "failed to create the render target"
                                      : target_error;
    return false;
  }
  if (auto* surface = target_->AsSurfaceTarget()) {
    // Flutter doesn't report when it has finished with an image.
    buffers_.Configure(surface->slot_count(),
                       BufferState::ReleaseRule::kLaterChoices);
    buffers_.set_on_freed([surface](int slot) { surface->SlotFreed(slot); });
  }
  thread_ = std::thread([this] { Run(); });
  std::unique_lock lock(init_mutex_);
  init_cv_.wait(lock, [this] { return init_done_; });
  if (!init_ok_) {
    thread_.join();
    target_->Unregister();
    *out_error = init_error_.empty() ? "map creation failed" : init_error_;
    return false;
  }
  return true;
}

int MapTexture::slot_count() const { return target_->slot_count(); }

int64_t MapTexture::texture_id(int slot) const {
  return target_->texture_id(slot);
}

void MapTexture::LoadStyleUrl(std::string url) {
  commands_.Push(Command::StyleUrl(std::move(url)));
  Signal();
}

void MapTexture::LoadStyleJson(std::string json) {
  commands_.Push(Command::StyleJson(std::move(json)));
  Signal();
}

void MapTexture::SetCamera(const Camera& camera, int64_t seq) {
  commands_.SetCamera(camera, seq, NowNs());
  Signal();
}

void MapTexture::Resize(const Viewport& viewport) {
  TargetSize size;
  if (SizeForViewport(viewport, &size)) target_->WillResize(size);
  commands_.Push(Command::Resize(viewport));
  Signal();
}

void MapTexture::SetDisplayRefreshRate(double hz) {
  display_interval_ns_.store(
      hz > 0 && std::isfinite(hz) ? static_cast<int64_t>(1e9 / hz) : 0);
}

void MapTexture::ReduceMemoryUse() {
  commands_.Push(Command::ReduceMemoryUse());
  Signal();
}

void MapTexture::SetFeatureState(FeatureStateTarget feature,
                                 std::string state) {
  commands_.Push(Command::SetFeatureState(std::move(feature), std::move(state)));
  feature_state_queued_.fetch_add(1);
  Signal();
}

void MapTexture::RemoveFeatureState(FeatureStateTarget feature) {
  commands_.Push(Command::RemoveFeatureState(std::move(feature)));
  feature_state_queued_.fetch_add(1);
  Signal();
}

void MapTexture::OverlaySetSource(int64_t id, int32_t source_index,
                                  int32_t source_options,
                                  std::shared_ptr<PreparedGeoJson> data) {
  commands_.Push(
      Command::OverlaySetSource(id, source_index, source_options, std::move(data)));
  Signal();
}

void MapTexture::OverlayRemoveSource(int64_t id, int32_t source_index) {
  commands_.Push(Command::OverlayRemoveSource(id, source_index));
  Signal();
}

void MapTexture::OverlaySetLayers(int64_t id, std::vector<std::string> layers,
                                  std::vector<int32_t> layer_sources,
                                  Placement placement, OrderKey order) {
  commands_.Push(Command::OverlaySetLayers(id, std::move(layers),
                                           std::move(layer_sources),
                                           std::move(placement), order));
  Signal();
}

void MapTexture::OverlayRemove(int64_t id) {
  commands_.Push(Command::OverlayRemove(id));
  Signal();
}

void MapTexture::QueryRenderedFeatures(RenderedQuery query) {
  {
    std::lock_guard lock(queries_mutex_);
    queries_.push_back(std::move(query));
    feature_state_queued_before_queries_ = feature_state_queued_.load();
  }
  Signal();
}

void MapTexture::SetPaused(bool paused) {
  gate_.SetPaused(paused);
  if (!paused) Signal();
}

void MapTexture::RunTargetTask(TargetTask task, bool wait) {
  auto done = wait ? std::make_shared<TaskDone>() : nullptr;
  // The command runs the task on the map thread. If the map thread stops
  // first, destroying the command (with the queue, or in Teardown) still
  // ends the wait.
  struct Completion {
    std::shared_ptr<TaskDone> done;
    ~Completion() {
      if (done) done->Set();
    }
  };
  auto completion = std::make_shared<Completion>();
  completion->done = done;
  {
    std::lock_guard lock(target_tasks_mutex_);
    if (target_tasks_stopped_) return;
    commands_.Push(Command::TargetTask(
        [this, task = std::move(task), completion = std::move(completion)] {
          task(session_, size_);
          // A task replaces or removes the surface, so the images of frames
          // queued on the previous one may never arrive; their slots are
          // freed, and the pending render no longer waits for them.
          buffers_.ReleaseQueued();
          waiting_for_buffer_.store(false);
          // The next demand renders the pending frame unconditionally. A task
          // that replaces the target also makes the session run an
          // outstanding demand again.
          repaint_wanted_ = true;
        }));
  }
  Signal();
  if (!done) return;
  std::unique_lock lock(done->mutex);
  done->cv.wait(lock, [&] { return done->done; });
}

void MapTexture::ReportRenderError(const std::string& message) {
  Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, message.c_str());
}

void MapTexture::Dispose() {
  {
    std::lock_guard lock(callback_mutex_);
    callback_ = nullptr;
  }
  if (thread_.joinable()) {
    commands_.Push(Command::Dispose());
    Signal();
    thread_.join();
  }
  target_->Unregister();
}

void MapTexture::Signal() {
  {
    std::lock_guard lock(wake_mutex_);
    woken_ = true;
  }
  wake_cv_.notify_one();
}

// The FFI requires that a wake callback returns without waiting for another
// thread. wake_mutex_ is held only briefly, and never while calling the FFI.
void MapTexture::OnWake(void* user_data) {
  static_cast<MapTexture*>(user_data)->Signal();
}

void MapTexture::WaitForWake(int64_t timeout_ms) {
  std::unique_lock lock(wake_mutex_);
  wake_cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                    [this] { return woken_; });
  woken_ = false;
}

bool MapTexture::SelectNewest(int* out_slot, FrameInfo* out_info) {
  if (auto* surface = target_->AsSurfaceTarget()) {
    int slot = buffers_.SelectNewest([&](int index, const FrameInfo& info) {
      *out_info = info;
      surface->FrameAvailable(index);
    });
    if (slot < 0) return false;
    *out_slot = slot;
    int64_t now = NowNs();
    selected_at_ns_.store(now);
    int64_t published = published_at_ns_.load();
    {
      std::lock_guard lock(stats_mutex_);
      ++stats_.presented_frames;
      if (published != 0) {
        ++stats_.pickup_wait_count;
        stats_.pickup_wait_total_ns += now - published;
      }
    }
    Emit(MAP_TEXTURE_EVENT_FRAME_DISPLAYED, nullptr, out_info, -1, slot);
    if (waiting_for_buffer_.exchange(false)) Signal();
    return true;
  }
  auto* target = target_->AsBufferTarget();
  // The first choice of a frame of a new set releases the frame kept from
  // before the resize.
  int slot = buffers_.SelectNewest([&](int, const FrameInfo& info) {
    *out_info = info;
    target->ReleaseFallbackLocked();
  });
  if (slot < 0) return false;
  *out_slot = slot;
  selected_at_ns_.store(NowNs());
  target->FrameAvailable(slot);
  if (waiting_for_buffer_.exchange(false)) Signal();
  return true;
}

void MapTexture::ResetSlots() {
  buffers_.WithLock([this](int) { buffers_.ResetLocked(); });
}

bool MapTexture::OnFrameImage(
    uint64_t frame_id, const std::function<void(int slot)>& on_published) {
  FrameInfo info;
  bool known = false;
  int slot = -1;
  switch (buffers_.OnImage(frame_id, &slot, &info, &known, on_published)) {
    case BufferState::ImageResult::kPublished:
      published_at_ns_.store(NowNs());
      RecordCameraLatency(info);
      Emit(MAP_TEXTURE_EVENT_FRAME_READY, nullptr, &info, 0, slot);
      // Publishing frees the slots of the replaced ready and queued frames.
      if (waiting_for_buffer_.exchange(false)) Signal();
      return true;
    case BufferState::ImageResult::kEarly:
      // The map thread publishes the frame when its render returns.
      return true;
    case BufferState::ImageResult::kUnknown:
      break;
  }
  // An image of a frame that was replaced or reset is expected; one that no
  // slot ever expected means that the frame id didn't reach the image.
  if (!known && !unknown_frame_reported_.exchange(true)) {
    ReportRenderError("received an image of unknown frame " +
                      std::to_string(frame_id));
  }
  return false;
}

void* MapTexture::Present(int slot) {
  auto* target = target_->AsBufferTarget();
  if (target == nullptr) return nullptr;
  void* buffer = nullptr;
  auto presented = buffers_.Present(slot, [&](const BufferState::Presented& p) {
    buffer = target->CopyBufferLocked(p.index);
  });
  if (presented.is_new) {
    int64_t now = NowNs();
    presented_at_ns_.store(now);
    int64_t published = published_at_ns_.load();
    {
      std::lock_guard lock(stats_mutex_);
      ++stats_.presented_frames;
      if (published != 0) {
        ++stats_.pickup_wait_count;
        stats_.pickup_wait_total_ns += now - published;
      }
    }
    Emit(MAP_TEXTURE_EVENT_FRAME_DISPLAYED, nullptr, &presented.info,
         presented.display_time_us, presented.index);
  }
  if (waiting_for_buffer_.exchange(false)) Signal();
  return buffer;
}

void MapTexture::RecordCameraLatency(const FrameInfo& info) {
  if (info.camera_set_at_ns == 0) return;
  int64_t latency = NowNs() - info.camera_set_at_ns;
  std::lock_guard lock(stats_mutex_);
  if (info.seq <= latency_counted_seq_) return;
  latency_counted_seq_ = info.seq;
  ++stats_.camera_latency_count;
  stats_.camera_latency_total_ns += latency;
  stats_.camera_latency_max_ns =
      std::max(stats_.camera_latency_max_ns, latency);
}

std::optional<RenderedView> MapTexture::LastRenderedViewForTesting() {
  std::lock_guard lock(rendered_view_mutex_);
  return rendered_view_;
}

map_texture_stats MapTexture::stats() {
  int max_in_use = buffers_.max_in_use();
  std::lock_guard lock(stats_mutex_);
  map_texture_stats stats = stats_;
  stats.max_slots_in_use = max_in_use;
  return stats;
}

// Map thread.

void MapTexture::Run() {
  MapThreadOwnerScope owner(this);
  bool ok = false;
  RunInPlatformScope([&] { ok = Init(); });
  {
    std::lock_guard lock(init_mutex_);
    init_done_ = true;
    init_ok_ = ok;
  }
  init_cv_.notify_all();
  if (!ok) {
    RunInPlatformScope([&] { Teardown(); });
    return;
  }

  bool stop = false;
  while (!stop) {
    RunInPlatformScope([&] { stop = RunOnce(); });
  }
  RunInPlatformScope([&] { Teardown(); });
}

// The map thread arms one frame demand at a time. The demand waits for the
// map's next update, so a slot is taken for it as soon as one may be rendered.
bool MapTexture::RenderWanted() {
  if (demand_outstanding_ || session_ == MLN_HANDLE_NULL || gate_.paused()) {
    return false;
  }
  if (auto* surface = target_->AsSurfaceTarget()) {
    if (!surface->CanPresent()) return false;
  }
  return !waiting_for_buffer_.load();
}

bool MapTexture::RunOnce() {
  bool render_now = RenderWanted();
  int64_t timeout_ms = render_now ? 0 : kIdleWaitMs;
  if (render_now && target_->AsSurfaceTarget() != nullptr) {
    // A surface target's render waits for the end of the refresh interval.
    // The wait parks in whole milliseconds, so the part of the wait below one
    // millisecond is slept here.
    int64_t remaining = IntervalRemainingNs();
    if (remaining > 0 && remaining < 1'000'000) {
      std::this_thread::sleep_for(std::chrono::nanoseconds(remaining));
    } else {
      timeout_ms = remaining / 1'000'000;
    }
  }
  if (notify_after_resize_at_ns_ != 0) {
    int64_t until_ms = (notify_after_resize_at_ns_ - NowNs()) / 1'000'000;
    timeout_ms = std::clamp<int64_t>(until_ms, 0, timeout_ms);
  }
  WaitForWake(timeout_ms);
  bool stop = false;
  ApplyCommands(&stop);
  if (stop) return true;
  SyncOverlays();
  ApplyCamera();
  WaitForCamera();
  ServiceDriver();
  RunQueries();
  // A layer list that arrived while the camera was waited for or the driver
  // serviced is reconciled before the frame is requested.
  SyncOverlays();
  MaybeRender();
  // A newly armed demand renders at once if the map has an update.
  ServiceDriver();
  MaybeNotifyAfterResize();
  return false;
}

// Workaround for Flutter's Darwin embedders (see
// docs/flutter-texture-cache-followup.md): Flutter wraps each pixel buffer it
// displays through its own CVMetalTextureCache and never flushes it per frame.
// The cache frees an entry only when it creates another texture after the
// entry's maximum age has passed, so after a series of resizes it keeps the
// replaced buffers alive until the next new frame, which on an idle map can be
// much later. Telling Flutter once more that a frame is available for each
// slot's texture, after the maximum age, makes it create a texture and free
// them.
void MapTexture::MaybeNotifyAfterResize() {
  if (notify_after_resize_at_ns_ == 0 || NowNs() < notify_after_resize_at_ns_ ||
      gate_.paused()) {
    return;
  }
  notify_after_resize_at_ns_ = 0;
  target_->AsBufferTarget()->FrameAvailable();
}

bool MapTexture::Init() {
  std::string cache_path = PlatformCachePath();
  // Without a path, MapLibre's default root makes asset:// URLs fail.
  std::string asset_path = PlatformAssetPath();
  mln_runtime_options runtime_options = mln_runtime_options_default();
  if (!cache_path.empty()) runtime_options.cache_path = View(cache_path);
  if (!asset_path.empty()) runtime_options.asset_path = View(asset_path);

  // Installed once for the process, before the first map loads a style. The
  // callback is process-global, so it replaces any other that the app set
  // through the FFI. If the call fails, the map renders without reporting
  // glyph failures.
  std::call_once(log_callback_once, [this] {
    mln_log_handler handler{};
    handler.size = sizeof(handler);
    handler.callback = &MapTexture::OnLogRecord;
    mln_diagnostic diagnostic = NewDiagnostic();
    mln_status log_status = mln_log_set_callback(&handler, &diagnostic);
    if (log_status != MLN_STATUS_OK) {
      ReportStatus("mln_log_set_callback", log_status, &diagnostic);
    }
  });

  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      mln_runtime_create(&runtime_options, &runtime_, &diagnostic);
  if (status != MLN_STATUS_OK) {
    ReportInitStatus("mln_runtime_create", status, &diagnostic);
    return false;
  }

  // Before the map, so that the handler receives its first events. The
  // runtime calls it on its scheduler thread.
  mln_runtime_event_handler handler{};
  handler.size = sizeof(handler);
  handler.callback = &MapTexture::OnEvents;
  handler.user_data = this;
  mln_completion handler_done =
      ReportingCompletion("mln_runtime_set_event_handler");
  status = mln_runtime_set_event_handler(runtime_, &handler, &handler_done,
                                         &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(handler_done);
    ReportInitStatus("mln_runtime_set_event_handler", status, &diagnostic);
    return false;
  }

  // Runtime operations run in order, so the maximum size is in effect before
  // the first resource request or write of the style load. If the call fails,
  // the map uses MapLibre's default and continues to render.
  if (maximum_cache_size_) {
    mln_completion size_done =
        ReportingCompletion("mln_runtime_set_maximum_ambient_cache_size");
    status = mln_runtime_set_maximum_ambient_cache_size(
        runtime_, *maximum_cache_size_, &size_done, &diagnostic);
    if (status != MLN_STATUS_OK) {
      DiscardFunctionCompletion(size_done);
      ReportStatus("mln_runtime_set_maximum_ambient_cache_size", status,
                   &diagnostic);
    }
  }

  // Before the map, so that style requests carry the headers. The runtime
  // applies the rules in native code; the call copies them.
  if (!header_rules_.empty()) {
    std::vector<mln_http_header> headers;
    for (const auto& rule : header_rules_) {
      for (const auto& [name, value] : rule.headers) {
        headers.push_back({View(name), View(value)});
      }
    }
    std::vector<mln_http_header_rule> rules;
    size_t first_header = 0;
    for (const auto& rule : header_rules_) {
      mln_http_header_rule transform_rule = mln_http_header_rule_default();
      transform_rule.kinds = MLN_RESOURCE_KIND_MASK_ALL;
      transform_rule.flags = MLN_URL_MATCH_GLOB;
      transform_rule.url = View(rule.url);
      transform_rule.headers =
          rule.headers.empty() ? nullptr : headers.data() + first_header;
      transform_rule.header_count = rule.headers.size();
      rules.push_back(transform_rule);
      first_header += rule.headers.size();
    }
    mln_http_header_transform transform{};
    transform.size = sizeof(transform);
    transform.rules = rules.data();
    transform.rule_count = rules.size();
    mln_completion transform_done =
        ReportingCompletion("mln_runtime_set_http_header_transform");
    status = mln_runtime_set_http_header_transform(runtime_, &transform,
                                                   &transform_done, &diagnostic);
    if (status != MLN_STATUS_OK) {
      DiscardFunctionCompletion(transform_done);
      ReportInitStatus("mln_runtime_set_http_header_transform", status,
                       &diagnostic);
      return false;
    }
  }

  mln_map_options map_options = mln_map_options_default();
  map_options.initial_extent.width = 256;
  map_options.initial_extent.height = 256;
  map_options.initial_extent.scale_factor = initial_pixel_ratio_;
  map_options.event_mask = kMapEventMask;
  auto created = std::make_shared<Waiter>();
  mln_completion create_done = Waiter::For(created);
  status = mln_runtime_create_map(runtime_, &map_options, &create_done,
                                  &diagnostic);
  if (status != MLN_STATUS_OK) {
    Waiter::Discard(create_done);
    ReportInitStatus("mln_runtime_create_map", status, &diagnostic);
    return false;
  }
  created->WaitFor(30'000'000'000);
  if (!created->Done() || created->status != MLN_STATUS_OK ||
      created->value.size() < sizeof(mln_map)) {
    init_error_ = "mln_runtime_create_map failed: " + created->diagnostic;
    Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, init_error_.c_str());
    return false;
  }
  std::memcpy(&map_, created->value.data(), sizeof(mln_map));
  return true;
}

void MapTexture::ServiceUntil(const std::function<bool()>& done) {
  while (!done()) {
    if (session_ != MLN_HANDLE_NULL) {
      // Any service call can render the armed demand's frame, for example
      // after a replacement resumes a demand that waits for an update, so a
      // surface target gets the frame's id before this one too.
      if (auto* surface = target_->AsSurfaceTarget();
          surface != nullptr && demand_outstanding_ && !demand_stale_) {
        surface->WillRender(next_frame_id_);
      }
      mln_status status =
          mln_render_session_service_driver_work(session_, nullptr);
      if (status != MLN_STATUS_OK && status != MLN_STATUS_BUSY) break;
    }
    if (done()) break;
    WaitForWake(1);
  }
}

void MapTexture::DestroySession() {
  if (session_ != MLN_HANDLE_NULL) {
    // A detach is refused while a frame is acquired.
    ReleaseHeldFrames(true);
    mln_diagnostic diagnostic = NewDiagnostic();
    auto detached = std::make_shared<Waiter>();
    mln_completion detach_done = Waiter::For(detached);
    mln_status status =
        mln_render_session_detach(session_, &detach_done, &diagnostic);
    if (status == MLN_STATUS_OK) {
      ServiceUntil([&] { return detached->Done(); });
    } else {
      Waiter::Discard(detach_done);
      mln_render_abandon_result abandoned{};
      abandoned.size = sizeof(abandoned);
      mln_render_session_abandon(session_, &abandoned, nullptr);
    }
    mln_render_session_release(session_, nullptr);
    session_ = MLN_HANDLE_NULL;
    demand_outstanding_ = false;
    demand_slot_ = -1;
  }
  if (auto* surface = target_->AsSurfaceTarget()) {
    surface->ReleaseSurfaces();
    return;
  }
  buffers_.WithLock([this](int) {
    target_->AsBufferTarget()->ReleaseBuffersLocked();
    buffers_.ResetLocked();
  });
}

void MapTexture::Teardown() {
  // Commands queued after the dispose don't run; dropping them ends the wait
  // of a target task.
  {
    std::lock_guard lock(target_tasks_mutex_);
    target_tasks_stopped_ = true;
    commands_.TakeAll();
  }
  DestroySession();
  // Waiting for each release completion ensures that no completion or event
  // callback runs into this object afterwards.
  if (map_ != MLN_HANDLE_NULL) {
    auto released = std::make_shared<Waiter>();
    mln_completion release_done = Waiter::For(released);
    if (mln_map_release(map_, &release_done, nullptr) == MLN_STATUS_OK) {
      released->WaitFor(30'000'000'000);
    } else {
      Waiter::Discard(release_done);
      mln_map_dispose(map_, nullptr);
    }
    map_ = MLN_HANDLE_NULL;
  }
  if (runtime_ != MLN_HANDLE_NULL) {
    auto released = std::make_shared<Waiter>();
    mln_completion release_done = Waiter::For(released);
    if (mln_runtime_release(runtime_, &release_done, nullptr) ==
        MLN_STATUS_OK) {
      released->WaitFor(30'000'000'000);
    } else {
      Waiter::Discard(release_done);
      mln_runtime_dispose(runtime_, nullptr);
    }
    runtime_ = MLN_HANDLE_NULL;
  }
}

void MapTexture::ApplyCommands(bool* stop) {
  for (auto& command : commands_.TakeAll()) {
    switch (command.kind) {
      // Commands with a discarded completion: a style that fails to load
      // queues a loading-failed event, which carries the message.
      case Command::Kind::kStyleUrl: {
        mln_diagnostic diagnostic = NewDiagnostic();
        mln_status status = mln_map_set_style_url(map_, View(command.text),
                                                  nullptr, &diagnostic);
        if (status != MLN_STATUS_OK) {
          ReportStatus("mln_map_set_style_url", status, &diagnostic);
        }
        ++style_commands_;
        break;
      }
      case Command::Kind::kStyleJson: {
        mln_diagnostic diagnostic = NewDiagnostic();
        mln_status status = mln_map_set_style_json(map_, View(command.text),
                                                   nullptr, &diagnostic);
        if (status != MLN_STATUS_OK) {
          ReportStatus("mln_map_set_style_json", status, &diagnostic);
        }
        ++style_commands_;
        break;
      }
      case Command::Kind::kResize:
        ApplyResize(command.viewport);
        break;
      case Command::Kind::kReduceMemoryUse:
        ApplyReduceMemoryUse();
        break;
      case Command::Kind::kSetFeatureState:
      case Command::Kind::kRemoveFeatureState:
        ApplyFeatureState(command);
        break;
      case Command::Kind::kOverlaySetSource:
      case Command::Kind::kOverlayRemoveSource:
      case Command::Kind::kOverlaySetLayers:
      case Command::Kind::kOverlayRemove:
        ApplyOverlayCommand(command);
        break;
      case Command::Kind::kTargetTask:
        command.task();
        break;
      case Command::Kind::kDispose:
        *stop = true;
        return;
    }
  }
}

void MapTexture::ApplyFeatureState(const Command& command) {
  ++feature_state_applied_;
  const FeatureStateTarget& feature = command.feature;
  mln_feature_state_selector selector{};
  selector.size = sizeof(selector);
  selector.source_id = View(feature.source_id);
  if (feature.source_layer_id) {
    selector.fields |= MLN_FEATURE_STATE_SELECTOR_SOURCE_LAYER_ID;
    selector.source_layer_id = View(*feature.source_layer_id);
  }
  if (feature.feature_id) {
    selector.fields |= MLN_FEATURE_STATE_SELECTOR_FEATURE_ID;
    selector.feature_id = View(*feature.feature_id);
  }
  if (feature.key) {
    selector.fields |= MLN_FEATURE_STATE_SELECTOR_STATE_KEY;
    selector.state_key = View(*feature.key);
  }
  bool set = command.kind == Command::Kind::kSetFeatureState;
  const char* what =
      set ? "mln_map_set_feature_state" : "mln_map_remove_feature_state";
  mln_completion done = ReportingCompletion(
      what,
      [this](const mln_completion_result& result) {
        uint64_t generation = result.render_update_generation;
        uint64_t newest = feature_state_generation_.load();
        while (generation > newest &&
               !feature_state_generation_.compare_exchange_weak(newest,
                                                                generation)) {
        }
      },
      [this] {
        feature_state_completed_.fetch_add(1);
        Signal();
      });
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      set ? mln_map_set_feature_state(map_, &selector, View(command.text),
                                      &done, &diagnostic)
          : mln_map_remove_feature_state(map_, &selector, &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus(what, status, &diagnostic);
    return;
  }
  ++feature_state_submitted_;
}

void MapTexture::ApplyOverlayCommand(Command& command) {
  OverlayCommand& update = command.overlay;
  overlays_dirty_ = true;
  if (command.kind == Command::Kind::kOverlayRemove) {
    auto it = overlays_.find(update.id);
    if (it == overlays_.end()) return;
    Overlay& overlay = it->second;
    for (auto& [index, source] : overlay.sources) {
      if (source.submitted) {
        overlay_sources_to_remove_.push_back(OverlaySourceId(update.id, index));
      }
    }
    overlay_sources_to_remove_.insert(overlay_sources_to_remove_.end(),
                                      overlay.sources_to_remove.begin(),
                                      overlay.sources_to_remove.end());
    overlays_.erase(it);
    return;
  }
  if (command.kind == Command::Kind::kOverlayRemoveSource) {
    auto it = overlays_.find(update.id);
    if (it == overlays_.end()) return;
    auto source = it->second.sources.find(update.source_index);
    if (source == it->second.sources.end()) return;
    if (source->second.submitted) {
      it->second.sources_to_remove.push_back(
          OverlaySourceId(update.id, update.source_index));
    }
    it->second.sources.erase(source);
    return;
  }
  Overlay& overlay = overlays_[update.id];
  if (command.kind == Command::Kind::kOverlaySetSource) {
    OverlaySource& source = overlay.sources[update.source_index];
    source.data = std::move(update.data);
    source.options = update.source_options;
    ++source.data_version;
    return;
  }
  // Unchanged layers with a new placement or order are moved, not added again.
  if (overlay.layers != update.layers) {
    overlay.layers = std::move(update.layers);
    overlay.layer_sources = std::move(update.layer_sources);
    ++overlay.layers_version;
  }
  overlay.placement = std::move(update.placement);
  overlay.order = update.order;
}

namespace {

// The layer IDs and types of a completed mln_map_list_style_layers().
std::vector<StyleLayer> LayersOf(const mln_completion_result& result) {
  std::vector<StyleLayer> layers;
  const auto* base = static_cast<const char*>(result.value);
  for (size_t i = 0; i < result.value_count; ++i) {
    const auto& info = *reinterpret_cast<const mln_style_layer_info*>(
        base + i * result.value_size);
    layers.push_back({std::string(ViewOf(info.id)), std::string(ViewOf(info.type))});
  }
  return layers;
}

}  // namespace

void MapTexture::SyncOverlays() {
  uint64_t loads = style_loads_.load();
  if (loads != style_loads_seen_) {
    style_loads_seen_ = loads;
    style_loaded_ = true;
    missing_anchors_reported_.clear();
    for (auto& [id, overlay] : overlays_) {
      for (auto& [index, source] : overlay.sources) source.submitted = false;
      overlay.sources_to_remove.clear();
    }
    overlay_sources_to_remove_.clear();
    overlays_dirty_ = true;
  }
  std::optional<LayerList> list;
  {
    std::lock_guard lock(layer_list_mutex_);
    list = std::exchange(layer_list_, std::nullopt);
  }
  if (list) {
    layer_list_pending_ = false;
    if (layer_list_style_commands_ != style_commands_ ||
        layer_list_style_loads_ != style_loads_seen_) {
      overlays_dirty_ = true;
    } else if (list->status != MLN_STATUS_OK) {
      Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
           StatusMessage("mln_map_list_style_layers",
                         static_cast<mln_status>(list->status),
                         list->diagnostic.c_str())
               .c_str());
    } else {
      ReconcileOverlays(list->layers);
    }
  }
  bool work = !overlays_.empty() || !overlay_sources_to_remove_.empty();
  if (overlays_dirty_ && !layer_list_pending_ && style_loaded_ && work) {
    overlays_dirty_ = false;
    RequestLayerList();
  }
}

void MapTexture::RequestLayerList() {
  mln_completion done =
      FunctionCompletion([this](const mln_completion_result& result) {
        LayerList list;
        list.status = result.status;
        if (result.status == MLN_STATUS_OK) {
          list.layers = LayersOf(result);
        } else {
          list.diagnostic = std::string(ViewOf(result.diagnostic));
        }
        {
          std::lock_guard lock(layer_list_mutex_);
          layer_list_ = std::move(list);
        }
        Signal();
      });
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status = mln_map_list_style_layers(map_, &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus("mln_map_list_style_layers", status, &diagnostic);
    return;
  }
  layer_list_pending_ = true;
  layer_list_style_commands_ = style_commands_;
  layer_list_style_loads_ = style_loads_seen_;
}

void MapTexture::ReconcileOverlays(const std::vector<StyleLayer>& layers) {
  std::vector<OverlayLayout> layouts;
  for (auto& [id, overlay] : overlays_) {
    bool shown = !overlay.layers.empty();
    for (int32_t index : overlay.layer_sources) {
      shown = shown && overlay.sources.count(index) > 0;
    }
    if (shown) {
      // Layers are added again when they changed, and when a submitted
      // source needs adding again, which needs the layers that name it
      // removed.
      bool readd = overlay.layers_version != overlay.layers_submitted;
      for (auto& [index, source] : overlay.sources) {
        readd = readd || (source.submitted &&
                          source.submitted_options != source.options);
      }
      OverlayLayout layout{id, overlay.order, overlay.placement, {}, readd};
      for (size_t i = 0; i < overlay.layers.size(); ++i) {
        layout.layer_ids.push_back(OverlayLayerId(id, i));
      }
      layouts.push_back(std::move(layout));
    } else {
      for (auto& [index, source] : overlay.sources) {
        if (!source.submitted) continue;
        overlay_sources_to_remove_.push_back(OverlaySourceId(id, index));
        source.submitted = false;
      }
      overlay_sources_to_remove_.insert(overlay_sources_to_remove_.end(),
                                        overlay.sources_to_remove.begin(),
                                        overlay.sources_to_remove.end());
      overlay.sources_to_remove.clear();
    }
  }
  LayerPlan plan = PlanLayers(layers, layouts);

  // Layers first: a source with a layer can't be removed.
  for (const std::string& id : plan.remove_stale) RemoveOverlayLayer(id);
  for (const std::string& id : overlay_sources_to_remove_) RemoveOverlaySource(id);
  overlay_sources_to_remove_.clear();

  for (const std::string& id : plan.missing_layer_ids) {
    if (missing_anchors_reported_.insert(id).second) {
      Emit(MAP_TEXTURE_EVENT_LOADING_FAILED,
           ("the style has no layer \"" + id + "\" to place an overlay below")
               .c_str());
    }
  }

  // New sources before the layers that name them.
  for (const OverlayLayout& layout : layouts) {
    AddOverlaySources(layout.id, overlays_.at(layout.id), false);
  }

  for (const OverlayStep& step : plan.steps) {
    Overlay& overlay = overlays_.at(step.id);
    for (const std::string& id : step.remove_first) RemoveOverlayLayer(id);
    // The overlay's layers aren't in the style after an install or a
    // replacement, so a source whose options changed can be added again.
    if (step.action != OverlayAction::kMove) {
      AddOverlaySources(step.id, overlay, true);
    }
    for (size_t i = 0; i < overlay.layers.size(); ++i) {
      std::string layer_id = OverlayLayerId(step.id, i);
      bool move = step.action == OverlayAction::kMove;
      const char* what =
          move ? "mln_map_move_style_layer" : "mln_map_add_style_layer_json";
      mln_completion done = OverlayCompletion(what, layer_id, false);
      mln_diagnostic diagnostic = NewDiagnostic();
      mln_status status =
          move ? mln_map_move_style_layer(map_, View(layer_id), View(step.before),
                                          &done, &diagnostic)
               : mln_map_add_style_layer_json(map_, View(overlay.layers[i]),
                                              View(step.before), &done,
                                              &diagnostic);
      if (status != MLN_STATUS_OK) {
        DiscardFunctionCompletion(done);
        ReportStatus(what, status, &diagnostic);
      }
    }
    overlay.layers_submitted = overlay.layers_version;
  }

  // Sources that no layer names any more, after the layers that named them
  // were removed above, and data of the sources that stay.
  for (const OverlayLayout& layout : layouts) {
    Overlay& overlay = overlays_.at(layout.id);
    for (const std::string& id : overlay.sources_to_remove) RemoveOverlaySource(id);
    overlay.sources_to_remove.clear();
    for (auto& [index, source] : overlay.sources) {
      if (source.data_version == source.data_submitted) continue;
      std::string source_id = OverlaySourceId(layout.id, index);
      mln_completion done =
          OverlayCompletion("mln_map_set_geojson_source_data", source_id, true);
      mln_diagnostic diagnostic = NewDiagnostic();
      mln_status status = mln_map_set_geojson_source_data(
          map_, View(source_id), source.data->handle, &done, &diagnostic);
      if (status != MLN_STATUS_OK) {
        DiscardFunctionCompletion(done);
        ReportStatus("mln_map_set_geojson_source_data", status, &diagnostic);
      }
      source.data_submitted = source.data_version;
    }
  }
}

void MapTexture::AddOverlaySources(int64_t id, Overlay& overlay,
                                   bool readd_changed_options) {
  for (auto& [index, source] : overlay.sources) {
    bool again =
        readd_changed_options && source.submitted_options != source.options;
    if (!source.submitted || again) AddOverlaySource(id, index, source);
  }
}

void MapTexture::AddOverlaySource(int64_t id, int32_t index,
                                  OverlaySource& source) {
  std::string source_id = OverlaySourceId(id, index);
  if (source.submitted) RemoveOverlaySource(source_id);
  mln_completion done =
      OverlayCompletion("mln_map_add_geojson_source_data", source_id, false);
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status = mln_map_add_geojson_source_data(
      map_, View(source_id), source.data->handle, &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus("mln_map_add_geojson_source_data", status, &diagnostic);
  }
  source.submitted = true;
  source.submitted_options = source.options;
  source.data_submitted = source.data_version;
}

mln_completion MapTexture::OverlayCompletion(const char* what,
                                             const std::string& target,
                                             bool ignore_not_found) {
  std::string operation = std::string(what) + " (" + target + ")";
  return FunctionCompletion([this, operation = std::move(operation),
                             ignore_not_found](const mln_completion_result& result) {
    if (result.status == MLN_STATUS_OK ||
        (ignore_not_found && result.status == MLN_STATUS_NOT_FOUND)) {
      return;
    }
    Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
         StatusMessage(operation.c_str(), static_cast<mln_status>(result.status),
                       std::string(ViewOf(result.diagnostic)).c_str())
             .c_str());
  });
}

void MapTexture::RemoveOverlayLayer(const std::string& id) {
  mln_completion done = OverlayCompletion("mln_map_remove_style_layer", id, true);
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status = mln_map_remove_style_layer(map_, View(id), &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus("mln_map_remove_style_layer", status, &diagnostic);
  }
}

void MapTexture::RemoveOverlaySource(const std::string& id) {
  mln_completion done = OverlayCompletion("mln_map_remove_style_source", id, true);
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      mln_map_remove_style_source(map_, View(id), &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus("mln_map_remove_style_source", status, &diagnostic);
  }
}

std::optional<std::vector<StyleLayerInfo>>
MapTexture::ListStyleLayersForTesting() {
  struct Result {
    std::mutex mutex;
    std::condition_variable cv;
    bool done = false;
    std::optional<std::vector<StyleLayerInfo>> layers;
  };
  auto result = std::make_shared<Result>();
  mln_completion done =
      FunctionCompletion([result](const mln_completion_result& completed) {
        std::vector<StyleLayerInfo> layers;
        const auto* base = static_cast<const char*>(completed.value);
        for (size_t i = 0; i < completed.value_count; ++i) {
          const auto& info = *reinterpret_cast<const mln_style_layer_info*>(
              base + i * completed.value_size);
          layers.push_back({std::string(ViewOf(info.id)),
                            std::string(ViewOf(info.type)),
                            std::string(ViewOf(info.source_id))});
        }
        {
          std::lock_guard lock(result->mutex);
          if (completed.status == MLN_STATUS_OK) result->layers = std::move(layers);
          result->done = true;
        }
        result->cv.notify_all();
      });
  if (mln_map_list_style_layers(map_, &done, nullptr) != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    return std::nullopt;
  }
  std::unique_lock lock(result->mutex);
  result->cv.wait_for(lock, std::chrono::seconds(5), [&] { return result->done; });
  return result->layers;
}

void MapTexture::ApplyReduceMemoryUse() {
  if (session_ == MLN_HANDLE_NULL) return;
  // This releases cached tiles and images. It is driver work, which the map
  // thread services, also while rendering is paused.
  mln_completion done = FunctionCompletion(
      [this](const mln_completion_result& result) {
        if (result.status == MLN_STATUS_OK) {
          std::lock_guard lock(stats_mutex_);
          ++stats_.memory_reductions;
        }
      });
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      mln_render_session_reduce_memory_use(session_, &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus("mln_render_session_reduce_memory_use", status, &diagnostic);
  }
}

void MapTexture::ApplyResize(const Viewport& viewport) {
  TargetSize size;
  if (!SizeForViewport(viewport, &size)) return;
  viewport_ = viewport;
  if (session_ != MLN_HANDLE_NULL &&
      size.physical_width == size_.physical_width &&
      size.physical_height == size_.physical_height &&
      size.extent.scale_factor == size_.extent.scale_factor) {
    return;
  }

  if (auto* buffer_target = target_->AsBufferTarget()) {
    if (!buffer_target->PrepareBuffers(size)) {
      Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, "failed to allocate texture buffers");
      return;
    }
    // A demand armed before the resize could render into the replaced set
    // after its buffers are freed, so the barrier ends it first. A
    // replacement is refused while a frame is acquired, and the frames are
    // released while their textures exist. The map thread requests no frame
    // before the replacement, so the session renders no frame into the
    // replaced set.
    if (session_ != MLN_HANDLE_NULL && demand_outstanding_) EndDemands();
    ReleaseHeldFrames(true);
    buffers_.WithLock([buffer_target, this](int chosen) {
      buffer_target->SwapBuffersLocked(chosen);
      buffers_.ResetLocked();
    });
    notify_after_resize_at_ns_ = NowNs() + kResizeSettledNs;
    // The armed demand's slot belongs to the replaced set.
    if (demand_outstanding_) demand_stale_ = true;
  }
  size_ = size;

  mln_diagnostic diagnostic = NewDiagnostic();
  if (session_ == MLN_HANDLE_NULL) {
    AttachSession();
  } else {
    // The previous textures are released already, so the replacement must
    // run before the session renders again.
    auto replaced = std::make_shared<Waiter>();
    mln_completion replace_done = Waiter::For(replaced);
    mln_status status =
        target_->SetTarget(session_, size_, {&replace_done, &diagnostic});
    if (status != MLN_STATUS_OK) {
      Waiter::Discard(replace_done);
      ReportStatus("set_target", status, &diagnostic);
      return;
    }
    ServiceUntil([&] { return replaced->Done(); });
    if (replaced->status != MLN_STATUS_OK) {
      Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
           ("set_target failed: " + replaced->diagnostic).c_str());
    }
  }
}

void MapTexture::EndDemands() {
  auto ended = std::make_shared<Waiter>();
  mln_completion barrier_done = Waiter::For(ended);
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      mln_render_session_barrier(session_, &barrier_done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    Waiter::Discard(barrier_done);
    ReportStatus("mln_render_session_barrier", status, &diagnostic);
    return;
  }
  ServiceUntil([&] { return ended->Done(); });
}

bool MapTexture::AttachSession() {
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_render_session_attach_options options =
      mln_render_session_attach_options_default();
  options.driver = MLN_RENDER_DRIVER_CALLER_GRAPHICS_THREAD;
  options.frame_wake = mln_wake{&MapTexture::OnWake, this, nullptr};
  options.driver_work_wake = mln_wake{&MapTexture::OnWake, this, nullptr};
  auto attached = std::make_shared<Waiter>();
  mln_completion attach_done = Waiter::For(attached);
  mln_status status = target_->Attach(map_, size_, options, &session_,
                                      {&attach_done, &diagnostic});
  if (status != MLN_STATUS_OK) {
    Waiter::Discard(attach_done);
    session_ = MLN_HANDLE_NULL;
    ReportStatus("attach", status, &diagnostic);
    return false;
  }
  // A caller-graphics-thread session completes its attachment in driver
  // work that the map thread services.
  ServiceUntil([&] { return attached->Done(); });
  if (attached->status != MLN_STATUS_OK) {
    Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
         ("attach failed: " + attached->diagnostic).c_str());
  }
  return attached->status == MLN_STATUS_OK;
}

// A failed render leaves the session in MLN_RENDER_SESSION_STATE_TARGET_LOST,
// which no target replacement leaves, so the map thread detaches the session
// and attaches a new one.
bool MapTexture::RecoverLostTarget() {
  if (session_ == MLN_HANDLE_NULL) return false;
  mln_render_session_snapshot snapshot{};
  snapshot.size = sizeof(snapshot);
  if (mln_render_session_get_snapshot(session_, &snapshot, nullptr) !=
          MLN_STATUS_OK ||
      snapshot.state != MLN_RENDER_SESSION_STATE_TARGET_LOST) {
    return false;
  }
  ReleaseHeldFrames(true);
  auto detached = std::make_shared<Waiter>();
  mln_completion detach_done = Waiter::For(detached);
  if (mln_render_session_detach(session_, &detach_done, nullptr) ==
      MLN_STATUS_OK) {
    ServiceUntil([&] { return detached->Done(); });
  } else {
    Waiter::Discard(detach_done);
    mln_render_abandon_result abandoned{};
    abandoned.size = sizeof(abandoned);
    mln_render_session_abandon(session_, &abandoned, nullptr);
  }
  mln_render_session_release(session_, nullptr);
  session_ = MLN_HANDLE_NULL;
  if (demand_outstanding_ && !demand_stale_ && demand_slot_ >= 0) {
    buffers_.Release(demand_slot_);
  }
  demand_outstanding_ = false;
  demand_slot_ = -1;
  demand_stale_ = false;
  repaint_wanted_ = true;
  return AttachSession();
}

void MapTexture::ApplyCamera() {
  auto update = commands_.TakeCamera();
  if (!update) return;
  const Camera& camera = update->camera;
  mln_camera_update camera_update = mln_camera_update_default();
  camera_update.mode = MLN_CAMERA_UPDATE_MODE_JUMP;
  camera_update.camera = mln_camera_options_default();
  camera_update.camera.fields =
      MLN_CAMERA_OPTION_CENTER | MLN_CAMERA_OPTION_ZOOM | MLN_CAMERA_OPTION_BEARING;
  camera_update.camera.center = {camera.latitude, camera.longitude};
  camera_update.camera.zoom = camera.zoom;
  camera_update.camera.bearing = camera.bearing;
  // The completion reports the render update that includes the camera, which
  // a frame result's map_update_generation counts.
  int64_t seq = update->seq;
  int64_t set_at_ns = update->set_at_ns;
  mln_completion done = FunctionCompletion(
      [this, seq, set_at_ns](const mln_completion_result& result) {
        if (result.status == MLN_STATUS_OK) {
          std::lock_guard lock(camera_generations_mutex_);
          camera_generations_.push_back(
              {result.render_update_generation, seq, set_at_ns});
        }
        // After the generation is recorded, so that a frame that the waiting
        // map thread renders next is matched to this camera.
        cameras_completed_.fetch_add(1);
        Signal();
      });
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      mln_map_update_camera(map_, &camera_update, &done, &diagnostic);
  if (status != MLN_STATUS_OK) {
    DiscardFunctionCompletion(done);
    ReportStatus("mln_map_update_camera", status, &diagnostic);
    return;
  }
  ++cameras_submitted_;
}

// Rendering before the camera's update is published would render the previous
// camera, which cost the iPhone one more display frame of lag.
// The completion signals the wake, so the map thread waits without spinning.
// Every command completes, and a dispose also signals the wake.
void MapTexture::WaitForCamera() {
  bool waited = false;
  while (cameras_completed_.load() < cameras_submitted_ &&
         !commands_.DisposeQueued()) {
    WaitForWake(kIdleWaitMs);
    waited = true;
  }
  // The wait may have consumed a wake for other work, which the next
  // iteration of the loop then handles without waiting.
  if (waited) Signal();
}

void MapTexture::OnEvents(void* user_data, const mln_event_batch_view* events) {
  auto* self = static_cast<MapTexture*>(user_data);
  const auto* base = reinterpret_cast<const char*>(events->events);
  for (size_t i = 0; i < events->event_count; ++i) {
    const auto* event =
        reinterpret_cast<const mln_runtime_event*>(base + i * events->event_size);
    std::string message;
    if (event->message.size > 0) {
      message.assign(static_cast<const char*>(event->message.data),
                     event->message.size);
    }
    switch (event->type) {
      case MLN_RUNTIME_EVENT_MAP_STYLE_LOADED:
        // The map thread installs the overlays in the new style (design
        // D201) before it renders.
        self->style_loads_.fetch_add(1);
        self->Signal();
        self->Emit(MAP_TEXTURE_EVENT_STYLE_LOADED);
        break;
      case MLN_RUNTIME_EVENT_MAP_LOADING_FAILED:
        self->Emit(MAP_TEXTURE_EVENT_LOADING_FAILED,
                   message.empty() ? "map loading failed" : message.c_str());
        break;
      case MLN_RUNTIME_EVENT_MAP_RENDER_ERROR:
        self->Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
                   message.empty() ? "render error" : message.c_str());
        break;
      case MLN_RUNTIME_EVENT_MAP_IDLE:
        self->Emit(MAP_TEXTURE_EVENT_IDLE);
        break;
      default:
        break;
    }
  }
}

void MapTexture::MaybeRender() {
  if (demand_outstanding_ || session_ == MLN_HANDLE_NULL) return;

  // While paused, no demand is armed and ServiceDriver() renders nothing;
  // SetPaused(false) wakes the map thread to arm one.
  if (gate_.paused()) {
    std::lock_guard lock(stats_mutex_);
    ++stats_.paused_renders;
    return;
  }

  if (auto* surface = target_->AsSurfaceTarget()) {
    RenderIntoSurface(*surface);
  } else if (target_->AsBufferTarget()->RendersIntoBuffers()) {
    RenderIntoRing(*target_->AsBufferTarget());
  } else {
    RenderIntoBuffer(*target_->AsBufferTarget());
  }
}

// Normally the next frame renders only after Dart has chosen the latest one,
// and SelectNewest() signals the wake source to retry the render. While a
// frame takes longer than a display refresh interval, waiting would cost a
// whole refresh interval per frame, so the next frame renders right away; a
// frame Dart hasn't chosen yet is then replaced.
bool MapTexture::MayRender(bool* render_ahead) {
  bool latest_chosen = buffers_.LatestReadyChosen();
  *render_ahead = !latest_chosen && RenderAhead();
  if (latest_chosen || *render_ahead) return true;
  render_waited_for_display_ = true;
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.waits_for_display;
  }
  waiting_for_buffer_.store(true);
  // SelectNewest() may have run between the check and the store, and found no
  // wait to end.
  if (buffers_.LatestReadyChosen() && waiting_for_buffer_.exchange(false)) {
    Signal();
  }
  return false;
}

// Present() and SelectNewest() free held slots and then wake the map thread.
int MapTexture::AcquireSlot() {
  int index = buffers_.AcquireFree(-1);
  if (index < 0) {
    {
      std::lock_guard lock(stats_mutex_);
      ++stats_.skipped_renders;
    }
    waiting_for_buffer_.store(true);
  }
  return index;
}

void MapTexture::RecordRenderStart(int64_t start, bool render_ahead) {
  {
    std::lock_guard lock(stats_mutex_);
    if (render_ahead) ++stats_.render_ahead_frames;
    int64_t selected = selected_at_ns_.load();
    if (render_waited_for_display_ && selected != 0 && selected <= start) {
      ++stats_.present_to_render_count;
      stats_.present_to_render_total_ns += start - selected;
    }
  }
  render_waited_for_display_ = false;
}

// The slot is taken and made the session's target when the demand is armed,
// and the frame is published when its result arrives (HandleFrameResult).
void MapTexture::RenderIntoBuffer(BufferRenderTarget& target) {
  bool render_ahead = false;
  if (!MayRender(&render_ahead)) return;
  int index = AcquireSlot();
  if (index < 0) return;

  ArmDemand(index, render_ahead);
}

// The session chooses the slot among those whose frames the map thread
// doesn't hold, so the slot is known when the frame is acquired
// (HandleFrameResult).
void MapTexture::RenderIntoRing(BufferRenderTarget& target) {
  bool render_ahead = false;
  if (!MayRender(&render_ahead)) return;
  ReleaseHeldFrames(false);
  if (!FreeSlotAvailable()) return;
  ArmDemand(-1, render_ahead);
}

bool MapTexture::FreeSlotAvailable() {
  for (int i = 0; i < target_->slot_count(); ++i) {
    if (buffers_.slot(i) == BufferState::Slot::kFree) return true;
  }
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.skipped_renders;
  }
  waiting_for_buffer_.store(true);
  // Present() or SelectNewest() may have freed a slot between the check and
  // the store, and found no wait to end.
  for (int i = 0; i < target_->slot_count(); ++i) {
    if (buffers_.slot(i) == BufferState::Slot::kFree &&
        waiting_for_buffer_.exchange(false)) {
      Signal();
      break;
    }
  }
  return false;
}

// A surface target's session queues each frame on the surface, and the frame
// is published when its image arrives. Renders are paced to one per display
// refresh interval, not by Dart's choice: on Android a frame reaches Dart only
// after its image arrives, and Dart chooses it in the next Flutter frame, so
// waiting for the choice would cost a refresh interval per frame. A ready
// frame that Dart hasn't chosen is replaced.
void MapTexture::RenderIntoSurface(SurfaceRenderTarget& target) {
  if (!target.CanPresent()) return;
  if (IntervalRemainingNs() > 0) {
    if (!interval_wait_counted_) {
      interval_wait_counted_ = true;
      std::lock_guard lock(stats_mutex_);
      ++stats_.interval_waits;
    }
    return;
  }
  interval_wait_counted_ = false;
  int index = AcquireSlot();
  if (index < 0) return;
  buffers_.Expect(index, next_frame_id_);
  ArmDemand(index, false);
}

bool MapTexture::ArmDemand(int slot, bool render_ahead) {
  mln_frame_demand demand = mln_frame_demand_default();
  // After a frame that asked for another without a map update, as during a
  // paint transition, the next frame renders unconditionally.
  demand.flags = repaint_wanted_ ? 0u
                                 : MLN_FRAME_DEMAND_IF_NEEDED |
                                       MLN_FRAME_DEMAND_WAIT_FOR_UPDATE;
  if (target_->AsSurfaceTarget() != nullptr) {
    demand.flags |= MLN_FRAME_DEMAND_PRESENT;
  }
  demand.token = ++demand_token_;
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_status status =
      mln_render_session_request_frame(session_, &demand, &diagnostic);
  if (status != MLN_STATUS_OK) {
    if (slot >= 0) buffers_.Release(slot);
    if (!RecoverLostTarget()) {
      ReportStatus("mln_render_session_request_frame", status, &diagnostic);
    }
    return false;
  }
  demand_outstanding_ = true;
  demand_slot_ = slot;
  demand_render_ahead_ = render_ahead;
  demand_stale_ = false;
  return true;
}

void MapTexture::ServiceDriver() {
  if (session_ == MLN_HANDLE_NULL) return;
  // While paused, the map thread submits no GPU work; the driver work waits
  // until rendering resumes. An armed frame demand that waits counts as a
  // render that the pause deferred.
  if (!gate_.TryBeginRender()) {
    if (demand_outstanding_) {
      std::lock_guard lock(stats_mutex_);
      ++stats_.paused_renders;
    }
    return;
  }
  RenderGateScope gate_scope(gate_);

  if (auto* surface = target_->AsSurfaceTarget()) {
    // The id goes with the next frame the session presents.
    if (demand_outstanding_ && !demand_stale_) {
      surface->WillRender(next_frame_id_);
    }
  }
  mln_diagnostic diagnostic = NewDiagnostic();
  int64_t start = NowNs();
  mln_status status =
      mln_render_session_service_driver_work(session_, &diagnostic);
  int64_t elapsed = NowNs() - start;
  if (status != MLN_STATUS_OK && status != MLN_STATUS_BUSY) {
    ReportStatus("mln_render_session_service_driver_work", status, &diagnostic);
  }
  DrainFrameResults(start, elapsed);
}

void MapTexture::DrainFrameResults(int64_t service_start, int64_t service_ns) {
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_render_frame_batch batch = MLN_HANDLE_NULL;
  mln_status status =
      mln_render_session_drain_frame_results(session_, &batch, &diagnostic);
  if (status == MLN_STATUS_NOT_READY) return;
  if (status != MLN_STATUS_OK) {
    ReportStatus("mln_render_session_drain_frame_results", status, &diagnostic);
    return;
  }
  mln_render_frame_batch_view view{};
  view.size = sizeof(view);
  if (mln_render_frame_batch_get(batch, &view, &diagnostic) == MLN_STATUS_OK) {
    const auto* base = reinterpret_cast<const char*>(view.results);
    for (size_t i = 0; i < view.result_count; ++i) {
      HandleFrameResult(*reinterpret_cast<const mln_render_frame_result*>(
                            base + i * view.result_size),
                        service_start, service_ns);
    }
  }
  mln_render_frame_batch_release(batch);
}

namespace {

// Appends `text` to `out` as a JSON string.
void AppendJsonString(std::string& out, std::string_view text) {
  out += '"';
  for (char c : text) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char escaped[7];
          std::snprintf(escaped, sizeof(escaped), "\\u%04x", c);
          out += escaped;
        } else {
          out += c;
        }
    }
  }
  out += '"';
}

// The JSON array that MAP_TEXTURE_EVENT_QUERY_RESULT carries, from the
// features of a query's completion. The FFI's feature and state are JSON
// already, so nothing is parsed.
std::string QueryResultJson(const mln_completion_result& result) {
  std::string json = "[";
  const auto* base = static_cast<const char*>(result.value);
  for (size_t i = 0; i < result.value_count; ++i) {
    const auto& feature = *reinterpret_cast<const mln_queried_feature*>(
        base + i * result.value_size);
    if (i > 0) json += ',';
    json += "{\"feature\":";
    json += ViewOf(feature.feature);
    json += ",\"source\":";
    if (feature.fields & MLN_QUERIED_FEATURE_SOURCE_ID) {
      AppendJsonString(json, ViewOf(feature.source_id));
    } else {
      json += "null";
    }
    json += ",\"sourceLayer\":";
    if (feature.fields & MLN_QUERIED_FEATURE_SOURCE_LAYER_ID) {
      AppendJsonString(json, ViewOf(feature.source_layer_id));
    } else {
      json += "null";
    }
    json += ",\"state\":";
    if (feature.fields & MLN_QUERIED_FEATURE_STATE) {
      json += ViewOf(feature.state);
    } else {
      json += "{}";
    }
    json += '}';
  }
  json += ']';
  return json;
}

// The outcome of one query of a batch, written by its completion.
struct QueryOutcome {
  std::mutex mutex;
  bool done = false;
  int32_t status = MLN_STATUS_OK;
  std::string message;

  void Set(int32_t result_status, std::string result_message) {
    std::lock_guard lock(mutex);
    status = result_status;
    message = std::move(result_message);
    done = true;
  }

  bool Done() {
    std::lock_guard lock(mutex);
    return done;
  }
};

}  // namespace

// A query reads the last frame the session rendered when its driver work runs
// in a later service call, and any service call can render the armed demand's
// frame first. Ending the demand before converting keeps the converted
// geometry and the frame the query reads the same.
void MapTexture::RunQueries() {
  std::vector<RenderedQuery> queries;
  {
    std::lock_guard lock(queries_mutex_);
    if (queries_.empty()) return;
    // While paused, queries wait like renders, because a service call may
    // render.
    if (session_ != MLN_HANDLE_NULL && gate_.paused()) return;
    // The frame that includes the feature state comes after the commands'
    // repaint. A command queued after this pass took the queue is applied in
    // a later pass.
    if (session_ != MLN_HANDLE_NULL &&
        (feature_state_applied_ < feature_state_queued_before_queries_ ||
         feature_state_completed_.load() < feature_state_submitted_ ||
         rendered_update_generation_ < feature_state_generation_.load())) {
      return;
    }
    queries.swap(queries_);
  }
  auto last_view = [this] {
    std::lock_guard lock(rendered_view_mutex_);
    return rendered_view_;
  };
  if (session_ == MLN_HANDLE_NULL || !last_view()) {
    for (const RenderedQuery& query : queries) {
      EmitQueryResult(query.request_id, MLN_STATUS_OK, "[]");
    }
    return;
  }
  if (!gate_.TryBeginRender()) {
    std::lock_guard lock(queries_mutex_);
    queries_.insert(queries_.begin(), std::make_move_iterator(queries.begin()),
                    std::make_move_iterator(queries.end()));
    return;
  }
  RenderGateScope gate_scope(gate_);

  if (demand_outstanding_) {
    uint64_t rendered = rendered_results_;
    bool repaint = repaint_wanted_;
    int64_t start = NowNs();
    EndDemands();
    DrainFrameResults(start, NowNs() - start);
    // The demand armed next renders as the ended one would have.
    if (rendered_results_ == rendered) repaint_wanted_ = repaint;
  }
  const RenderedView view = *last_view();

  std::vector<std::shared_ptr<QueryOutcome>> outcomes;
  for (const RenderedQuery& query : queries) {
    auto outcome = std::make_shared<QueryOutcome>();
    outcomes.push_back(outcome);
    if (query.layer_ids && query.layer_ids->empty()) {
      outcome->Set(MLN_STATUS_OK, "[]");
      continue;
    }
    ScreenBox box =
        ScreenBounds(view.camera, view.width, view.height, query.corners);
    mln_rendered_query_geometry geometry{};
    geometry.size = sizeof(geometry);
    geometry.type = MLN_RENDERED_QUERY_GEOMETRY_TYPE_BOX;
    geometry.data.box = {{box.min.x, box.min.y}, {box.max.x, box.max.y}};
    mln_rendered_feature_query_options options =
        mln_rendered_feature_query_options_default();
    std::vector<mln_buffer_view> layer_ids;
    if (query.layer_ids) {
      for (const std::string& id : *query.layer_ids) layer_ids.push_back(View(id));
      options.fields |= MLN_RENDERED_FEATURE_QUERY_OPTION_LAYER_IDS;
      options.layer_ids = layer_ids.data();
      options.layer_id_count = layer_ids.size();
    }
    if (query.filter) {
      options.fields |= MLN_RENDERED_FEATURE_QUERY_OPTION_FILTER;
      options.filter = View(*query.filter);
    }
    mln_completion done =
        FunctionCompletion([outcome](const mln_completion_result& result) {
          if (result.status == MLN_STATUS_OK) {
            outcome->Set(MLN_STATUS_OK, QueryResultJson(result));
          } else if (result.status == MLN_STATUS_TARGET_LOST) {
            outcome->Set(MLN_STATUS_OK, "[]");
          } else {
            outcome->Set(result.status, std::string(ViewOf(result.diagnostic)));
          }
        });
    mln_diagnostic diagnostic = NewDiagnostic();
    mln_status status = mln_render_session_query_rendered_features(
        session_, &geometry, &options, &done, &diagnostic);
    if (status != MLN_STATUS_OK) {
      DiscardFunctionCompletion(done);
      if (status == MLN_STATUS_INVALID_STATE) {
        outcome->Set(MLN_STATUS_OK, "[]");
      } else {
        outcome->Set(status, diagnostic.message);
      }
    }
  }
  ServiceUntil([&outcomes] {
    return std::all_of(outcomes.begin(), outcomes.end(),
                       [](const auto& outcome) { return outcome->Done(); });
  });
  for (size_t i = 0; i < queries.size(); ++i) {
    QueryOutcome& outcome = *outcomes[i];
    std::lock_guard lock(outcome.mutex);
    if (outcome.done) {
      EmitQueryResult(queries[i].request_id, outcome.status, outcome.message);
    } else {
      EmitQueryResult(queries[i].request_id, MLN_STATUS_NATIVE_ERROR,
                      "the query did not complete");
    }
  }
}

void MapTexture::EmitQueryResult(int64_t request_id, int32_t status,
                                 const std::string& message) {
  std::lock_guard lock(callback_mutex_);
  if (callback_ == nullptr) return;
  auto* event =
      static_cast<map_texture_event*>(std::calloc(1, sizeof(map_texture_event)));
  event->handle = handle_;
  event->type = MAP_TEXTURE_EVENT_QUERY_RESULT;
  event->request_id = request_id;
  event->status = status;
  event->message = strdup(message.c_str());
  callback_(event);
}

void MapTexture::HandleFrameResult(const mln_render_frame_result& result,
                                   int64_t service_start, int64_t service_ns) {
  if (result.disposition == MLN_RENDER_RESULT_RENDERED) {
    ++rendered_results_;
    rendered_update_generation_ = result.map_update_generation;
    const mln_map_view& view = result.view;
    std::lock_guard lock(rendered_view_mutex_);
    rendered_view_ = RenderedView{
        {view.camera.center.latitude, view.camera.center.longitude,
         view.camera.zoom, view.camera.bearing},
        static_cast<double>(view.extent.width),
        static_cast<double>(view.extent.height)};
  }
  if (!demand_outstanding_ || result.token != demand_token_) return;
  demand_outstanding_ = false;
  int index = demand_slot_;
  bool stale = demand_stale_;
  demand_slot_ = -1;
  demand_stale_ = false;

  // A demand armed before a resize may render the update of the new size
  // into a frame that isn't published. A demand that waits for an update would
  // then wait for one that doesn't come while the map is idle, so the next
  // demand renders unconditionally.
  if (stale) {
    repaint_wanted_ = true;
    if (result.disposition == MLN_RENDER_RESULT_RENDERED &&
        target_->AsBufferTarget() != nullptr && acquire_frames_) {
      AcquireAndReleaseFrame();
    }
    return;
  }
  if (result.disposition != MLN_RENDER_RESULT_RENDERED) {
    if (index >= 0) buffers_.Release(index);
    repaint_wanted_ = false;
    if (result.disposition == MLN_RENDER_RESULT_TARGET_NOT_READY) {
      RecoverLostTarget();
    }
    return;
  }
  repaint_wanted_ = result.needs_repaint;
  if (auto* buffer_target = target_->AsBufferTarget();
      buffer_target != nullptr && buffer_target->RendersIntoBuffers()) {
    index = HoldRenderedFrame(*buffer_target);
    if (index < 0) {
      // The frame isn't published, so the next demand renders again.
      repaint_wanted_ = true;
      return;
    }
  } else if (buffer_target != nullptr && acquire_frames_) {
    AcquireAndReleaseFrame();
  }

  RecordRenderStart(service_start, demand_render_ahead_);
  RecordRender(service_start, service_ns);
  FrameInfo info = RenderedFrameInfo(result);
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.rendered_frames;
    if (result.needs_repaint) ++stats_.needs_repaint_frames;
  }

  if (target_->AsSurfaceTarget() != nullptr) {
    bool published = buffers_.Queue(index, info);
    // The listener may receive the image before the service call returns.
    if (published) {
      published_at_ns_.store(NowNs());
      RecordCameraLatency(info);
      Emit(MAP_TEXTURE_EVENT_FRAME_READY, nullptr, &info, 0, index);
    }
    return;
  }

  BufferRenderTarget& target = *target_->AsBufferTarget();
  int64_t cost = service_ns;
  if (!target.RendersIntoBuffers()) {
    int64_t copy_start = NowNs();
    bool copied = target.CopyToBuffer(index);
    int64_t elapsed = NowNs() - copy_start;
    cost += elapsed;
    {
      std::lock_guard lock(stats_mutex_);
      ++stats_.copy_count;
      stats_.copy_total_ns += elapsed;
      stats_.copy_max_ns = std::max(stats_.copy_max_ns, elapsed);
    }
    if (!copied) {
      buffers_.Release(index);
      Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, "failed to copy the frame");
      return;
    }
  }
  // Smoothed over about eight frames, so that one slow or fast frame doesn't
  // switch between pacing and rendering ahead.
  frame_cost_avg_ns_ = frame_cost_avg_ns_ == 0
                           ? cost
                           : frame_cost_avg_ns_ + (cost - frame_cost_avg_ns_) / 8;
  buffers_.Publish(index, info);
  published_at_ns_.store(NowNs());
  // Dart marks the slot's texture available when it chooses the frame.
  RecordCameraLatency(info);
  Emit(MAP_TEXTURE_EVENT_FRAME_READY, nullptr, &info, 0, index);
}

namespace {

// Flutter reads a buffer target's textures without a fence that a release can
// wait on, so a frame is released without consumer synchronization.
void ReleaseFrame(mln_acquired_frame frame) {
  mln_diagnostic diagnostic = NewDiagnostic();
  mln_gpu_sync sync = mln_gpu_sync_default();
  mln_status status = mln_acquired_frame_release(frame, &sync, &diagnostic);
  if (status != MLN_STATUS_OK) {
    std::fprintf(stderr, "flutter_mapigrade: mln_acquired_frame_release: %d\n",
                 status);
  }
}

}  // namespace

void MapTexture::AcquireAndReleaseFrame() {
  while (true) {
    mln_acquired_frame frame = MLN_HANDLE_NULL;
    mln_diagnostic diagnostic = NewDiagnostic();
    mln_status status =
        mln_render_session_acquire_frame(session_, &frame, &diagnostic);
    if (status == MLN_STATUS_UNSUPPORTED) {
      acquire_frames_ = false;
      return;
    }
    if (status == MLN_STATUS_NOT_READY) return;
    if (status != MLN_STATUS_OK) {
      ReportStatus("mln_render_session_acquire_frame", status, &diagnostic);
      return;
    }
    // Flutter reads the texture after a copy, or a stale frame isn't
    // published at all.
    ReleaseFrame(frame);
  }
}

int MapTexture::HoldRenderedFrame(BufferRenderTarget& target) {
  // The session acquires the oldest rendered frame first, so the last one is
  // the frame of this result; any older one wasn't published.
  mln_acquired_frame newest = MLN_HANDLE_NULL;
  while (true) {
    mln_acquired_frame frame = MLN_HANDLE_NULL;
    mln_diagnostic diagnostic = NewDiagnostic();
    mln_status status =
        mln_render_session_acquire_frame(session_, &frame, &diagnostic);
    if (status == MLN_STATUS_NOT_READY) break;
    if (status != MLN_STATUS_OK) {
      ReportStatus("mln_render_session_acquire_frame", status, &diagnostic);
      break;
    }
    if (newest != MLN_HANDLE_NULL) ReleaseFrame(newest);
    newest = frame;
  }
  if (newest == MLN_HANDLE_NULL) return -1;
  bool current = false;
  int slot = target.FrameSlot(newest, &current);
  // The session renders only into a slot whose frame the map thread doesn't
  // hold, and the map thread holds the frame of every slot that isn't free,
  // so the slot is free. Only the map thread takes a free slot.
  if (slot < 0 || !current || held_frames_[slot] != MLN_HANDLE_NULL ||
      buffers_.slot(slot) != BufferState::Slot::kFree ||
      buffers_.AcquireFree(slot) != slot) {
    ReleaseFrame(newest);
    Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
         "the session rendered into a slot that isn't free");
    return -1;
  }
  held_frames_[slot] = newest;
  return slot;
}

void MapTexture::ReleaseHeldFrames(bool all) {
  for (int i = 0; i < kMaxBufferCount; ++i) {
    if (held_frames_[i] == MLN_HANDLE_NULL) continue;
    if (!all && buffers_.slot(i) != BufferState::Slot::kFree) continue;
    ReleaseFrame(held_frames_[i]);
    held_frames_[i] = MLN_HANDLE_NULL;
  }
}

int64_t MapTexture::IntervalRemainingNs() {
  if (last_render_start_ns_ == 0) return 0;
  int64_t interval = display_interval_ns_.load();
  if (interval <= 0) interval = kDefaultIntervalNs;
  int64_t remaining = last_render_start_ns_ + interval - NowNs();
  return std::max<int64_t>(remaining, 0);
}

void MapTexture::RecordRender(int64_t start, int64_t elapsed) {
  std::lock_guard lock(stats_mutex_);
  if (last_render_start_ns_ != 0 &&
      start - last_render_start_ns_ < 100'000'000) {
    ++stats_.frame_cycle_count;
    stats_.frame_cycle_total_ns += start - last_render_start_ns_;
  }
  last_render_start_ns_ = start;
  // render_update_count counts the service calls that rendered a frame.
  ++stats_.render_update_count;
  stats_.render_update_total_ns += elapsed;
  stats_.render_update_max_ns = std::max(stats_.render_update_max_ns, elapsed);
}

FrameInfo MapTexture::RenderedFrameInfo(const mln_render_frame_result& result) {
  FrameInfo info;
  info.frame_id = next_frame_id_++;
  info.physical_width = size_.physical_width;
  info.physical_height = size_.physical_height;
  info.scale_factor = size_.extent.scale_factor;
  // The view that the frame drew. Its center longitude is unwrapped.
  const mln_camera_options& camera = result.view.camera;
  info.camera = {camera.center.latitude, camera.center.longitude, camera.zoom,
                 camera.bearing};
  {
    // The newest camera command whose generation the frame's update includes.
    // Older entries are no longer needed.
    std::lock_guard lock(camera_generations_mutex_);
    size_t newest = camera_generations_.size();
    for (size_t i = 0; i < camera_generations_.size(); ++i) {
      if (camera_generations_[i].generation <= result.map_update_generation) {
        newest = i;
      }
    }
    if (newest < camera_generations_.size()) {
      applied_seq_ = camera_generations_[newest].seq;
      applied_set_at_ns_ = camera_generations_[newest].set_at_ns;
      camera_generations_.erase(camera_generations_.begin(),
                                camera_generations_.begin() + newest);
    }
  }
  info.seq = applied_seq_;
  info.camera_set_at_ns = applied_set_at_ns_;
  return info;
}

bool MapTexture::RenderAhead() {
  switch (render_ahead_mode.load()) {
    case RenderAheadMode::kNever:
      return false;
    case RenderAheadMode::kAlways:
      return true;
    case RenderAheadMode::kAuto:
      break;
  }
  // Hysteresis: start rendering ahead when a frame costs more than a refresh
  // interval, and go back to pacing only when it costs less than 3/4 of one,
  // so that a frame cost close to the interval doesn't switch on every frame.
  int64_t interval = display_interval_ns_.load();
  if (interval <= 0) {
    rendering_ahead_ = false;
  } else if (frame_cost_avg_ns_ > interval) {
    rendering_ahead_ = true;
  } else if (frame_cost_avg_ns_ < interval * 3 / 4) {
    rendering_ahead_ = false;
  }
  return rendering_ahead_;
}

void MapTexture::Emit(int32_t type, const char* message,
                      const FrameInfo* frame, int64_t display_time_us,
                      int slot) {
  std::lock_guard lock(callback_mutex_);
  if (callback_ == nullptr) return;
  auto* event =
      static_cast<map_texture_event*>(std::calloc(1, sizeof(map_texture_event)));
  event->handle = handle_;
  event->type = type;
  if (frame != nullptr) {
    event->frame_id = static_cast<int64_t>(frame->frame_id);
    event->latitude = frame->camera.latitude;
    event->longitude = frame->camera.longitude;
    event->zoom = frame->camera.zoom;
    event->bearing = frame->camera.bearing;
    event->physical_width = static_cast<int32_t>(frame->physical_width);
    event->physical_height = static_cast<int32_t>(frame->physical_height);
    event->scale_factor = frame->scale_factor;
    event->display_time_us = display_time_us;
    event->slot = slot;
    event->seq = frame->seq;
  }
  if (message != nullptr) event->message = strdup(message);
  callback_(event);
}

// MapLibre may hold its logging lock here, so this only queues an event for
// Dart and calls no FFI function. Returning 0 lets MapLibre's platform logger
// write the record as well.
uint32_t MapTexture::OnLogRecord(void*, uint32_t severity, uint32_t event,
                                 int64_t, const char* message) {
  MapTexture* map = map_thread_owner;
  if (map == nullptr || message == nullptr ||
      severity != MLN_LOG_SEVERITY_ERROR || event != MLN_LOG_EVENT_STYLE ||
      !std::string_view(message).starts_with(kGlyphFailurePrefix)) {
    return 0;
  }
  map->Emit(MAP_TEXTURE_EVENT_LOADING_FAILED, message);
  return 0;
}

void MapTexture::ReportStatus(const char* what, mln_status status,
                              const mln_diagnostic* diagnostic) {
  Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
       StatusMessage(what, status,
                     diagnostic != nullptr ? diagnostic->message : nullptr)
           .c_str());
}

void MapTexture::ReportInitStatus(const char* what, mln_status status,
                                  const mln_diagnostic* diagnostic) {
  init_error_ = StatusMessage(
      what, status, diagnostic != nullptr ? diagnostic->message : nullptr);
  Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, init_error_.c_str());
}

mln_completion MapTexture::ReportingCompletion(
    const char* what,
    std::function<void(const mln_completion_result&)> on_success,
    std::function<void()> on_done) {
  return FunctionCompletion(
      [this, what, on_success = std::move(on_success),
       on_done = std::move(on_done)](const mln_completion_result& result) {
        if (result.status == MLN_STATUS_OK) {
          if (on_success) on_success(result);
          if (on_done) on_done();
          return;
        }
        std::string detail;
        if (result.diagnostic.size > 0) {
          detail.assign(static_cast<const char*>(result.diagnostic.data),
                        result.diagnostic.size);
        }
        Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
             StatusMessage(what, static_cast<mln_status>(result.status),
                           detail.c_str())
                 .c_str());
        if (on_done) on_done();
      });
}

}  // namespace map_texture
