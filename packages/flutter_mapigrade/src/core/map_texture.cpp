#include "map_texture.h"

#include <algorithm>
#include <chrono>
#include <cmath>
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

constexpr uint64_t kMapEventMask =
    MLN_RUNTIME_EVENT_MASK_MAP_STYLE_LOADED |
    MLN_RUNTIME_EVENT_MASK_MAP_LOADING_FAILED |
    MLN_RUNTIME_EVENT_MASK_MAP_RENDER_UPDATE_AVAILABLE |
    MLN_RUNTIME_EVENT_MASK_MAP_RENDER_ERROR | MLN_RUNTIME_EVENT_MASK_MAP_IDLE;

// Park bound of a pump with nothing to render. Wakes come from the runtime and
// from commands, so this only bounds a missed wake.
constexpr int64_t kIdlePumpTimeoutMs = 250;
// Drain budget per pump, so that style parsing and tile work don't hold up a
// pending frame for long.
constexpr int64_t kPumpBudgetMs = 8;
// Delay after the last resize before Flutter is told once more that a frame
// is available. Longer than the default maximum texture age (1 s) of a
// CVMetalTextureCache; see MaybeNotifyAfterResize().
constexpr int64_t kResizeSettledNs = 1'100'000'000;
// The refresh interval a surface target paces by until the display's refresh
// rate is set (design D53): 60 Hz.
constexpr int64_t kDefaultIntervalNs = 1'000'000'000 / 60;

// The map whose map thread this is; null on other threads. MapLibre logs
// error records synchronously, on the thread that runs the failed work, and
// each map's resource responses run on its own map thread, in
// mln_runtime_pump().
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
  size->extent.size = sizeof(mln_render_target_extent);
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

}  // namespace

std::shared_ptr<MapTexture> MapTexture::Create(
    int64_t handle, double pixel_ratio, bool copy_free,
    std::optional<uint64_t> maximum_cache_size,
    std::vector<HttpHeaderRule> header_rules,
    map_texture_event_callback callback, std::string* out_error) {
  if (!(pixel_ratio > 0) || !std::isfinite(pixel_ratio)) {
    *out_error = "invalid pixel ratio";
    return nullptr;
  }
  std::shared_ptr<MapTexture> texture(
      new MapTexture(handle, pixel_ratio, maximum_cache_size,
                     std::move(header_rules), callback));
  if (!texture->Start(copy_free, out_error)) return nullptr;
  return texture;
}

MapTexture::MapTexture(int64_t handle, double pixel_ratio,
                       std::optional<uint64_t> maximum_cache_size,
                       std::vector<HttpHeaderRule> header_rules,
                       map_texture_event_callback callback)
    : handle_(handle),
      initial_pixel_ratio_(pixel_ratio),
      maximum_cache_size_(maximum_cache_size),
      header_rules_(std::move(header_rules)),
      callback_(callback) {
  // Filled before any rule points into it.
  for (const auto& rule : header_rules_) {
    for (const auto& [name, value] : rule.headers) {
      transform_headers_.push_back({name.c_str(), value.c_str()});
    }
  }
  size_t first_header = 0;
  for (const auto& rule : header_rules_) {
    mln_adapter_http_header_transform_rule transform_rule{};
    transform_rule.kind = MLN_ADAPTER_RESOURCE_KIND_ANY;
    transform_rule.flags = MLN_ADAPTER_URL_MATCH_GLOB;
    transform_rule.url = rule.url.c_str();
    transform_rule.headers = rule.headers.empty()
                                 ? nullptr
                                 : transform_headers_.data() + first_header;
    transform_rule.header_count = rule.headers.size();
    transform_rules_.push_back(transform_rule);
    first_header += rule.headers.size();
  }
  transform_table_.rules = transform_rules_.data();
  transform_table_.count = transform_rules_.size();
}

MapTexture::~MapTexture() {
  // Dispose() joins the thread; this only covers a failed Start().
  if (thread_.joinable()) {
    commands_.Push(Command::Dispose());
    Signal();
    thread_.join();
  }
}

bool MapTexture::Start(bool copy_free, std::string* out_error) {
  target_ = CreatePlatformRenderTarget(weak_from_this(), copy_free);
  if (!target_) {
    *out_error = "failed to create the render target";
    return false;
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

int64_t MapTexture::texture_id() const { return target_->texture_id(); }

void MapTexture::LoadStyleUrl(std::string url) {
  commands_.Push(Command::StyleUrl(std::move(url)));
  Signal();
}

void MapTexture::LoadStyleJson(std::string json) {
  commands_.Push(Command::StyleJson(std::move(json)));
  Signal();
}

void MapTexture::SetCamera(const Camera& camera) {
  commands_.SetCamera(camera);
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
          if (session_ != MLN_HANDLE_NULL) render_pending_ = true;
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
  std::lock_guard lock(wake_mutex_);
  if (wake_ != MLN_HANDLE_NULL) mln_wake_source_signal(wake_);
}

void* MapTexture::Present() {
  auto* target = target_->AsBufferTarget();
  if (target == nullptr) return nullptr;
  void* buffer = nullptr;
  auto presented = buffers_.Present([&](const BufferState::Presented& p) {
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
         presented.display_time_us);
  }
  if (waiting_for_buffer_.exchange(false)) Signal();
  return buffer;
}

map_texture_stats MapTexture::stats() {
  std::lock_guard lock(stats_mutex_);
  return stats_;
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

bool MapTexture::RenderWanted() {
  if (!render_pending_ || session_ == MLN_HANDLE_NULL || gate_.paused()) {
    return false;
  }
  if (auto* surface = target_->AsSurfaceTarget()) {
    return surface->CanPresent();
  }
  return !waiting_for_buffer_.load();
}

bool MapTexture::RunOnce() {
  bool render_now = RenderWanted();
  int64_t timeout_ms = render_now ? 0 : kIdlePumpTimeoutMs;
  if (render_now && target_->AsSurfaceTarget() != nullptr) {
    // A surface target's render waits for the end of the refresh interval
    // (design D53). The pump parks in whole milliseconds, so the part of the
    // wait below one millisecond is slept here.
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
  mln_status status = mln_runtime_pump(runtime_, timeout_ms, kPumpBudgetMs);
  if (status != MLN_STATUS_OK) ReportStatus("mln_runtime_pump", status);
  bool stop = false;
  ApplyCommands(&stop);
  if (stop) return true;
  ApplyCamera();
  DrainEvents();
  MaybeRender();
  MaybeNotifyAfterResize();
  return false;
}

// Workaround for Flutter's Darwin embedders (see
// docs/flutter-texture-cache-followup.md): Flutter wraps each pixel buffer it
// displays through its own CVMetalTextureCache and never flushes it per frame.
// The cache frees an entry only when it creates another texture after the
// entry's maximum age has passed, so after a series of resizes it keeps the
// replaced buffers alive until the next new frame, which on an idle map can be
// much later. Telling Flutter once more that a frame is available, after the
// maximum age, makes it create a texture and free them.
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
  runtime_options.cache_path = cache_path.empty() ? nullptr : cache_path.c_str();
  runtime_options.asset_path = asset_path.empty() ? nullptr : asset_path.c_str();
  runtime_options.event_mask = MLN_RUNTIME_EVENT_MASK_NONE;

  // Installed once for the process, before the first map loads a style. The
  // callback is process-global, so it replaces any other that the app set
  // through the FFI. If the call fails, the map renders without reporting
  // glyph failures.
  std::call_once(log_callback_once, [this] {
    mln_status log_status =
        mln_log_set_callback(&MapTexture::OnLogRecord, nullptr);
    if (log_status != MLN_STATUS_OK) {
      ReportStatus("mln_log_set_callback", log_status);
    }
  });

  mln_status status = mln_runtime_create(&runtime_options, &runtime_);
  if (status != MLN_STATUS_OK) {
    ReportInitStatus("mln_runtime_create", status);
    return false;
  }

  // The database thread runs its messages in order, so the maximum size is in
  // effect before the first resource request or write of the style load
  // (design D62). If the call fails, the map uses MapLibre's default and
  // continues to render (D63).
  if (maximum_cache_size_) {
    mln_offline_operation_id operation = 0;
    status = mln_runtime_set_maximum_ambient_cache_size_start(
        runtime_, *maximum_cache_size_, &operation);
    if (status == MLN_STATUS_OK) {
      mln_runtime_offline_operation_discard(runtime_, operation);
    } else {
      ReportStatus("mln_runtime_set_maximum_ambient_cache_size_start", status);
    }
  }

  // Before the map, so that style requests carry the headers.
  if (!header_rules_.empty()) {
    mln_http_header_transform transform{};
    transform.size = sizeof(transform);
    transform.callback = mln_adapter_http_header_transform_callback;
    transform.user_data = &transform_table_;
    status = mln_runtime_set_http_header_transform(runtime_, &transform);
    if (status != MLN_STATUS_OK) {
      ReportInitStatus("mln_runtime_set_http_header_transform", status);
      return false;
    }
  }

  mln_wake_source wake = MLN_HANDLE_NULL;
  status = mln_runtime_wake_source_acquire(runtime_, &wake);
  if (status != MLN_STATUS_OK) {
    ReportInitStatus("mln_runtime_wake_source_acquire", status);
    return false;
  }
  {
    std::lock_guard lock(wake_mutex_);
    wake_ = wake;
  }

  mln_map_options map_options = mln_map_options_default();
  map_options.width = 256;
  map_options.height = 256;
  map_options.scale_factor = initial_pixel_ratio_;
  map_options.event_mask = kMapEventMask;
  status = mln_map_create(runtime_, &map_options, &map_);
  if (status != MLN_STATUS_OK) {
    ReportInitStatus("mln_map_create", status);
    return false;
  }
  return true;
}

void MapTexture::DestroySession() {
  if (session_ != MLN_HANDLE_NULL) {
    mln_render_session_destroy(session_);
    session_ = MLN_HANDLE_NULL;
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
  if (map_ != MLN_HANDLE_NULL) {
    mln_map_destroy(map_);
    map_ = MLN_HANDLE_NULL;
  }
  if (runtime_ != MLN_HANDLE_NULL) {
    mln_runtime_destroy(runtime_);
    runtime_ = MLN_HANDLE_NULL;
  }
  std::lock_guard lock(wake_mutex_);
  mln_wake_source_destroy(wake_);
  wake_ = MLN_HANDLE_NULL;
}

void MapTexture::ApplyCommands(bool* stop) {
  for (auto& command : commands_.TakeAll()) {
    switch (command.kind) {
      case Command::Kind::kStyleUrl: {
        mln_status status = mln_map_set_style_url(map_, command.text.c_str());
        if (status != MLN_STATUS_OK) {
          ReportStatus("mln_map_set_style_url", status);
        }
        break;
      }
      case Command::Kind::kStyleJson: {
        mln_buffer_view json{command.text.data(), command.text.size()};
        mln_status status = mln_map_set_style_json(map_, json);
        // A malformed document also queues a loading-failed event, which
        // carries the message.
        if (status != MLN_STATUS_OK && status != MLN_STATUS_NATIVE_ERROR) {
          ReportStatus("mln_map_set_style_json", status);
        }
        break;
      }
      case Command::Kind::kResize:
        ApplyResize(command.viewport);
        break;
      case Command::Kind::kReduceMemoryUse:
        ApplyReduceMemoryUse();
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

void MapTexture::ApplyReduceMemoryUse() {
  if (session_ == MLN_HANDLE_NULL) return;
  // This releases cached tiles and images and submits no GPU work, so it also
  // runs while rendering is paused.
  mln_status status = mln_render_session_reduce_memory_use(session_);
  if (status == MLN_STATUS_OK) {
    std::lock_guard lock(stats_mutex_);
    ++stats_.memory_reductions;
  } else if (status != MLN_STATUS_INVALID_STATE) {
    // MLN_STATUS_INVALID_STATE: no renderer exists yet, so there is nothing
    // to release.
    ReportStatus("mln_render_session_reduce_memory_use", status);
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
    buffers_.WithLock([buffer_target, this](int latest) {
      buffer_target->SwapBuffersLocked(latest);
      buffers_.ResetLocked();
    });
    notify_after_resize_at_ns_ = NowNs() + kResizeSettledNs;
  }
  size_ = size;

  mln_status status;
  if (session_ == MLN_HANDLE_NULL) {
    status = target_->Attach(map_, size_, &session_);
    if (status != MLN_STATUS_OK) ReportStatus("attach", status);
  } else {
    status = target_->SetTarget(session_, size_);
    if (status != MLN_STATUS_OK) ReportStatus("set_target", status);
  }
  render_pending_ = true;
}

void MapTexture::ApplyCamera() {
  auto camera = commands_.TakeCamera();
  if (!camera) return;
  mln_camera_options options = mln_camera_options_default();
  options.fields =
      MLN_CAMERA_OPTION_CENTER | MLN_CAMERA_OPTION_ZOOM | MLN_CAMERA_OPTION_BEARING;
  options.latitude = camera->latitude;
  options.longitude = camera->longitude;
  options.zoom = camera->zoom;
  options.bearing = camera->bearing;
  mln_status status = mln_map_jump_to(map_, &options);
  if (status != MLN_STATUS_OK) ReportStatus("mln_map_jump_to", status);
}

void MapTexture::DrainEvents() {
  mln_runtime_event_batch batch = mln_runtime_event_batch_default();
  do {
    mln_status status = mln_runtime_drain_events(runtime_, 0, &batch);
    if (status != MLN_STATUS_OK) {
      ReportStatus("mln_runtime_drain_events", status);
      return;
    }
    const char* base = reinterpret_cast<const char*>(batch.events);
    for (size_t i = 0; i < batch.event_count; ++i) {
      const auto* event =
          reinterpret_cast<const mln_runtime_event*>(base + i * batch.event_size);
      std::string message;
      if (event->message_size > 0) {
        message.assign(batch.messages + event->message_offset,
                       event->message_size);
      }
      switch (event->type) {
        case MLN_RUNTIME_EVENT_MAP_STYLE_LOADED:
          Emit(MAP_TEXTURE_EVENT_STYLE_LOADED);
          break;
        case MLN_RUNTIME_EVENT_MAP_LOADING_FAILED:
          Emit(MAP_TEXTURE_EVENT_LOADING_FAILED,
               message.empty() ? "map loading failed" : message.c_str());
          break;
        case MLN_RUNTIME_EVENT_MAP_RENDER_ERROR:
          Emit(MAP_TEXTURE_EVENT_RENDER_ERROR,
               message.empty() ? "render error" : message.c_str());
          break;
        case MLN_RUNTIME_EVENT_MAP_IDLE:
          Emit(MAP_TEXTURE_EVENT_IDLE);
          break;
        case MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE: {
          {
            std::lock_guard lock(stats_mutex_);
            ++stats_.render_update_available_events;
          }
          render_pending_ = true;
          break;
        }
        default:
          break;
      }
    }
  } while (batch.remaining_count > 0);
}

void MapTexture::MaybeRender() {
  if (!render_pending_ || session_ == MLN_HANDLE_NULL) return;

  // While paused, the render stays pending; SetPaused(false) wakes the map
  // thread to render it (design D13).
  if (!gate_.TryBeginRender()) {
    std::lock_guard lock(stats_mutex_);
    ++stats_.paused_renders;
    return;
  }
  RenderGateScope gate_scope(gate_);

  if (auto* surface = target_->AsSurfaceTarget()) {
    RenderIntoSurface(*surface);
  } else {
    RenderIntoBuffer(*target_->AsBufferTarget());
  }
}

void MapTexture::RenderIntoBuffer(BufferRenderTarget& target) {
  // Normally the next frame renders only after Flutter has taken the latest
  // one, and Present() signals the wake source to retry this render. While a
  // frame takes longer than a display refresh interval, waiting would cost a
  // whole refresh interval per frame, so the next frame renders right away;
  // a frame Flutter hasn't taken yet is then replaced (design D19).
  bool latest_presented = buffers_.LatestPresented();
  bool render_ahead = !latest_presented && RenderAhead();
  if (!latest_presented && !render_ahead) {
    render_waited_for_display_ = true;
    {
      std::lock_guard lock(stats_mutex_);
      ++stats_.waits_for_display;
    }
    waiting_for_buffer_.store(true);
    return;
  }
  int index = buffers_.AcquireFree(-1);
  if (index < 0) {
    {
      std::lock_guard lock(stats_mutex_);
      ++stats_.skipped_renders;
    }
    waiting_for_buffer_.store(true);
    return;
  }

  if (target.RendersIntoBuffers()) {
    mln_status select_status = target.SelectBuffer(session_, index);
    if (select_status != MLN_STATUS_OK) {
      ReportStatus("select buffer", select_status);
      return;
    }
  }

  int64_t start = NowNs();
  {
    std::lock_guard lock(stats_mutex_);
    if (render_ahead) ++stats_.render_ahead_frames;
    int64_t presented = presented_at_ns_.load();
    if (render_waited_for_display_ && presented != 0 && presented <= start) {
      ++stats_.present_to_render_count;
      stats_.present_to_render_total_ns += start - presented;
    }
  }
  render_waited_for_display_ = false;
  bool needs_repaint = false;
  if (!RenderUpdate(start, &needs_repaint)) return;

  int64_t cost = NowNs() - start;
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
      Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, "failed to copy the frame");
      return;
    }
  }
  // Smoothed over about eight frames, so that one slow or fast frame doesn't
  // switch between pacing and rendering ahead.
  frame_cost_avg_ns_ = frame_cost_avg_ns_ == 0
                           ? cost
                           : frame_cost_avg_ns_ + (cost - frame_cost_avg_ns_) / 8;

  FrameInfo info = RenderedFrameInfo();
  buffers_.Publish(index, info);
  published_at_ns_.store(NowNs());
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.rendered_frames;
    if (needs_repaint) ++stats_.needs_repaint_frames;
  }
  // The map publishes another render update by itself while a transition
  // runs, so needs_repaint needs no action here (see
  // mln_render_session_render_update in render_session.h).
  target.FrameAvailable();
}

// Queueing a frame on the surface never blocks, so renders are paced to one
// per display refresh interval (design D53). The frame-displayed event is sent
// when render_update has queued the frame, and has no display time.
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

  bool needs_repaint = false;
  if (!RenderUpdate(NowNs(), &needs_repaint)) return;

  FrameInfo info = RenderedFrameInfo();
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.rendered_frames;
    // RenderUpdate has queued the frame on the surface (design D112).
    ++stats_.presented_frames;
    if (needs_repaint) ++stats_.needs_repaint_frames;
  }
  Emit(MAP_TEXTURE_EVENT_FRAME_DISPLAYED, nullptr, &info, -1);
}

int64_t MapTexture::IntervalRemainingNs() {
  if (last_render_start_ns_ == 0) return 0;
  int64_t interval = display_interval_ns_.load();
  if (interval <= 0) interval = kDefaultIntervalNs;
  int64_t remaining = last_render_start_ns_ + interval - NowNs();
  return std::max<int64_t>(remaining, 0);
}

bool MapTexture::RenderUpdate(int64_t start, bool* needs_repaint) {
  {
    std::lock_guard lock(stats_mutex_);
    if (last_render_start_ns_ != 0 &&
        start - last_render_start_ns_ < 100'000'000) {
      ++stats_.frame_cycle_count;
      stats_.frame_cycle_total_ns += start - last_render_start_ns_;
    }
  }
  last_render_start_ns_ = start;
  render_pending_ = false;
  mln_render_result result = MLN_RENDER_RESULT_NO_UPDATE;
  mln_status status =
      mln_render_session_render_update(session_, &result, needs_repaint);
  int64_t elapsed = NowNs() - start;
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.render_update_count;
    stats_.render_update_total_ns += elapsed;
    stats_.render_update_max_ns = std::max(stats_.render_update_max_ns, elapsed);
  }
  if (status != MLN_STATUS_OK) {
    ReportStatus("mln_render_session_render_update", status);
    return false;
  }
  return result == MLN_RENDER_RESULT_RENDERED;
}

FrameInfo MapTexture::RenderedFrameInfo() {
  FrameInfo info;
  info.frame_id = next_frame_id_++;
  info.physical_width = size_.physical_width;
  info.physical_height = size_.physical_height;
  info.scale_factor = size_.extent.scale_factor;
  mln_map_projection projection = MLN_HANDLE_NULL;
  mln_status status = mln_render_session_projection_create(session_, &projection);
  if (status == MLN_STATUS_OK) {
    mln_camera_options camera = mln_camera_options_default();
    if (mln_map_projection_get_camera(projection, &camera) == MLN_STATUS_OK) {
      info.camera = {camera.latitude, camera.longitude, camera.zoom,
                     camera.bearing};
    }
    mln_map_projection_destroy(projection);
  } else {
    ReportStatus("mln_render_session_projection_create", status);
  }
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
                      const FrameInfo* frame, int64_t display_time_us) {
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
  }
  if (message != nullptr) event->message = strdup(message);
  callback_(event);
}

namespace {

std::string StatusMessage(const char* what, mln_status status) {
  const char* detail = mln_thread_last_error_message();
  std::string message = std::string(what) + " failed with status " +
                        std::to_string(static_cast<int>(status));
  if (detail != nullptr && detail[0] != '\0') {
    message += ": ";
    message += detail;
  }
  return message;
}

}  // namespace

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

void MapTexture::ReportStatus(const char* what, mln_status status) {
  Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, StatusMessage(what, status).c_str());
}

void MapTexture::ReportInitStatus(const char* what, mln_status status) {
  init_error_ = StatusMessage(what, status);
  Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, init_error_.c_str());
}

}  // namespace map_texture
