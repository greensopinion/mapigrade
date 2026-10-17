// State of the display slots, one buffer each (designs D3, D4, D124 and
// D133).
//
// Each slot is in one of these states:
// - free: the map thread may render into it
// - rendering: the map thread renders into it
// - queued: on Android, its frame is rendered and queued on the surface, and
//   its image hasn't arrived yet (design D131)
// - ready: it holds a finished frame that Dart hasn't chosen
// - held: Dart has chosen its frame, and a Flutter frame may display it
//
// When a held slot becomes free depends on the release rule. With kPresent
// (macOS and iOS), a held slot becomes free when Flutter's raster thread
// presents a slot that Dart chose later, and the slot presented last stays
// held until another slot is presented. With kLaterChoices (Android, where
// Flutter doesn't report when it has finished with a frame), a held slot
// becomes free when Dart has chosen kLaterChoices later frames. A ready slot
// becomes free when a newer frame is published.
//
// The map thread calls AcquireFree(), Release(), Publish() and Queue(). On
// Android the thread that receives a frame's image calls PublishQueued(). Dart calls Select()
// on the platform thread. Flutter's raster thread calls Present().
// One mutex guards the state, and the callers run their buffer lookups under
// it (see WithLock), so a buffer set replaced during a resize is never read
// half-replaced.
#pragma once

#include <array>
#include <cstdint>
#include <functional>
#include <mutex>

#include <time.h>

#include "command_queue.h"

namespace map_texture {

inline constexpr int kBufferCount = 4;
// The slots of an Android map (design D133).
inline constexpr int kChoiceReleasedBufferCount = 6;
inline constexpr int kMaxBufferCount = 6;
// With ReleaseRule::kLaterChoices, the number of later choices after which a
// held slot becomes free (design D133).
inline constexpr int kLaterChoices = 3;

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
  enum class Slot { kFree, kRendering, kQueued, kReady, kHeld };
  enum class ReleaseRule { kPresent, kLaterChoices };

  // `count` is the number of slots, at most kMaxBufferCount. With four slots
  // and kPresent a free one exists while Dart chooses each ready frame and
  // Flutter presents one frame behind: one slot presented, one chosen, one
  // ready and one rendering. With six slots and kLaterChoices: three held,
  // one ready, one queued and one rendering (design D133). Tests use fewer to reach the "no free slot"
  // case.
  explicit BufferState(int count = kBufferCount,
                       ReleaseRule rule = ReleaseRule::kPresent)
      : count_(count), rule_(rule) {}

  // Sets the number of slots and the release rule, before any other call.
  void Configure(int count, ReleaseRule rule) {
    std::lock_guard lock(mutex_);
    count_ = count;
    rule_ = rule;
  }

  // Sets a function that is called with the index of each slot that becomes
  // free, under the state lock, before any other call. The Android target
  // closes the slot's image in it.
  void set_on_freed(std::function<void(int)> on_freed) {
    std::lock_guard lock(mutex_);
    on_freed_ = std::move(on_freed);
  }

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

  // True if Dart has chosen the latest finished frame, or none is ready or
  // queued. The map thread renders the next frame only then, so it renders at
  // most one frame ahead of Dart's choice.
  bool LatestReadyChosen() {
    std::lock_guard lock(mutex_);
    for (int i = 0; i < count_; ++i) {
      if (slots_[i] == Slot::kReady || slots_[i] == Slot::kQueued) {
        return false;
      }
    }
    return true;
  }

  // Records that the rendering slot `index` renders the frame `frame_id`,
  // before the render, so that an image that arrives before Queue() finds the
  // slot (design D131).
  void Expect(int index, uint64_t frame_id) {
    std::lock_guard lock(mutex_);
    if (slots_[index] != Slot::kRendering) return;
    info_[index] = FrameInfo{};
    info_[index].frame_id = frame_id;
    if (frame_id > max_expected_frame_id_) max_expected_frame_id_ = frame_id;
  }

  // The render into slot `index` has queued its frame on the surface. If the
  // frame's image arrived already, publishes the frame and returns true;
  // otherwise marks the slot as waiting for the image and returns false
  // (design D131).
  bool Queue(int index, const FrameInfo& info) {
    std::lock_guard lock(mutex_);
    if (slots_[index] != Slot::kRendering) return false;
    info_[index] = info;
    if (!image_arrived_[index]) {
      SetLocked(index, Slot::kQueued);
      return false;
    }
    PublishLocked(index);
    return true;
  }

  // Frees the slots of queued frames, whose images may not arrive.
  void ReleaseQueued() {
    std::lock_guard lock(mutex_);
    for (int i = 0; i < count_; ++i) {
      if (slots_[i] == Slot::kQueued) SetLocked(i, Slot::kFree);
    }
  }

  enum class ImageResult { kPublished, kEarly, kUnknown };

  // The image of the frame `frame_id` arrived. Runs `on_published(index)`
  // under the state lock when a slot takes the image. If the slot's frame is
  // queued, publishes it as Publish() does, also freeing the slots of older
  // queued frames, whose images won't arrive, sets `out_index` and
  // `out_info`, and returns kPublished. If the slot still renders the frame,
  // the image arrived before Queue(), which then publishes it: returns
  // kEarly. Returns kUnknown if no slot expects the frame; then `out_known`
  // tells whether a slot expected it before, for example before a Reset.
  template <typename F>
  ImageResult OnImage(uint64_t frame_id, int* out_index, FrameInfo* out_info,
                      bool* out_known, F&& on_published) {
    std::lock_guard lock(mutex_);
    int index = -1;
    for (int i = 0; i < count_; ++i) {
      if ((slots_[i] == Slot::kQueued || slots_[i] == Slot::kRendering) &&
          info_[i].frame_id == frame_id && !image_arrived_[i]) {
        index = i;
      }
    }
    *out_known = frame_id <= max_expected_frame_id_;
    if (index < 0) return ImageResult::kUnknown;
    image_arrived_[index] = true;
    on_published(index);
    if (slots_[index] == Slot::kRendering) return ImageResult::kEarly;
    PublishLocked(index);
    *out_index = index;
    *out_info = info_[index];
    return ImageResult::kPublished;
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
  // chosen last again counts once. `on_selected(new_choice, info)` runs under
  // the state lock when the choice is recorded; `new_choice` is false when
  // Dart chose the slot chosen last again.
  template <typename F>
  bool Select(int index, uint64_t frame_id, F&& on_selected) {
    std::lock_guard lock(mutex_);
    if (index < 0 || index >= count_ || info_[index].frame_id != frame_id ||
        (slots_[index] != Slot::kReady && slots_[index] != Slot::kHeld)) {
      return false;
    }
    bool new_choice = index != last_selected_ || slots_[index] != Slot::kHeld;
    if (new_choice) {
      selection_[index] = ++selections_;
      last_selected_ = index;
      SetLocked(index, Slot::kHeld);
      if (rule_ == ReleaseRule::kLaterChoices) {
        for (int i = 0; i < count_; ++i) {
          if (slots_[i] == Slot::kHeld &&
              selection_[i] + kLaterChoices <= selections_) {
            SetLocked(i, Slot::kFree);
          }
        }
      }
    }
    on_selected(new_choice, info_[index]);
    return true;
  }

  bool Select(int index, uint64_t frame_id) {
    return Select(index, frame_id, [](bool, const FrameInfo&) {});
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

  // Flutter's raster thread presents slot `index`. If Dart chose it, returns
  // it, and with kPresent frees the slots chosen before it. `use` runs under the state lock
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
      for (int i = 0; i < count_ && rule_ == ReleaseRule::kPresent; ++i) {
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
      SetLocked(i, Slot::kFree);
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

  // The most slots in use (rendering, queued, ready or held) at once.
  int max_in_use() {
    std::lock_guard lock(mutex_);
    return max_in_use_;
  }

 private:
  // Publishes the queued or rendering frame in `index`, whose image arrived:
  // frees the slots of older queued frames and the ready slot.
  void PublishLocked(int index) {
    for (int i = 0; i < count_; ++i) {
      if (i == index) continue;
      if ((slots_[i] == Slot::kQueued &&
           info_[i].frame_id < info_[index].frame_id) ||
          slots_[i] == Slot::kReady) {
        SetLocked(i, Slot::kFree);
      }
    }
    presented_once_[index] = false;
    SetLocked(index, Slot::kReady);
  }

  void SetLocked(int index, Slot state) {
    bool freed = state == Slot::kFree && slots_[index] != Slot::kFree;
    if (state == Slot::kFree) image_arrived_[index] = false;
    slots_[index] = state;
    if (freed && on_freed_) on_freed_(index);
    int in_use = 0;
    for (int i = 0; i < count_; ++i) {
      if (slots_[i] != Slot::kFree) ++in_use;
    }
    if (in_use > max_in_use_) max_in_use_ = in_use;
  }

  std::mutex mutex_;
  int count_;
  ReleaseRule rule_;
  std::function<void(int)> on_freed_;
  std::array<Slot, kMaxBufferCount> slots_{};
  std::array<FrameInfo, kMaxBufferCount> info_{};
  // The order in which Dart chose each held slot; larger is later.
  std::array<uint64_t, kMaxBufferCount> selection_{};
  std::array<bool, kMaxBufferCount> presented_once_{};
  uint64_t selections_ = 0;
  // The newest frame id passed to Expect().
  uint64_t max_expected_frame_id_ = 0;
  // Whether the image of the slot's frame arrived (design D131).
  std::array<bool, kMaxBufferCount> image_arrived_{};
  int last_selected_ = -1;
  int max_in_use_ = 0;
};

}  // namespace map_texture
