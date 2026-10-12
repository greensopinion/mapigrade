// One map rendered into a Flutter texture: the map thread that owns the
// MapLibre runtime, map and render session (designs D1 and D2), the command
// queue from Dart, and for a buffer target, the buffer state shared with
// Flutter's raster thread.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "buffer_state.h"
#include "command_queue.h"
#include "map_texture_api.h"
#include "mln.h"
#include "render_gate.h"
#include "render_target.h"

namespace map_texture {

class MapTexture : public std::enable_shared_from_this<MapTexture> {
 public:
  // Creates the platform render target, starts the map thread, and waits
  // until the thread has created the runtime and map. With `copy_free`, the
  // session renders directly into the display buffers (design D20). With
  // `maximum_cache_size`, the maximum size in bytes of the runtime's tile
  // cache is that value; otherwise it is MapLibre's default (design D61).
  // Returns null on failure.
  static std::shared_ptr<MapTexture> Create(
      int64_t handle, double pixel_ratio, bool copy_free,
      std::optional<uint64_t> maximum_cache_size,
      map_texture_event_callback callback);

  ~MapTexture();

  int64_t texture_id() const;

  // Commands. Any thread; they queue work and wake the map thread.
  void LoadStyleUrl(std::string url);
  void LoadStyleJson(std::string json);
  void SetCamera(const Camera& camera);
  void Resize(const Viewport& viewport);
  // The display's refresh rate in Hz, or 0 if unknown (design D19).
  void SetDisplayRefreshRate(double hz);
  // Asks the renderer to release cached resources it can rebuild (design
  // D14).
  void ReduceMemoryUse();

  // Any thread except the map thread. While paused, the map thread submits no
  // GPU work; pausing returns after a render in progress has ended (design
  // D13). Resuming renders a pending frame with the latest camera.
  void SetPaused(bool paused);

  // Work of a surface target on the map thread: `session` is the render
  // session (MLN_HANDLE_NULL before the first resize) and `size` the size the
  // map renders at.
  using TargetTask =
      std::function<void(mln_render_session session, const TargetSize& size)>;

  // Any thread except the map thread. Runs `task` on the map thread, ordered
  // with the other commands, and then renders the pending frame with the
  // latest camera once the target can present (design D54). With `wait`,
  // returns after the task has run, or after the map thread has stopped if it
  // stops first.
  void RunTargetTask(TargetTask task, bool wait);

  // Any thread. Reports a render error to Dart, for errors of the platform
  // render target.
  void ReportRenderError(const std::string& message);

  // Stops the map thread after it has destroyed the session, map and
  // runtime, then unregisters the texture. After this returns no events are
  // delivered.
  void Dispose();

  // Flutter's raster thread, for a buffer target. Marks the latest frame as
  // presented and returns its buffer, retained, through
  // BufferRenderTarget::CopyBufferLocked. Reports a frame-displayed event with
  // the display time when the frame is new.
  void* Present();

  map_texture_stats stats();

 private:
  MapTexture(int64_t handle, double pixel_ratio,
             std::optional<uint64_t> maximum_cache_size,
             map_texture_event_callback callback);

  bool Start(bool copy_free);
  void Run();
  // One iteration of the map thread's loop; returns true to stop.
  bool RunOnce();
  // Whether the map thread should render now rather than park.
  bool RenderWanted();
  void ApplyReduceMemoryUse();
  void DestroySession();
  bool Init();
  void Teardown();
  void Signal();

  void ApplyCommands(bool* stop);
  void ApplyResize(const Viewport& viewport);
  void ApplyCamera();
  void DrainEvents();
  void MaybeRender();
  void RenderIntoBuffer(BufferRenderTarget& target);
  void RenderIntoSurface(SurfaceRenderTarget& target);
  // Map thread, for a surface target: the time until the next render may
  // start, or 0 if it may start now (design D53).
  int64_t IntervalRemainingNs();
  // Map thread: runs render_update and records its stats. Returns whether it
  // rendered a frame.
  bool RenderUpdate(int64_t start, bool* needs_repaint);
  // Map thread: the frame just rendered, with the camera it was rendered with.
  FrameInfo RenderedFrameInfo();
  // Map thread: whether to render without waiting until Flutter has taken the
  // latest frame (design D19).
  bool RenderAhead();
  void MaybeNotifyAfterResize();

  void Emit(int32_t type, const char* message = nullptr,
            const FrameInfo* frame = nullptr, int64_t display_time_us = 0);
  void ReportStatus(const char* what, mln_status status);

  const int64_t handle_;
  const double initial_pixel_ratio_;
  const std::optional<uint64_t> maximum_cache_size_;

  std::unique_ptr<RenderTarget> target_;
  CommandQueue commands_;
  BufferState buffers_;
  RenderGate gate_;

  std::thread thread_;
  std::mutex init_mutex_;
  std::condition_variable init_cv_;
  bool init_done_ = false;
  bool init_ok_ = false;

  // Guards wake_ against destruction while another thread signals it.
  std::mutex wake_mutex_;
  mln_wake_source wake_ = MLN_HANDLE_NULL;

  // Guards target_tasks_stopped_, which the map thread sets when it stops, so
  // that no target task is queued after that.
  std::mutex target_tasks_mutex_;
  bool target_tasks_stopped_ = false;

  // Guards callback_; cleared at dispose so that no event follows it.
  std::mutex callback_mutex_;
  map_texture_event_callback callback_;

  // Map thread state.
  mln_runtime runtime_ = MLN_HANDLE_NULL;
  mln_map map_ = MLN_HANDLE_NULL;
  mln_render_session session_ = MLN_HANDLE_NULL;
  TargetSize size_{};
  Viewport viewport_{};
  bool render_pending_ = false;
  uint64_t next_frame_id_ = 1;
  // When to tell Flutter once more that a frame is available after the last
  // resize (steady clock, ns), or 0 for not pending.
  int64_t notify_after_resize_at_ns_ = 0;
  // Set when a render was deferred because Flutter hadn't taken the latest
  // frame or no buffer was free; Present() wakes the map thread.
  std::atomic<bool> waiting_for_buffer_{false};
  // Timing stats (steady clock, ns): when the last frame was published and
  // when Flutter last took a frame, written by different threads.
  std::atomic<int64_t> published_at_ns_{0};
  std::atomic<int64_t> presented_at_ns_{0};
  // Map thread: when the last render_update started, and whether the next
  // render waited for Flutter to take the latest frame.
  int64_t last_render_start_ns_ = 0;
  // Map thread: the smoothed time of render_update plus the copy, and whether
  // the map currently renders ahead (design D19).
  int64_t frame_cost_avg_ns_ = 0;
  bool rendering_ahead_ = false;
  // The display's refresh interval, or 0 if unknown.
  std::atomic<int64_t> display_interval_ns_{0};
  bool render_waited_for_display_ = false;
  // Map thread, for a surface target: whether the pending render has been
  // counted in interval_waits.
  bool interval_wait_counted_ = false;

  std::mutex stats_mutex_;
  map_texture_stats stats_{};
};

// Pauses or resumes every live map, and maps created while paused start
// paused. The platform calls this when the application can't use the GPU, for
// example while an iOS app is in the background. Defined in
// map_texture_api.cpp.
void SetAllPaused(bool paused);

// Queues ReduceMemoryUse() for every live map, for example after an iOS
// memory warning. Defined in map_texture_api.cpp.
void ReduceAllMemoryUse();

// The sum of rendered frames over every live map, for logging. Defined in
// map_texture_api.cpp.
int64_t TotalRenderedFrames();

// For tests and measurements: when maps render without waiting until Flutter
// has taken the latest frame. kAuto (the default) renders ahead while a frame
// takes longer than a display refresh interval (design D19).
enum class RenderAheadMode { kAuto, kNever, kAlways };
void SetRenderAheadModeForTesting(RenderAheadMode mode);

// For tests: the clock the map thread paces renders by and records render
// starts with, in nanoseconds, or null for the steady clock.
void SetClockForTesting(int64_t (*now_ns)());

}  // namespace map_texture
