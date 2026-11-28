// Stops the map thread from submitting GPU work while the application can't
// use the GPU, for example while an iOS app is in the background.
//
// The map thread brackets each render (render_update plus the copy into a
// buffer) with TryBeginRender() and EndRender(). SetPaused(true) returns only
// when no render is in progress, so that after it returns no GPU work is
// submitted until SetPaused(false).
#pragma once

#include <condition_variable>
#include <mutex>

namespace map_texture {

class RenderGate {
 public:
  // Map thread. Returns false while paused. Otherwise marks a render as in
  // progress until EndRender() and returns true.
  bool TryBeginRender() {
    std::lock_guard lock(mutex_);
    if (paused_) return false;
    rendering_ = true;
    return true;
  }

  // Map thread. Ends the render that TryBeginRender() began.
  void EndRender() {
    {
      std::lock_guard lock(mutex_);
      rendering_ = false;
    }
    cv_.notify_all();
  }

  // Any thread except the map thread. Pausing waits until a render in
  // progress has ended.
  void SetPaused(bool paused) {
    std::unique_lock lock(mutex_);
    paused_ = paused;
    if (paused) cv_.wait(lock, [this] { return !rendering_; });
  }

  bool paused() {
    std::lock_guard lock(mutex_);
    return paused_;
  }

 private:
  std::mutex mutex_;
  std::condition_variable cv_;
  bool paused_ = false;
  bool rendering_ = false;
};

// Ends a render begun with RenderGate::TryBeginRender() when it goes out of
// scope.
class RenderGateScope {
 public:
  explicit RenderGateScope(RenderGate& gate) : gate_(gate) {}
  ~RenderGateScope() { gate_.EndRender(); }
  RenderGateScope(const RenderGateScope&) = delete;
  RenderGateScope& operator=(const RenderGateScope&) = delete;

 private:
  RenderGate& gate_;
};

}  // namespace map_texture
