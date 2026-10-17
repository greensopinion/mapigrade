// State of the display slots, one buffer each (designs D3, D4 and D124).
//
// Each slot is in one of these states:
// - free: the map thread may render into it
// - rendering: the map thread renders into it
// - ready: it holds a finished frame that Dart hasn't chosen
// - held: Dart has chosen its frame, and a Flutter frame may display it
//
// A held slot becomes free when Flutter's raster thread presents a slot that
// Dart chose later. The slot presented last stays held until another slot is
// presented. A ready slot becomes free when a newer frame is published.
//
// The map thread calls AcquireFree(), Release() and Publish(). Dart calls
// Select() on the platform thread. Flutter's raster thread calls Present().
// One mutex guards the state, and the callers run their buffer lookups under
// it (see WithLock), so a buffer set replaced during a resize is never read
// half-replaced.
#pragma once

#include <array>
#include <cstdint>
#include <mutex>

#include <time.h>

#include "command_queue.h"

namespace map_texture {

inline constexpr int kBufferCount = 4;
inline constexpr int kMaxBufferCount = 4;

// The clock of Flutter's FrameTiming on macOS and iOS, in microseconds: the
// engine reads Dart_TimelineGetTicks, which is CLOCK_MONOTONIC_RAW (design
// D24). std::chrono::steady_clock is CLOCK_UPTIME_RAW on Apple platforms and
// differs from it by the time the device has slept. Android uses no buffer
// state with display times, so there it is CLOCK_MONOTONIC.
inline int64_t DisplayClockUs() {
#if defined(__APPLE__)
  return static_cast<int64_t>(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) /
                              1000);
#else
  timespec now{};
  clock_gettime(CLOCK_MONOTONIC, &now);
  return static_cast<int64_t>(now.tv_sec) * 1'000'000 + now.tv_nsec / 1000;
#endif
}

// What a buffer holds: the frame id and the camera and size it was rendered
// with, and the sequence number of the camera update it was rendered with
// (design D125).
struct FrameInfo {
  uint64_t frame_id = 0;
  Camera camera;
  int64_t seq = 0;
  uint32_t physical_width = 0;
  uint32_t physical_height = 0;
  double scale_factor = 1;
};

class BufferState {
 public:
  enum class Slot { kFree, kRendering, kReady, kHeld };

  // `count` is the number of slots, at most kMaxBufferCount. With four slots a
  // free one exists while Dart chooses each ready frame and Flutter presents
  // one frame behind: one slot presented, one chosen, one ready and one
  // rendering. Tests use fewer to reach the "no free slot" case.
  explicit BufferState(int count = kBufferCount) : count_(count) {}

  // Returns the index of a free slot and marks it rendering, preferring
  // `current` (the slot the session renders into now) so that the target
  // doesn't change needlessly. Returns -1 if no slot is free.
  int AcquireFree(int current) {
    std::lock_guard lock(mutex_);
    int index = -1;
    if (current >= 0 && current < count_ && slots_[current] == Slot::kFree) {
      index = current;
    } else {
      for (int i = 0; i < count_; ++i) {
        if (slots_[i] == Slot::kFree) {
          index = i;
          break;
        }
      }
    }
    if (index >= 0) SetLocked(index, Slot::kRendering);
    return index;
  }

  // Marks a slot from AcquireFree() free again, after a render that published
  // no frame.
  void Release(int index) {
    std::lock_guard lock(mutex_);
    if (slots_[index] == Slot::kRendering) SetLocked(index, Slot::kFree);
  }

  // True if Dart has chosen the latest finished frame, or none is ready. The
  // map thread renders the next frame only then, so it renders at most one
  // frame ahead of Dart's choice.
  bool LatestReadyChosen() {
    std::lock_guard lock(mutex_);
    for (int i = 0; i < count_; ++i) {
      if (slots_[i] == Slot::kReady) return false;
    }
    return true;
  }

  // Marks `index` as holding a finished frame. A frame that is ready and not
  // chosen is replaced: its slot becomes free.
  void Publish(int index, const FrameInfo& info) {
    std::lock_guard lock(mutex_);
    for (int i = 0; i < count_; ++i) {
      if (i != index && slots_[i] == Slot::kReady) SetLocked(i, Slot::kFree);
    }
    info_[index] = info;
    presented_once_[index] = false;
    SetLocked(index, Slot::kReady);
  }

  // Records that Dart chose the frame `frame_id` in slot `index`, and returns
  // true. Returns false and changes nothing if the slot doesn't hold that
  // frame, for example after a resize replaced the set. Choosing the slot
  // chosen last again counts once. `on_selected` runs under the state lock
  // when the choice is recorded.
  template <typename F>
  bool Select(int index, uint64_t frame_id, F&& on_selected) {
    std::lock_guard lock(mutex_);
    if (index < 0 || index >= count_ || info_[index].frame_id != frame_id ||
        (slots_[index] != Slot::kReady && slots_[index] != Slot::kHeld)) {
      return false;
    }
    if (index != last_selected_ || slots_[index] != Slot::kHeld) {
      selection_[index] = ++selections_;
      last_selected_ = index;
      SetLocked(index, Slot::kHeld);
    }
    on_selected();
    return true;
  }

  bool Select(int index, uint64_t frame_id) {
    return Select(index, frame_id, [] {});
  }

  struct Presented {
    // The slot to display, or -1 if the slot holds no frame that Dart chose
    // since the last Reset().
    int index = -1;
    FrameInfo info;
    // True if this present returns a frame that wasn't returned before.
    bool is_new = false;
    // Set when is_new: the time at which Flutter took the frame, from
    // DisplayClockUs().
    int64_t display_time_us = 0;
  };

  // Flutter's raster thread presents slot `index`. If Dart chose it, frees the
  // slots chosen before it and returns it. `use` runs under the state lock
  // with the result, so the caller can read the buffer before the map thread
  // can replace the set.
  template <typename F>
  Presented Present(int index, F&& use) {
    std::lock_guard lock(mutex_);
    Presented result;
    if (index >= 0 && index < count_ && slots_[index] == Slot::kHeld) {
      result.index = index;
      result.info = info_[index];
      result.is_new = !presented_once_[index];
      if (result.is_new) result.display_time_us = DisplayClockUs();
      presented_once_[index] = true;
      for (int i = 0; i < count_; ++i) {
        if (i != index && slots_[i] == Slot::kHeld &&
            selection_[i] < selection_[index]) {
          SetLocked(i, Slot::kFree);
        }
      }
    }
    use(result);
    return result;
  }

  // Runs `f` under the state lock. The map thread uses it to replace the
  // buffer set together with ResetLocked(), and gets the slot Dart chose last
  // (or -1) first.
  template <typename F>
  void WithLock(F&& f) {
    std::lock_guard lock(mutex_);
    f(last_selected_ >= 0 && slots_[last_selected_] == Slot::kHeld
          ? last_selected_
          : -1);
  }

  // Marks all slots free. Call under WithLock when the buffer set is
  // replaced.
  void ResetLocked() {
    for (int i = 0; i < count_; ++i) {
      slots_[i] = Slot::kFree;
      info_[i] = FrameInfo{};
      selection_[i] = 0;
      presented_once_[i] = false;
    }
    last_selected_ = -1;
  }

  Slot slot(int index) {
    std::lock_guard lock(mutex_);
    return slots_[index];
  }

  // The most slots in use (rendering, ready or held) at once.
  int max_in_use() {
    std::lock_guard lock(mutex_);
    return max_in_use_;
  }

 private:
  void SetLocked(int index, Slot state) {
    slots_[index] = state;
    int in_use = 0;
    for (int i = 0; i < count_; ++i) {
      if (slots_[i] != Slot::kFree) ++in_use;
    }
    if (in_use > max_in_use_) max_in_use_ = in_use;
  }

  std::mutex mutex_;
  const int count_;
  std::array<Slot, kMaxBufferCount> slots_{};
  std::array<FrameInfo, kMaxBufferCount> info_{};
  // The order in which Dart chose each held slot; larger is later.
  std::array<uint64_t, kMaxBufferCount> selection_{};
  std::array<bool, kMaxBufferCount> presented_once_{};
  uint64_t selections_ = 0;
  int last_selected_ = -1;
  int max_in_use_ = 0;
};

}  // namespace map_texture
