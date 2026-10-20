// Tests of MapTexture with a surface render target (design D52) and its
// display slots (D130-D135), the display slots of a buffer target
// (D122-D126), camera sequence numbers (D125), the maximum size of the tile
// cache (D61-D63), and the HTTP header rules (D81, D82), on the fake FFI in
// fake_mln.cpp, and the engine token of each map (D156 and D157 of the
// multiple-flutter-engines change).
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "fake_mln.h"
#include "map_texture.h"
#include "map_texture_api.h"
#include "render_target.h"

using map_texture::BufferRenderTarget;
using map_texture::MapTexture;
using map_texture::SurfaceRenderTarget;
using map_texture::TargetSize;

namespace {

int failures = 0;

#define CHECK(condition)                                                 \
  do {                                                                   \
    if (!(condition)) {                                                  \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__,        \
                   __LINE__, #condition);                                \
      ++failures;                                                        \
    }                                                                    \
  } while (false)

constexpr int64_t kSessionHandle = 1'000'000;

// A surface target with six slots that share one texture. The test plays
// the image listener: it passes the frame ids that WillRender recorded to
// MapTexture::OnFrameImage, and the target keeps the frame id as the slot's
// image.
class FakeSurfaceTarget : public SurfaceRenderTarget {
 public:
  int slot_count() const override {
    return map_texture::kChoiceReleasedBufferCount;
  }
  int64_t texture_id(int) const override { return 42; }

  void WillRender(uint64_t frame_id) override {
    {
      std::lock_guard lock(mutex);
      will_render.push_back(frame_id);
    }
    if (deliver_early) DeliverEarly(frame_id);
  }

  // Delivers the image of `frame_id` before render_update returns, as the
  // listener can on a device. Defined after last_owner.
  void DeliverEarly(uint64_t frame_id);

  void FrameAvailable(int slot) override {
    std::lock_guard lock(mutex);
    pushed.push_back(images.count(slot) > 0 ? images[slot] : 0);
  }

  void SlotFreed(int slot) override {
    std::lock_guard lock(mutex);
    auto image = images.find(slot);
    if (image == images.end()) return;
    closed.push_back(image->second);
    images.erase(image);
  }

  mln_status Attach(mln_map, const TargetSize& size,
                    mln_render_session* out_session) override {
    attached_size = size;
    *out_session = kSessionHandle;
    return MLN_STATUS_OK;
  }

  mln_status SetTarget(mln_render_session, const TargetSize& size) override {
    ++set_targets;
    attached_size = size;
    return MLN_STATUS_OK;
  }

  void WillResize(const TargetSize& size) override {
    will_resize_width = size.physical_width;
  }

  bool CanPresent() const override { return can_present.load(); }

  void ReleaseSurfaces() override { surfaces_released = true; }

  void Unregister() override { unregistered = true; }

  // Set when the last target released its surfaces and unregistered; read
  // after dispose has destroyed the target.
  static inline std::atomic<bool> surfaces_released{false};
  static inline std::atomic<bool> unregistered{false};

  std::atomic<bool> can_present{true};
  std::atomic<int> set_targets{0};
  std::atomic<uint32_t> will_resize_width{0};
  TargetSize attached_size{};

  // Whether WillRender delivers the frame's image at once.
  std::atomic<bool> deliver_early{false};

  std::mutex mutex;
  // The frame ids passed to WillRender, in order.
  std::vector<uint64_t> will_render;
  // The frame id of the image each slot keeps.
  std::map<int, uint64_t> images;
  // The frame ids of the images given to Flutter, and of those released.
  std::vector<uint64_t> pushed;
  std::vector<uint64_t> closed;
};

// A copy-free buffer target with four slots. Its buffers are the slot
// indexes plus one; the fallback is 100.
class FakeBufferTarget : public BufferRenderTarget {
 public:
  int slot_count() const override { return map_texture::kBufferCount; }
  int64_t texture_id(int slot) const override { return 50 + slot; }

  mln_status Attach(mln_map, const TargetSize&,
                    mln_render_session* out_session) override {
    *out_session = kSessionHandle;
    return MLN_STATUS_OK;
  }
  mln_status SetTarget(mln_render_session, const TargetSize&) override {
    return MLN_STATUS_OK;
  }
  void Unregister() override {}

  bool PrepareBuffers(const TargetSize&) override { return true; }
  void SwapBuffersLocked(int chosen) override {
    has_fallback = chosen >= 0 || has_fallback;
  }
  void* CopyBufferLocked(int index) override {
    if (index >= 0) return reinterpret_cast<void*>(intptr_t{index + 1});
    return has_fallback ? reinterpret_cast<void*>(intptr_t{100}) : nullptr;
  }
  void ReleaseFallbackLocked() override { has_fallback = false; }
  bool CopyToBuffer(int) override { return true; }
  bool RendersIntoBuffers() const override { return true; }

  // Map thread, before each render: counts renders into a slot that the test
  // records as held by Dart.
  mln_status SelectBuffer(mln_render_session, int index) override {
    std::lock_guard lock(mutex);
    if (held.count(index) > 0) ++renders_into_held;
    return MLN_STATUS_OK;
  }

  void FrameAvailable(int slot) override {
    std::lock_guard lock(mutex);
    available.push_back(slot);
  }
  void FrameAvailable() override {}
  void ReleaseBuffersLocked() override {}

  std::mutex mutex;
  // The slots the test has chosen and not seen freed.
  std::set<int> held;
  int renders_into_held = 0;
  // The slots marked available by Select, in order.
  std::vector<int> available;
  bool has_fallback = false;
};

// Whether the next map gets a buffer target instead of a surface target.
bool use_buffer_target = false;

// The engine tokens that the fake platform has a texture registry for, and
// the token that the last render target was created with.
constexpr int64_t kEngine = 7;
constexpr int64_t kOtherEngine = 8;
int64_t last_engine = 0;

// The target and owner of the last map created.
FakeSurfaceTarget* last_target = nullptr;
FakeBufferTarget* last_buffer_target = nullptr;
std::weak_ptr<MapTexture> last_owner;

// Events received through the callback.
struct Event {
  int32_t type;
  int64_t frame_id;
  double zoom;
  int32_t physical_width;
  int64_t display_time_us;
  std::string message;
  int32_t slot;
  int64_t seq;
};
std::mutex events_mutex;
std::vector<Event> events;

void OnEvent(map_texture_event* event) {
  {
    std::lock_guard lock(events_mutex);
    events.push_back({event->type, event->frame_id, event->zoom,
                      event->physical_width, event->display_time_us,
                      event->message == nullptr ? "" : event->message,
                      event->slot, event->seq});
  }
  map_texture_event_free(event);
}

// The messages of the load failures received.
std::vector<std::string> LoadFailures() {
  std::lock_guard lock(events_mutex);
  std::vector<std::string> messages;
  for (const auto& event : events) {
    if (event.type == MAP_TEXTURE_EVENT_LOADING_FAILED) {
      messages.push_back(event.message);
    }
  }
  return messages;
}

std::vector<Event> EventsOfType(int32_t type) {
  std::lock_guard lock(events_mutex);
  std::vector<Event> frames;
  for (const auto& event : events) {
    if (event.type == type) frames.push_back(event);
  }
  return frames;
}

std::vector<Event> FrameEvents() {
  return EventsOfType(MAP_TEXTURE_EVENT_FRAME_DISPLAYED);
}

std::vector<Event> ReadyEvents() {
  return EventsOfType(MAP_TEXTURE_EVENT_FRAME_READY);
}

// Dart's choice of the newest finished frame (design D140). Returns the
// status, and the chosen frame in `out` if one was chosen.
int32_t SelectNewest(int64_t handle, map_texture_frame* out = nullptr) {
  map_texture_frame frame{};
  int32_t status = map_texture_select_newest(handle, &frame);
  if (out != nullptr) *out = frame;
  return status;
}

// Waits up to two seconds for `condition`.
bool WaitFor(const std::function<bool()>& condition) {
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (std::chrono::steady_clock::now() < deadline) {
    if (condition()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return condition();
}

void Sleep(int ms) {
  std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

map_texture_stats Stats(int64_t handle) {
  map_texture_stats stats{};
  map_texture_get_stats(handle, &stats);
  return stats;
}

// Sets `error` to the message of map_texture_create().
int64_t CreateMapWithRules(const std::vector<const char*>& strings,
                           const std::vector<int32_t>& counts,
                           std::string* error = nullptr,
                           int64_t engine = kEngine) {
  fake_mln::Reset();
  {
    std::lock_guard lock(events_mutex);
    events.clear();
  }
  char* message = nullptr;
  int64_t handle = map_texture_create(
      engine, 2.0, 1, OnEvent, strings.empty() ? nullptr : strings.data(),
      counts.empty() ? nullptr : counts.data(),
      static_cast<int32_t>(counts.size()), &message);
  CHECK((handle > 0) == (message == nullptr));
  if (error != nullptr) *error = message == nullptr ? "" : message;
  map_texture_string_free(message);
  return handle;
}

int64_t CreateMap() {
  int64_t handle = CreateMapWithRules({}, {});
  CHECK(handle > 0);
  return handle;
}

void FakeSurfaceTarget::DeliverEarly(uint64_t frame_id) {
  auto owner = last_owner.lock();
  if (!owner) return;
  bool kept = owner->OnFrameImage(frame_id, [this, frame_id](int slot) {
    std::lock_guard lock(mutex);
    images[slot] = frame_id;
  });
  CHECK(kept);
}

// The image listener's part: delivers the image of frame `frame_id`, and
// returns whether the map published it.
bool DeliverImage(uint64_t frame_id) {
  auto owner = last_owner.lock();
  FakeSurfaceTarget* target = last_target;
  return owner->OnFrameImage(frame_id, [target, frame_id](int slot) {
    std::lock_guard lock(target->mutex);
    target->images[slot] = frame_id;
  });
}

// Plays the image listener and Dart for a surface map while it lives: it
// delivers the image of each frame the map has queued, and chooses the
// newest ready frame.
class SurfaceDart {
 public:
  explicit SurfaceDart(int64_t handle)
      : handle_(handle), thread_([this] { Run(); }) {}
  ~SurfaceDart() {
    stop_ = true;
    thread_.join();
  }

 private:
  void Run() {
    uint64_t delivered = 0;
    int64_t chosen = 0;
    while (!stop_) {
      // Frame k is queued once k frames have rendered.
      uint64_t rendered = static_cast<uint64_t>(Stats(handle_).rendered_frames);
      while (delivered < rendered) DeliverImage(++delivered);
      auto ready = ReadyEvents();
      if (!ready.empty() && ready.back().frame_id > chosen) {
        chosen = ready.back().frame_id;
        SelectNewest(handle_);
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  }

  const int64_t handle_;
  std::atomic<bool> stop_{false};
  std::thread thread_;
};

void SurfaceFrameIsReportedWithoutDisplayTime() {
  int64_t handle = CreateMap();
  {
    SurfaceDart dart(handle);
    map_texture_set_camera(handle, 51.5, -0.1, 12.5, 0, 1);
    map_texture_resize(handle, 200, 100, 2.0);
    CHECK(last_target->will_resize_width.load() == 400);
    CHECK(WaitFor([] { return !FrameEvents().empty(); }));
  }
  auto frames = FrameEvents();
  CHECK(frames[0].display_time_us == -1);
  CHECK(frames[0].physical_width == 400);
  CHECK(frames[0].zoom == 12.5);
  CHECK(last_target->attached_size.physical_height == 200);
  // A surface target has no display buffers for Flutter to take.
  auto owner = last_owner.lock();
  CHECK(owner->Present(0) == nullptr);
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames == 1);
  CHECK(stats.presented_frames == 1);
  CHECK(stats.copy_count == 0);
  owner.reset();
  FakeSurfaceTarget::surfaces_released = false;
  FakeSurfaceTarget::unregistered = false;
  map_texture_dispose(handle);
  CHECK(FakeSurfaceTarget::surfaces_released.load());
  CHECK(FakeSurfaceTarget::unregistered.load());
}

void NoRenderWithoutSurface() {
  int64_t handle = CreateMap();
  last_target->can_present = false;
  map_texture_resize(handle, 100, 100, 2.0);
  Sleep(100);
  CHECK(fake_mln::RenderCount() == 0);
  // The surface returns through a target task, which renders the pending
  // frame.
  auto owner = last_owner.lock();
  FakeSurfaceTarget* target = last_target;
  std::thread::id task_thread;
  owner->RunTargetTask(
      [&](mln_render_session session, const TargetSize& size) {
        task_thread = std::this_thread::get_id();
        CHECK(session == kSessionHandle);
        CHECK(size.physical_width == 200);
        target->can_present = true;
      },
      /*wait=*/true);
  CHECK(task_thread != std::thread::id());
  CHECK(task_thread != std::this_thread::get_id());
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 1; }));
  // A task after the first frame renders the pending frame again, as after a
  // new surface.
  owner->RunTargetTask([](mln_render_session, const TargetSize&) {}, true);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 2; }));
  owner.reset();
  map_texture_dispose(handle);
}

void TaskWaitEndsAtDispose() {
  int64_t handle = CreateMap();
  auto owner = last_owner.lock();
  map_texture_dispose(handle);
  // The map thread has stopped, so the task never runs; the wait ends.
  bool ran = false;
  owner->RunTargetTask([&](mln_render_session, const TargetSize&) { ran = true; },
                       true);
  CHECK(!ran);
}

// A clock the test advances.
std::atomic<int64_t> fake_now{0};
int64_t FakeNow() { return fake_now.load(); }

// Designs D53 and D134: renders are paced to one per display refresh
// interval.
void RendersArePacedByRefreshInterval() {
  fake_now = 1'000'000'000;
  map_texture::SetClockForTesting(FakeNow);
  fake_mln::SetClock(FakeNow);
  int64_t handle = CreateMap();
  map_texture_set_display_refresh_rate(handle, 120);
  constexpr int64_t kInterval = 1'000'000'000 / 120;
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 1; }));

  // A render update arrives at once, so the next render waits for the end of
  // the interval.
  fake_mln::QueueRenderUpdate();
  Sleep(50);
  CHECK(fake_mln::RenderCount() == 1);
  CHECK(Stats(handle).interval_waits == 1);
  fake_now += kInterval - 1;
  fake_mln::QueueRenderUpdate();
  Sleep(50);
  CHECK(fake_mln::RenderCount() == 1);
  // Counted once per deferred render.
  CHECK(Stats(handle).interval_waits == 1);
  fake_now += 1;
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 2; }));
  auto starts = fake_mln::RenderStarts();
  CHECK(starts.size() == 2);
  CHECK(starts[1] - starts[0] >= kInterval);

  // Renders don't wait for Dart to choose a frame (design D134).
  CHECK(ReadyEvents().empty());
  CHECK(Stats(handle).waits_for_display == 0);

  // A render update after more than an interval renders at once.
  fake_now += 5 * kInterval;
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 3; }));
  CHECK(Stats(handle).interval_waits == 1);

  map_texture_dispose(handle);
  map_texture::SetClockForTesting(nullptr);
  fake_mln::SetClock(nullptr);
}

// The frame-ready event comes only when the frame's image arrives, and Dart's
// first choice of a frame gives its image to Flutter once (designs D131 and
// D132).
void SurfaceFrameIsReadyWhenItsImageArrives() {
  int64_t handle = CreateMap();
  map_texture_set_camera(handle, 0, 0, 6, 0, 4);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 1; }));
  Sleep(50);
  CHECK(ReadyEvents().empty());
  {
    std::lock_guard lock(last_target->mutex);
    CHECK((last_target->will_render == std::vector<uint64_t>{1}));
  }
  CHECK(DeliverImage(1));
  auto ready = ReadyEvents();
  CHECK(ready.size() == 1);
  CHECK(ready[0].frame_id == 1);
  CHECK(ready[0].seq == 4);
  CHECK(ready[0].zoom == 6);
  CHECK(FrameEvents().empty());
  map_texture_frame chosen{};
  CHECK(SelectNewest(handle, &chosen) == MAP_TEXTURE_OK);
  CHECK(chosen.frame_id == 1);
  CHECK(chosen.slot == ready[0].slot);
  CHECK(chosen.seq == 4);
  CHECK(chosen.zoom == 6);
  CHECK(chosen.physical_width == ready[0].physical_width);
  // No newer frame: nothing is pushed or reported again.
  for (int i = 0; i < 2; ++i) {
    CHECK(SelectNewest(handle) == MAP_TEXTURE_NOT_SELECTED);
  }
  {
    std::lock_guard lock(last_target->mutex);
    CHECK((last_target->pushed == std::vector<uint64_t>{1}));
  }
  auto frames = FrameEvents();
  CHECK(frames.size() == 1);
  CHECK(frames[0].frame_id == 1);
  CHECK(frames[0].slot == ready[0].slot);
  CHECK(frames[0].display_time_us == -1);
  CHECK(Stats(handle).presented_frames == 1);
  map_texture_dispose(handle);
}

// Design D131: the listener can receive a frame's image before render_update
// returns; the map thread then publishes the frame when the render returns.
void SurfaceImageBeforeRenderReturns() {
  int64_t handle = CreateMap();
  last_target->deliver_early = true;
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return ReadyEvents().size() == 1; }));
  auto ready = ReadyEvents()[0];
  CHECK(ready.frame_id == 1);
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return ReadyEvents().size() == 2; }));
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).empty());
  {
    std::lock_guard lock(last_target->mutex);
    CHECK(last_target->images.size() == 2);
  }
  map_texture_dispose(handle);
}

// Design D131: a frame whose image never arrives, because a newer frame
// replaced it on the surface, frees its slot when the newer frame arrives.
void SurfaceFrameWithoutImageIsFreedByNewerFrame() {
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kAlways);
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 1; }));
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 2; }));
  CHECK(DeliverImage(2));
  auto ready = ReadyEvents();
  CHECK(ready.size() == 1);
  CHECK(ready[0].frame_id == 2);
  // The image of the replaced frame is refused without an error.
  CHECK(!DeliverImage(1));
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).empty());
  // Frames keep rendering into free slots while Dart chooses none.
  for (int frame = 3; frame <= 12; ++frame) {
    fake_mln::QueueRenderUpdate();
    CHECK(WaitFor([handle, frame] {
      return Stats(handle).rendered_frames == frame;
    }));
    CHECK(DeliverImage(frame));
  }
  CHECK(Stats(handle).skipped_renders == 0);
  {
    // Each replaced ready frame released its image.
    std::lock_guard lock(last_target->mutex);
    CHECK(last_target->images.size() == 1);
    CHECK(last_target->closed.size() == 10);
  }
  map_texture_dispose(handle);
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kAuto);
}

// Design D133: Dart chooses every frame, and each chosen image is released
// after three later choices.
void SurfaceSlotIsFreedAfterThreeLaterChoices() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  for (int frame = 1; frame <= 8; ++frame) {
    CHECK(WaitFor([handle, frame] {
      return Stats(handle).rendered_frames == frame;
    }));
    CHECK(DeliverImage(frame));
    auto ready = ReadyEvents().back();
    map_texture_frame chosen{};
    CHECK(SelectNewest(handle, &chosen) == MAP_TEXTURE_OK);
    CHECK(chosen.frame_id == ready.frame_id);
    {
      std::lock_guard lock(last_target->mutex);
      std::vector<uint64_t> expected;
      for (int closed = 1; closed <= frame - 3; ++closed) {
        expected.push_back(closed);
      }
      CHECK(last_target->closed == expected);
    }
    fake_mln::QueueRenderUpdate();
  }
  auto stats = Stats(handle);
  CHECK(stats.skipped_renders == 0);
  CHECK(stats.max_slots_in_use <= map_texture::kChoiceReleasedBufferCount);
  map_texture_dispose(handle);
}

// Design D131: an image whose frame no slot ever queued is reported once.
void SurfaceImageOfUnknownFrameIsReportedOnce() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 1; }));
  CHECK(!DeliverImage(1000));
  CHECK(!DeliverImage(1001));
  auto errors = EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR);
  CHECK(errors.size() == 1);
  CHECK(errors[0].message == "received an image of unknown frame 1000");
  map_texture_dispose(handle);
}

// A target task, which replaces or removes the surface, frees the slot of a
// frame whose image hasn't arrived, so that the map renders again.
void SurfaceTargetTaskFreesQueuedFrame() {
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kNever);
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 1; }));
  auto owner = last_owner.lock();
  owner->RunTargetTask([](mln_render_session, const TargetSize&) {}, true);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 2; }));
  // The first frame's image may still arrive; it is refused without an
  // error.
  CHECK(!DeliverImage(1));
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).empty());
  owner.reset();
  map_texture_dispose(handle);
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kAuto);
}

// Design D137: after ResetSlots, the slots' images are released and no frame
// from before can be chosen.
void SurfaceResetSlotsReleasesImages() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 1; }));
  CHECK(DeliverImage(1));
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  last_owner.lock()->ResetSlots();
  {
    std::lock_guard lock(last_target->mutex);
    CHECK(last_target->images.empty());
    CHECK((last_target->closed == std::vector<uint64_t>{1}));
  }
  CHECK(SelectNewest(handle) == MAP_TEXTURE_NOT_SELECTED);
  map_texture_dispose(handle);
}

void IdleMapRendersNothing() {
  int64_t handle = CreateMap();
  SurfaceDart dart(handle);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return FrameEvents().size() == 1; }));
  Sleep(10'000);
  CHECK(fake_mln::RenderCount() == 1);
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames == 1);
  CHECK(stats.interval_waits == 0);
  map_texture_dispose(handle);
}

void NoRenderWhilePaused() {
  int64_t handle = CreateMap();
  SurfaceDart dart(handle);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 1; }));
  map_texture_set_paused_for_testing(1);
  map_texture_set_camera(handle, 0, 0, 3, 0, 1);
  Sleep(300);
  CHECK(fake_mln::RenderCount() == 1);
  CHECK(Stats(handle).paused_renders > 0);
  map_texture_set_paused_for_testing(0);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 2; }));
  CHECK(WaitFor([] {
    auto frames = FrameEvents();
    return frames.size() == 2 && frames[1].zoom == 3;
  }));
  map_texture_dispose(handle);
}

void FrameReportsLatestCameraSequenceNumber() {
  int64_t handle = CreateMap();
  SurfaceDart dart(handle);
  map_texture_set_camera(handle, 0, 0, 1, 0, 1);
  map_texture_set_camera(handle, 0, 0, 2, 0, 2);
  map_texture_set_camera(handle, 0, 0, 3, 0, 3);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return FrameEvents().size() == 1; }));
  CHECK(FrameEvents()[0].seq == 3);
  CHECK(FrameEvents()[0].zoom == 3);
  // A frame after a tile load, without a camera change, reports the last
  // applied number.
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return FrameEvents().size() == 2; }));
  CHECK(FrameEvents()[1].seq == 3);
  map_texture_dispose(handle);
}

int64_t CreateBufferMap() {
  use_buffer_target = true;
  int64_t handle = CreateMap();
  use_buffer_target = false;
  return handle;
}

// Dart's part: records in the test's model that the frame of `ready`, the
// newest finished frame, is held, then chooses the newest finished frame.
void Choose(int64_t handle, const Event& ready) {
  {
    std::lock_guard lock(last_buffer_target->mutex);
    last_buffer_target->held.insert(ready.slot);
  }
  map_texture_frame chosen{};
  CHECK(SelectNewest(handle, &chosen) == MAP_TEXTURE_OK);
  CHECK(chosen.frame_id == ready.frame_id);
  CHECK(chosen.slot == ready.slot);
}

// The raster thread's part: presents `slot`, then removes from the model the
// slots chosen before it, which `chosen_order` lists in the order chosen. The
// model's lock is held across both, so that the map thread doesn't render
// into a slot that Present() freed before the model has removed it.
void PresentSlot(MapTexture& owner, int slot, std::vector<int>& chosen_order) {
  std::lock_guard lock(last_buffer_target->mutex);
  owner.Present(slot);
  for (size_t i = 0; i < chosen_order.size(); ++i) {
    if (chosen_order[i] != slot) continue;
    for (size_t j = 0; j < i; ++j) {
      if (std::find(chosen_order.begin() + i, chosen_order.end(),
                    chosen_order[j]) == chosen_order.end()) {
        last_buffer_target->held.erase(chosen_order[j]);
      }
    }
    chosen_order.erase(chosen_order.begin(), chosen_order.begin() + i);
    break;
  }
}

void ReadyEventPrecedesDisplayedEvent() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_set_camera(handle, 0, 0, 4, 0, 7);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return ReadyEvents().size() == 1; }));
  // Not displayed until Dart chooses the frame.
  CHECK(owner->Present(0) == nullptr);
  CHECK(FrameEvents().empty());
  auto ready = ReadyEvents()[0];
  CHECK(ready.seq == 7);
  CHECK(ready.zoom == 4);
  CHECK(ready.display_time_us == 0);
  Choose(handle, ready);
  {
    std::lock_guard lock(last_buffer_target->mutex);
    CHECK((last_buffer_target->available == std::vector<int>{ready.slot}));
  }
  CHECK(owner->Present(ready.slot) ==
        reinterpret_cast<void*>(intptr_t{ready.slot + 1}));
  {
    std::lock_guard lock(events_mutex);
    int ready_at = -1;
    int displayed_at = -1;
    for (size_t i = 0; i < events.size(); ++i) {
      if (events[i].frame_id != ready.frame_id) continue;
      if (events[i].type == MAP_TEXTURE_EVENT_FRAME_READY) ready_at = int(i);
      if (events[i].type == MAP_TEXTURE_EVENT_FRAME_DISPLAYED) {
        displayed_at = int(i);
        CHECK(events[i].slot == ready.slot);
        CHECK(events[i].seq == 7);
        CHECK(events[i].display_time_us > 0);
      }
    }
    CHECK(ready_at >= 0);
    CHECK(displayed_at > ready_at);
  }
  owner.reset();
  map_texture_dispose(handle);
}

// Design D139: a frame replaced by rendering ahead after Dart learned of it
// isn't chosen; Dart gets the newer frame, and the frame Dart chose before
// stays displayed until Flutter presents the newer one.
void NewestFrameIsChosenAfterReplacement() {
  int64_t handle = CreateBufferMap();
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kAlways);
  auto owner = last_owner.lock();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return ReadyEvents().size() == 1; }));
  auto shown = ReadyEvents()[0];
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  void* shown_buffer = reinterpret_cast<void*>(intptr_t{shown.slot + 1});
  CHECK(owner->Present(shown.slot) == shown_buffer);
  // Rendered ahead, the third frame replaces the second.
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return ReadyEvents().size() == 2; }));
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return ReadyEvents().size() == 3; }));
  auto newest = ReadyEvents()[2];
  map_texture_frame chosen{};
  CHECK(SelectNewest(handle, &chosen) == MAP_TEXTURE_OK);
  CHECK(chosen.frame_id == newest.frame_id);
  CHECK(chosen.slot == newest.slot);
  {
    std::lock_guard lock(last_buffer_target->mutex);
    CHECK((last_buffer_target->available ==
           std::vector<int>{shown.slot, newest.slot}));
  }
  // No newer frame: nothing is chosen, and the texture isn't marked again.
  CHECK(SelectNewest(handle) == MAP_TEXTURE_NOT_SELECTED);
  {
    std::lock_guard lock(last_buffer_target->mutex);
    CHECK(last_buffer_target->available.size() == 2);
  }
  // The frame chosen before stays displayable until the newer one is
  // presented.
  CHECK(owner->Present(shown.slot) == shown_buffer);
  CHECK(owner->Present(newest.slot) ==
        reinterpret_cast<void*>(intptr_t{newest.slot + 1}));
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kAuto);
  owner.reset();
  map_texture_dispose(handle);
}

// Design D124: the next render waits until Dart has chosen the latest frame,
// and the choice starts it.
void RenderWaitingForChoiceStartsAfterChoice() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return ReadyEvents().size() == 1; }));
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([handle] { return Stats(handle).waits_for_display > 0; }));
  Sleep(200);
  CHECK(Stats(handle).rendered_frames == 1);
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 2; }));
  owner.reset();
  map_texture_dispose(handle);
}

void MapDoesNotRenderIntoHeldSlot() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_resize(handle, 100, 100, 2.0);
  std::vector<int> chosen_order;
  int previous = -1;
  for (size_t frame = 1; frame <= 40; ++frame) {
    CHECK(WaitFor([frame] { return ReadyEvents().size() == frame; }));
    if (ReadyEvents().size() != frame) break;
    auto ready = ReadyEvents().back();
    Choose(handle, ready);
    chosen_order.push_back(ready.slot);
    // The next frame renders while Flutter presents the frame chosen
    // before.
    fake_mln::QueueRenderUpdate();
    if (previous >= 0) PresentSlot(*owner, previous, chosen_order);
    previous = ready.slot;
  }
  {
    std::lock_guard lock(last_buffer_target->mutex);
    CHECK(last_buffer_target->renders_into_held == 0);
  }
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames >= 40);
  CHECK(stats.skipped_renders == 0);
  CHECK(stats.max_slots_in_use <= 4);
  owner.reset();
  map_texture_dispose(handle);
}

void IdleBufferMapRendersNothing() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return ReadyEvents().size() == 1; }));
  auto ready = ReadyEvents()[0];
  Choose(handle, ready);
  owner->Present(ready.slot);
  Sleep(10'000);
  CHECK(fake_mln::RenderCount() == 1);
  CHECK(Stats(handle).rendered_frames == 1);
  owner.reset();
  map_texture_dispose(handle);
}

void AllSlotsHeldWithoutPresent() {
  int64_t handle = CreateBufferMap();
  map_texture_resize(handle, 100, 100, 2.0);
  // Dart chooses each frame, and Flutter never presents.
  for (size_t frame = 1; frame <= 4; ++frame) {
    CHECK(WaitFor([frame] { return ReadyEvents().size() == frame; }));
    if (ReadyEvents().size() != frame) break;
    CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
    fake_mln::QueueRenderUpdate();
  }
  CHECK(WaitFor([handle] { return Stats(handle).skipped_renders > 0; }));
  auto stats = Stats(handle);
  CHECK(stats.max_slots_in_use == 4);
  CHECK(stats.rendered_frames == 4);
  // A present frees the slots chosen before the presented one.
  auto owner = last_owner.lock();
  owner->Present(ReadyEvents().back().slot);
  CHECK(WaitFor([] { return ReadyEvents().size() == 5; }));
  owner.reset();
  map_texture_dispose(handle);
}

void SelectAfterDisposeReportsDisposed() {
  int64_t handle = CreateBufferMap();
  int64_t ids[4] = {};
  CHECK(map_texture_texture_ids(handle, ids, 4) == 4);
  CHECK(ids[0] == 50 && ids[3] == 53);
  map_texture_dispose(handle);
  CHECK(SelectNewest(handle) == MAP_TEXTURE_ERROR_DISPOSED);
  CHECK(map_texture_texture_ids(handle, ids, 4) == MAP_TEXTURE_ERROR_DISPOSED);
  CHECK(map_texture_set_camera(handle, 0, 0, 0, 0, 1) ==
        MAP_TEXTURE_ERROR_DISPOSED);
}

// Design D135: six slots share the surface target's one texture.
void SurfaceMapHasSixSlotsWithOneTexture() {
  int64_t handle = CreateMap();
  int64_t ids[8] = {};
  CHECK(map_texture_texture_ids(handle, ids, 8) == 6);
  for (int i = 0; i < 6; ++i) CHECK(ids[i] == 42);
  CHECK(map_texture_select_newest(handle, nullptr) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  map_texture_dispose(handle);
}

constexpr const char* kSetCacheSize =
    "mln_runtime_set_maximum_ambient_cache_size_start";

// The names of the calls recorded since the last map was created.
std::vector<std::string> CallNames() {
  std::vector<std::string> names;
  for (const auto& call : fake_mln::Calls()) names.push_back(call.name);
  return names;
}

// The sizes passed to mln_runtime_set_maximum_ambient_cache_size_start since
// the last map was created.
std::vector<uint64_t> CacheSizes() {
  std::vector<uint64_t> sizes;
  for (const auto& call : fake_mln::Calls()) {
    if (call.name == kSetCacheSize) sizes.push_back(call.size);
  }
  return sizes;
}

bool StyleLoaded() {
  auto names = CallNames();
  return !names.empty() && names.back() == "mln_map_set_style_url";
}

// Run this test before any test sets a maximum size, because the maximum size
// is process-wide.
void NoCacheSizeWithoutValue() {
  int64_t handle = CreateMap();
  map_texture_load_style_url(handle, "https://example.com/style.json");
  CHECK(WaitFor(StyleLoaded));
  CHECK(CacheSizes().empty());
  map_texture_dispose(handle);
}

void CacheSizeIsSetBeforeMapAndStyle() {
  CHECK(map_texture_set_maximum_cache_size(200 << 20) == MAP_TEXTURE_OK);
  int64_t handle = CreateMap();
  map_texture_load_style_url(handle, "https://example.com/style.json");
  CHECK(WaitFor(StyleLoaded));
  CHECK((CallNames() == std::vector<std::string>{
                            "mln_runtime_create", kSetCacheSize,
                            "mln_runtime_offline_operation_discard",
                            "mln_map_create", "mln_map_set_style_url"}));
  CHECK((CacheSizes() == std::vector<uint64_t>{200 << 20}));
  map_texture_dispose(handle);
}

void CacheSizeAppliesToMapsCreatedAfterIt() {
  CHECK(map_texture_set_maximum_cache_size(200 << 20) == MAP_TEXTURE_OK);
  int64_t first = CreateMap();
  CHECK(map_texture_set_maximum_cache_size(10 << 20) == MAP_TEXTURE_OK);
  map_texture_load_style_url(first, "https://example.com/style.json");
  CHECK(WaitFor(StyleLoaded));
  CHECK((CacheSizes() == std::vector<uint64_t>{200 << 20}));
  int64_t second = CreateMap();
  CHECK((CacheSizes() == std::vector<uint64_t>{10 << 20}));
  map_texture_dispose(first);
  map_texture_dispose(second);
}

void NegativeCacheSizeIsRejected() {
  CHECK(map_texture_set_maximum_cache_size(10 << 20) == MAP_TEXTURE_OK);
  CHECK(map_texture_set_maximum_cache_size(-1) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  int64_t handle = CreateMap();
  CHECK((CacheSizes() == std::vector<uint64_t>{10 << 20}));
  map_texture_dispose(handle);
}

void ZeroCacheSizeIsApplied() {
  CHECK(map_texture_set_maximum_cache_size(0) == MAP_TEXTURE_OK);
  int64_t handle = CreateMap();
  CHECK((CacheSizes() == std::vector<uint64_t>{0}));
  map_texture_dispose(handle);
}

void CacheSizeFailureIsReportedAndMapRenders() {
  CHECK(map_texture_set_maximum_cache_size(10 << 20) == MAP_TEXTURE_OK);
  fake_mln::SetMaximumCacheSizeStatus(MLN_STATUS_NATIVE_ERROR);
  int64_t handle = CreateMap();
  fake_mln::SetMaximumCacheSizeStatus(MLN_STATUS_OK);
  {
    std::lock_guard lock(events_mutex);
    CHECK(events.size() == 1 &&
          events[0].type == MAP_TEXTURE_EVENT_RENDER_ERROR);
  }
  CHECK((CallNames() == std::vector<std::string>{
                            "mln_runtime_create", kSetCacheSize,
                            "mln_map_create"}));
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 1; }));
  map_texture_dispose(handle);
}

// CallNames() without the process-wide cache size calls.
std::vector<std::string> InitCallNames() {
  std::vector<std::string> names;
  for (const auto& name : CallNames()) {
    if (name != kSetCacheSize &&
        name != "mln_runtime_offline_operation_discard") {
      names.push_back(name);
    }
  }
  return names;
}

void HeaderRulesAreCopiedAndRegistered() {
  // Strings the caller overwrites after the call.
  char url1[] = "https://tiles.example.com/v2/**";
  char name1[] = "X-Access-Key";
  char value1[] = "k2";
  char name2[] = "X-Other";
  char value2[] = "o";
  char url2[] = "https://tiles.example.com/**";
  char value3[] = "k1";
  int64_t handle = CreateMapWithRules(
      {url1, name1, value1, name2, value2, url2, name1, value3}, {2, 1});
  CHECK(handle > 0);
  for (char* text : {url1, name1, value1, name2, value2, url2, value3}) {
    std::memset(text, 'x', std::strlen(text));
  }
  CHECK(fake_mln::HeaderTransformRegistrations() == 1);
  CHECK(fake_mln::HeaderTransformUsesAdapter());
  auto rules = fake_mln::HeaderRules();
  CHECK(rules.size() == 2);
  if (rules.size() == 2) {
    for (const auto& rule : rules) {
      CHECK(rule.kind == MLN_ADAPTER_RESOURCE_KIND_ANY);
      CHECK(rule.flags == MLN_ADAPTER_URL_MATCH_GLOB);
    }
    CHECK(rules[0].url == "https://tiles.example.com/v2/**");
    CHECK((rules[0].headers == std::vector<fake_mln::Header>{
                                   {"X-Access-Key", "k2"}, {"X-Other", "o"}}));
    CHECK(rules[1].url == "https://tiles.example.com/**");
    CHECK((rules[1].headers ==
           std::vector<fake_mln::Header>{{"X-Access-Key", "k1"}}));
  }
  CHECK((InitCallNames() == std::vector<std::string>{
                                "mln_runtime_create",
                                "mln_runtime_set_http_header_transform",
                                "mln_map_create"}));
  map_texture_dispose(handle);
}

void RuleWithoutHeadersIsRegistered() {
  int64_t handle = CreateMapWithRules({"https://a.example.com/**"}, {0});
  CHECK(handle > 0);
  auto rules = fake_mln::HeaderRules();
  CHECK(rules.size() == 1 && rules[0].headers.empty());
  map_texture_dispose(handle);
}

void NoHeaderTransformWithoutRules() {
  int64_t handle = CreateMap();
  CHECK(fake_mln::HeaderTransformRegistrations() == 0);
  CHECK((InitCallNames() ==
         std::vector<std::string>{"mln_runtime_create", "mln_map_create"}));
  map_texture_dispose(handle);
}

void EmptyAssetPathKeepsDefault() {
  int64_t handle = CreateMap();
  CHECK(fake_mln::LastAssetPath() == "<null>");
  map_texture_dispose(handle);
}

void RejectedHeaderFailsCreate() {
  const char* message = "HTTP header \"Host\" is managed by MapLibre";
  fake_mln::SetHeaderValidateResult("Host", MLN_STATUS_INVALID_ARGUMENT,
                                    message);
  std::string error;
  int64_t result = CreateMapWithRules(
      {"https://a.example.com/**", "X-Ok", "1", "Host", "secret"}, {2},
      &error);
  fake_mln::SetHeaderValidateResult("", MLN_STATUS_OK, "");
  CHECK(result == MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(error == message);
  // Rejected before the map thread starts.
  CHECK(fake_mln::Calls().empty());
}

void InvalidRuleArraysFailCreate() {
  std::string error;
  fake_mln::Reset();
  char* message = nullptr;
  CHECK(map_texture_create(kEngine, 2.0, 1, OnEvent, nullptr, nullptr, 1,
                           &message) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(message != nullptr);
  map_texture_string_free(message);
  CHECK(CreateMapWithRules({"https://a.example.com/**"}, {-1}, &error) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(!error.empty());
  // A null out_error is allowed.
  CHECK(map_texture_create(kEngine, 2.0, 1, nullptr, nullptr, nullptr, 0,
                           nullptr) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(fake_mln::Calls().empty());
}

void FailedInitReportsMessage() {
  fake_mln::SetRuntimeCreateResult(MLN_STATUS_NATIVE_ERROR, "no runtime");
  std::string error;
  int64_t result = CreateMapWithRules({}, {}, &error);
  fake_mln::SetRuntimeCreateResult(MLN_STATUS_OK, "");
  CHECK(result == MAP_TEXTURE_ERROR_CREATE_FAILED);
  CHECK(error.find("mln_runtime_create") != std::string::npos);
  CHECK(error.find("no runtime") != std::string::npos);
}

constexpr const char* kGlyphFailure =
    "Failed to load glyph range 0-255 for font stack Noto Sans Regular:( "
    "HTTP status code 404)";

void GlyphFailureIsReportedAsLoadFailure() {
  int64_t handle = CreateMap();
  // Once for the process, however many maps are created.
  CHECK(fake_mln::LogCallbackRegistrations() == 1);
  fake_mln::QueueLogRecord({.message = kGlyphFailure});
  CHECK(WaitFor([] { return !LoadFailures().empty(); }));
  auto reported = LoadFailures();
  CHECK(reported.size() == 1);
  CHECK(reported[0] == kGlyphFailure);
  map_texture_dispose(handle);
}

void OtherLogRecordsAreNotReported() {
  int64_t handle = CreateMap();
  fake_mln::QueueLogRecord({.message = "Failed to load tile 1/0/0"});
  fake_mln::QueueLogRecord(
      {.severity = MLN_LOG_SEVERITY_WARNING, .message = kGlyphFailure});
  fake_mln::QueueLogRecord(
      {.event = MLN_LOG_EVENT_GLYPH, .message = kGlyphFailure});
  // Logged off the map thread, so it belongs to no map.
  fake_mln::Log({.message = kGlyphFailure});
  // The last record shows that the pump has passed the others on.
  fake_mln::QueueLogRecord({.message = std::string(kGlyphFailure) + " last"});
  CHECK(WaitFor([] { return !LoadFailures().empty(); }));
  Sleep(50);
  auto reported = LoadFailures();
  CHECK(reported.size() == 1);
  CHECK(reported[0] == std::string(kGlyphFailure) + " last");
  map_texture_dispose(handle);
}

void MapKeepsItsEngineToken() {
  int64_t handle = CreateMapWithRules({}, {}, nullptr, kOtherEngine);
  CHECK(handle > 0);
  CHECK(last_engine == kOtherEngine);
  auto owner = last_owner.lock();
  CHECK(owner && owner->engine() == kOtherEngine);
  owner.reset();
  map_texture_dispose(handle);
}

void DisposeEngineMapsDisposesOnlyThatEngine() {
  int64_t first = CreateMap();
  // Without the reset of CreateMapWithRules, which the live map uses.
  int64_t second =
      map_texture_create(kEngine, 2.0, 1, OnEvent, nullptr, nullptr, 0, nullptr);
  int64_t other = map_texture_create(kOtherEngine, 2.0, 1, OnEvent, nullptr,
                                     nullptr, 0, nullptr);
  CHECK(second > 0);
  CHECK(other > 0);
  map_texture::DisposeEngineMaps(kEngine);
  map_texture_stats stats{};
  CHECK(map_texture_get_stats(first, &stats) == MAP_TEXTURE_ERROR_DISPOSED);
  CHECK(map_texture_get_stats(second, &stats) == MAP_TEXTURE_ERROR_DISPOSED);
  CHECK(map_texture_load_style_url(first, "https://example.com") ==
        MAP_TEXTURE_ERROR_DISPOSED);
  CHECK(map_texture_dispose(second) == MAP_TEXTURE_ERROR_DISPOSED);
  CHECK(map_texture_get_stats(other, &stats) == MAP_TEXTURE_OK);
  CHECK(map_texture_dispose(other) == MAP_TEXTURE_OK);
}

void UnknownEngineFailsCreate() {
  std::string error;
  int64_t result = CreateMapWithRules({}, {}, &error, /*engine=*/99);
  CHECK(result == MAP_TEXTURE_ERROR_CREATE_FAILED);
  CHECK(error == map_texture::kEngineDetachedError);
  // The map thread doesn't start.
  CHECK(fake_mln::Calls().empty());
}

}  // namespace

namespace map_texture {

std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner, bool, int64_t engine,
    std::string* out_error) {
  if (engine != kEngine && engine != kOtherEngine) {
    *out_error = kEngineDetachedError;
    return nullptr;
  }
  last_engine = engine;
  last_owner = std::move(owner);
  if (use_buffer_target) {
    auto target = std::make_unique<FakeBufferTarget>();
    last_buffer_target = target.get();
    return target;
  }
  auto target = std::make_unique<FakeSurfaceTarget>();
  last_target = target.get();
  return target;
}

std::string PlatformCachePath() { return {}; }

std::string PlatformAssetPath() { return {}; }

void RunInPlatformScope(const std::function<void()>& work) { work(); }

}  // namespace map_texture

int main() {
  SurfaceFrameIsReportedWithoutDisplayTime();
  NoRenderWithoutSurface();
  TaskWaitEndsAtDispose();
  RendersArePacedByRefreshInterval();
  SurfaceFrameIsReadyWhenItsImageArrives();
  SurfaceImageBeforeRenderReturns();
  SurfaceFrameWithoutImageIsFreedByNewerFrame();
  SurfaceSlotIsFreedAfterThreeLaterChoices();
  SurfaceImageOfUnknownFrameIsReportedOnce();
  SurfaceTargetTaskFreesQueuedFrame();
  SurfaceResetSlotsReleasesImages();
  IdleMapRendersNothing();
  NoRenderWhilePaused();
  FrameReportsLatestCameraSequenceNumber();
  ReadyEventPrecedesDisplayedEvent();
  NewestFrameIsChosenAfterReplacement();
  RenderWaitingForChoiceStartsAfterChoice();
  MapDoesNotRenderIntoHeldSlot();
  IdleBufferMapRendersNothing();
  AllSlotsHeldWithoutPresent();
  SelectAfterDisposeReportsDisposed();
  SurfaceMapHasSixSlotsWithOneTexture();
  NoCacheSizeWithoutValue();
  CacheSizeIsSetBeforeMapAndStyle();
  CacheSizeAppliesToMapsCreatedAfterIt();
  NegativeCacheSizeIsRejected();
  ZeroCacheSizeIsApplied();
  CacheSizeFailureIsReportedAndMapRenders();
  HeaderRulesAreCopiedAndRegistered();
  RuleWithoutHeadersIsRegistered();
  NoHeaderTransformWithoutRules();
  EmptyAssetPathKeepsDefault();
  RejectedHeaderFailsCreate();
  InvalidRuleArraysFailCreate();
  FailedInitReportsMessage();
  GlyphFailureIsReportedAsLoadFailure();
  OtherLogRecordsAreNotReported();
  MapKeepsItsEngineToken();
  DisposeEngineMapsDisposesOnlyThatEngine();
  UnknownEngineFailsCreate();
  if (failures > 0) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("map texture tests passed\n");
  return 0;
}
