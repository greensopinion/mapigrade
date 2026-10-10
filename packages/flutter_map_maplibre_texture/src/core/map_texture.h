// One map rendered into a Flutter texture: the map thread that owns the
// MapLibre runtime, map and render session (designs D1 and D2), the command
// queue from Dart, and the buffer state shared with Flutter's raster thread.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "buffer_state.h"
#include "command_queue.h"
#include "map_texture_api.h"
#include "mln.h"
#include "render_target.h"

namespace map_texture {

class MapTexture : public std::enable_shared_from_this<MapTexture> {
 public:
  // Creates the platform render target, starts the map thread, and waits
  // until the thread has created the runtime and map. Returns null on failure.
  static std::shared_ptr<MapTexture> Create(
      int64_t handle, double pixel_ratio, map_texture_event_callback callback);

  ~MapTexture();

  int64_t texture_id() const;

  // Commands. Any thread; they queue work and wake the map thread.
  void LoadStyleUrl(std::string url);
  void LoadStyleJson(std::string json);
  void SetCamera(const Camera& camera);
  void Resize(const Viewport& viewport);

  // Stops the map thread after it has destroyed the session, map and
  // runtime, then unregisters the texture. After this returns no events are
  // delivered.
  void Dispose();

  // Flutter's raster thread. Marks the latest frame as presented and returns
  // its buffer, retained, through RenderTarget::CopyBufferLocked. Reports a
  // frame-displayed event when the frame is new.
  void* Present();

  map_texture_stats stats();

 private:
  MapTexture(int64_t handle, double pixel_ratio,
             map_texture_event_callback callback);

  bool Start();
  void Run();
  bool Init();
  void Teardown();
  void Signal();

  void ApplyCommands(bool* stop);
  void ApplyResize(const Viewport& viewport);
  void ApplyCamera();
  void DrainEvents();
  void MaybeRender();

  void Emit(int32_t type, const char* message = nullptr,
            const FrameInfo* frame = nullptr);
  void ReportStatus(const char* what, mln_status status);

  const int64_t handle_;
  const double initial_pixel_ratio_;

  std::unique_ptr<RenderTarget> target_;
  CommandQueue commands_;
  BufferState buffers_;

  std::thread thread_;
  std::mutex init_mutex_;
  std::condition_variable init_cv_;
  bool init_done_ = false;
  bool init_ok_ = false;

  // Guards wake_ against destruction while another thread signals it.
  std::mutex wake_mutex_;
  mln_wake_source wake_ = MLN_HANDLE_NULL;

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
  // Set when a render was deferred because Flutter hadn't taken the latest
  // frame or no buffer was free; Present() wakes the map thread.
  std::atomic<bool> waiting_for_buffer_{false};

  std::mutex stats_mutex_;
  map_texture_stats stats_{};
};

}  // namespace map_texture
