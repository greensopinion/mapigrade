#include "map_texture.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>

namespace map_texture {

namespace {
std::atomic<RenderAheadMode> render_ahead_mode{RenderAheadMode::kAuto};
}  // namespace

void SetRenderAheadModeForTesting(RenderAheadMode mode) {
  render_ahead_mode.store(mode);
}

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

int64_t NowNs() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

uint32_t RoundToPixels(double value) {
  return static_cast<uint32_t>(std::max(1.0, std::round(value)));
}

}  // namespace

std::shared_ptr<MapTexture> MapTexture::Create(
    int64_t handle, double pixel_ratio, map_texture_event_callback callback) {
  if (!(pixel_ratio > 0) || !std::isfinite(pixel_ratio)) return nullptr;
  std::shared_ptr<MapTexture> texture(
      new MapTexture(handle, pixel_ratio, callback));
  if (!texture->Start()) return nullptr;
  return texture;
}

MapTexture::MapTexture(int64_t handle, double pixel_ratio,
                       map_texture_event_callback callback)
    : handle_(handle),
      initial_pixel_ratio_(pixel_ratio),
      callback_(callback) {}

MapTexture::~MapTexture() {
  // Dispose() joins the thread; this only covers a failed Start().
  if (thread_.joinable()) {
    commands_.Push(Command::Dispose());
    Signal();
    thread_.join();
  }
}

bool MapTexture::Start() {
  target_ = CreatePlatformRenderTarget(weak_from_this());
  if (!target_) return false;
  thread_ = std::thread([this] { Run(); });
  std::unique_lock lock(init_mutex_);
  init_cv_.wait(lock, [this] { return init_done_; });
  if (!init_ok_) {
    thread_.join();
    target_->Unregister();
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
  void* buffer = nullptr;
  auto presented = buffers_.Present([&](const BufferState::Presented& p) {
    buffer = target_->CopyBufferLocked(p.index);
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
    Emit(MAP_TEXTURE_EVENT_FRAME_DISPLAYED, nullptr, &presented.info);
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
  return render_pending_ && session_ != MLN_HANDLE_NULL &&
         !waiting_for_buffer_.load() && !gate_.paused();
}

bool MapTexture::RunOnce() {
  bool render_now = RenderWanted();
  int64_t timeout_ms = render_now ? 0 : kIdlePumpTimeoutMs;
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
  target_->FrameAvailable();
}

bool MapTexture::Init() {
  std::string cache_path = PlatformCachePath();
  mln_runtime_options runtime_options = mln_runtime_options_default();
  runtime_options.cache_path = cache_path.empty() ? nullptr : cache_path.c_str();
  runtime_options.event_mask = MLN_RUNTIME_EVENT_MASK_NONE;
  mln_status status = mln_runtime_create(&runtime_options, &runtime_);
  if (status != MLN_STATUS_OK) {
    ReportStatus("mln_runtime_create", status);
    return false;
  }

  mln_wake_source wake = MLN_HANDLE_NULL;
  status = mln_runtime_wake_source_acquire(runtime_, &wake);
  if (status != MLN_STATUS_OK) {
    ReportStatus("mln_runtime_wake_source_acquire", status);
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
    ReportStatus("mln_map_create", status);
    return false;
  }
  return true;
}

void MapTexture::DestroySession() {
  if (session_ != MLN_HANDLE_NULL) {
    mln_render_session_destroy(session_);
    session_ = MLN_HANDLE_NULL;
  }
  buffers_.WithLock([this](int) {
    target_->ReleaseBuffersLocked();
    buffers_.ResetLocked();
  });
}

void MapTexture::Teardown() {
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
  if (!(viewport.logical_width > 0) || !(viewport.logical_height > 0) ||
      !(viewport.pixel_ratio > 0)) {
    return;
  }
  TargetSize size;
  size.physical_width =
      RoundToPixels(viewport.logical_width * viewport.pixel_ratio);
  size.physical_height =
      RoundToPixels(viewport.logical_height * viewport.pixel_ratio);
  size.extent.size = sizeof(mln_render_target_extent);
  size.extent.width = RoundToPixels(viewport.logical_width);
  size.extent.height = RoundToPixels(viewport.logical_height);
  size.extent.scale_factor = viewport.pixel_ratio;
  viewport_ = viewport;
  if (session_ != MLN_HANDLE_NULL &&
      size.physical_width == size_.physical_width &&
      size.physical_height == size_.physical_height &&
      size.extent.scale_factor == size_.extent.scale_factor) {
    return;
  }

  if (!target_->PrepareBuffers(size)) {
    Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, "failed to allocate texture buffers");
    return;
  }
  buffers_.WithLock([this](int latest) {
    target_->SwapBuffersLocked(latest);
    buffers_.ResetLocked();
  });
  size_ = size;
  notify_after_resize_at_ns_ = NowNs() + kResizeSettledNs;

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

  mln_render_result result = MLN_RENDER_RESULT_NO_UPDATE;
  bool needs_repaint = false;
  if (target_->RendersIntoBuffers()) {
    mln_status select_status = target_->SelectBuffer(session_, index);
    if (select_status != MLN_STATUS_OK) {
      ReportStatus("select buffer", select_status);
      return;
    }
  }

  int64_t start = NowNs();
  {
    std::lock_guard lock(stats_mutex_);
    if (render_ahead) ++stats_.render_ahead_frames;
    if (last_render_start_ns_ != 0 &&
        start - last_render_start_ns_ < 100'000'000) {
      ++stats_.frame_cycle_count;
      stats_.frame_cycle_total_ns += start - last_render_start_ns_;
    }
    int64_t presented = presented_at_ns_.load();
    if (render_waited_for_display_ && presented != 0 && presented <= start) {
      ++stats_.present_to_render_count;
      stats_.present_to_render_total_ns += start - presented;
    }
  }
  last_render_start_ns_ = start;
  render_waited_for_display_ = false;
  render_pending_ = false;
  mln_status status =
      mln_render_session_render_update(session_, &result, &needs_repaint);
  int64_t elapsed = NowNs() - start;
  {
    std::lock_guard lock(stats_mutex_);
    ++stats_.render_update_count;
    stats_.render_update_total_ns += elapsed;
    stats_.render_update_max_ns = std::max(stats_.render_update_max_ns, elapsed);
  }
  if (status != MLN_STATUS_OK) {
    ReportStatus("mln_render_session_render_update", status);
    return;
  }
  if (result != MLN_RENDER_RESULT_RENDERED) return;

  int64_t render_elapsed = elapsed;
  start = NowNs();
  bool copied = target_->RendersIntoBuffers() || target_->CopyToBuffer(index);
  elapsed = NowNs() - start;
  // Smoothed over about eight frames, so that one slow or fast frame doesn't
  // switch between pacing and rendering ahead.
  int64_t cost = render_elapsed + elapsed;
  frame_cost_avg_ns_ = frame_cost_avg_ns_ == 0
                           ? cost
                           : frame_cost_avg_ns_ + (cost - frame_cost_avg_ns_) / 8;
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

  FrameInfo info;
  info.frame_id = next_frame_id_++;
  info.physical_width = size_.physical_width;
  info.physical_height = size_.physical_height;
  info.scale_factor = size_.extent.scale_factor;
  mln_map_projection projection = MLN_HANDLE_NULL;
  status = mln_render_session_projection_create(session_, &projection);
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
  target_->FrameAvailable();
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
                      const FrameInfo* frame) {
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
  }
  if (message != nullptr) event->message = strdup(message);
  callback_(event);
}

void MapTexture::ReportStatus(const char* what, mln_status status) {
  const char* detail = mln_thread_last_error_message();
  std::string message = std::string(what) + " failed with status " +
                        std::to_string(static_cast<int>(status));
  if (detail != nullptr && detail[0] != '\0') {
    message += ": ";
    message += detail;
  }
  Emit(MAP_TEXTURE_EVENT_RENDER_ERROR, message.c_str());
}

}  // namespace map_texture
