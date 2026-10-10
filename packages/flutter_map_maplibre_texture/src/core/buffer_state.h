// State of the set of render target buffers (designs D3 and D4).
//
// Each buffer is in one of these roles:
// - latest: the last completed frame, which the next present returns
// - presented: the buffer the last present returned to Flutter
// - free: neither of the above; the map thread may render into it
//
// The map thread calls AcquireFree() and Publish(). Flutter's raster thread
// calls Present(). One mutex guards the state, and the callers run their
// buffer lookups under it (see WithLock), so a buffer set replaced during a
// resize is never read half-replaced.
#pragma once

#include <array>
#include <cstdint>
#include <mutex>

#include "command_queue.h"

namespace map_texture {

inline constexpr int kBufferCount = 3;
inline constexpr int kMaxBufferCount = 4;

// What a buffer holds: the frame id and the camera and size it was rendered
// with.
struct FrameInfo {
  uint64_t frame_id = 0;
  Camera camera;
  uint32_t physical_width = 0;
  uint32_t physical_height = 0;
  double scale_factor = 1;
};

class BufferState {
 public:
  // `count` is the number of buffers in the set, at most kMaxBufferCount.
  // With three buffers a free one always exists, because only one buffer can
  // be latest and one presented. Tests use two to reach the "no free buffer"
  // case.
  explicit BufferState(int count = kBufferCount) : count_(count) {}

  // Returns the index of a free buffer, preferring `current` (the buffer the
  // session renders into now) so that the target doesn't change needlessly.
  // Returns -1 if no buffer is free.
  int AcquireFree(int current) {
    std::lock_guard lock(mutex_);
    if (current >= 0 && IsFree(current)) return current;
    for (int i = 0; i < count_; ++i) {
      if (IsFree(i)) return i;
    }
    return -1;
  }

  // True if Flutter has taken the latest frame, or there is none. The map
  // thread renders the next frame only then, so it renders at most one frame
  // ahead of the display.
  bool LatestPresented() {
    std::lock_guard lock(mutex_);
    return latest_ < 0 || latest_ == presented_;
  }

  // Marks `index` as holding a completed frame.
  void Publish(int index, const FrameInfo& info) {
    std::lock_guard lock(mutex_);
    info_[index] = info;
    latest_ = index;
  }

  struct Presented {
    // The buffer to display, or -1 if no frame was published since the last
    // Reset().
    int index = -1;
    FrameInfo info;
    // True if this present returns a frame that wasn't returned before.
    bool is_new = false;
  };

  // Marks the latest buffer as presented and returns it. `use` runs under the
  // state lock with the result, so the caller can read the buffer before the
  // map thread can replace the set.
  template <typename F>
  Presented Present(F&& use) {
    std::lock_guard lock(mutex_);
    Presented result;
    if (latest_ >= 0) {
      result.index = latest_;
      result.info = info_[latest_];
      result.is_new = info_[latest_].frame_id != last_presented_frame_id_;
      presented_ = latest_;
      last_presented_frame_id_ = info_[latest_].frame_id;
    }
    use(result);
    return result;
  }

  // Runs `f` under the state lock. The map thread uses it to replace the
  // buffer set together with Reset(), and gets the latest index first.
  template <typename F>
  void WithLock(F&& f) {
    std::lock_guard lock(mutex_);
    f(latest_);
  }

  // Marks all buffers free. Call under WithLock when the buffer set is
  // replaced.
  void ResetLocked() {
    latest_ = -1;
    presented_ = -1;
  }

  int latest() {
    std::lock_guard lock(mutex_);
    return latest_;
  }

 private:
  bool IsFree(int i) const { return i != latest_ && i != presented_; }

  std::mutex mutex_;
  const int count_;
  std::array<FrameInfo, kMaxBufferCount> info_{};
  int latest_ = -1;
  int presented_ = -1;
  uint64_t last_presented_frame_id_ = 0;
};

}  // namespace map_texture
