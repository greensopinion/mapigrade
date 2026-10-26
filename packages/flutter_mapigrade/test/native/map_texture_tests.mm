// Tests of MapTexture with a surface render target (design D52) and its
// display slots (D130-D135), the display slots of a buffer target
// (D122-D126, D182 and D183), camera sequence numbers (D125, D181), the
// maximum size of the tile cache (D61-D63), the HTTP header rules (D81, D82),
// glyph load failures, and the engine token of each map (D156 and D157 of the
// multiple-flutter-engines change).
//
// The tests run MapTexture on the real MapLibre Native FFI with headless Metal
// targets (design D187 of the adopt-ffi-core-executor change): the surface
// target attaches a session-owned texture, and the buffer target a borrowed
// ring of four textures. ffi_redirect.h directs the few calls whose arguments
// or failures the tests check to ffi_wrappers.mm.
#import <Metal/Metal.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "ffi_wrappers.h"
#include "map_texture.h"
#include "map_texture_api.h"
#include "projection.h"
#include "render_target.h"

using map_texture::AsyncCall;
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

id<MTLDevice> Device() {
  static id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  return device;
}

// A style without sources, so that the map renders without network access.
// Each call gives a different background color, so that loading it publishes
// a render update without a camera change.
std::string NextStyle() {
  static std::atomic<int> count{0};
  int n = ++count;
  char color[8];
  std::snprintf(color, sizeof(color), "#%02x%02x%02x", (n * 37) % 256,
                (n * 91) % 256, (n * 53) % 256);
  // Without a transition, loading it renders one frame.
  return std::string(R"({"version": 8, "transition": {"duration": 0, "delay": 0},)"
                     R"( "sources": {}, "layers": [)"
                     R"({"id": "background", "type": "background",)"
                     R"( "paint": {"background-color": ")") +
         color + R"("}}]})";
}

// A surface target with six slots that share one texture, on a session-owned
// Metal texture. The test plays the image listener: it passes the frame ids
// that WillRender recorded to MapTexture::OnFrameImage, and the target keeps
// the frame id as the slot's image.
class FakeSurfaceTarget : public SurfaceRenderTarget {
 public:
  int slot_count() const override {
    return map_texture::kChoiceReleasedBufferCount;
  }
  int64_t texture_id(int) const override { return 42; }

  void WillRender(uint64_t frame_id) override;

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

  mln_status Attach(mln_map map, const TargetSize& size,
                    const mln_render_session_attach_options& options,
                    mln_render_session* out_session,
                    const AsyncCall& call) override {
    attached_size = size;
    mln_metal_owned_texture_descriptor descriptor =
        mln_metal_owned_texture_descriptor_default();
    descriptor.extent = size.extent;
    descriptor.context.device = (__bridge void*)Device();
    return mln_map_attach_metal_owned_texture(map, &descriptor, &options,
                                              out_session, call.completion,
                                              call.diagnostic);
  }

  mln_status SetTarget(mln_render_session session, const TargetSize& size,
                       const AsyncCall& call) override {
    ++set_targets;
    attached_size = size;
    return mln_render_session_resize(session, size.extent, call.completion,
                                     call.diagnostic);
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
  // The frame ids passed to WillRender, in order, each once. The map thread
  // passes the armed frame's id before every service call (design D184).
  std::vector<uint64_t> will_render;
  // The test clock at the first WillRender of each frame id.
  std::vector<int64_t> render_starts;
  // The frame id of the image each slot keeps.
  std::map<int, uint64_t> images;
  // The frame ids of the images given to Flutter, and of those released.
  std::vector<uint64_t> pushed;
  std::vector<uint64_t> closed;
};

// A copy-free buffer target with four slots, on a borrowed ring of four Metal
// textures (design D182). Its buffers are the slot indexes plus one; the
// fallback is 100.
class FakeBufferTarget : public BufferRenderTarget {
 public:
  int slot_count() const override { return map_texture::kBufferCount; }
  int64_t texture_id(int slot) const override { return 50 + slot; }

  mln_status Attach(mln_map map, const TargetSize& size,
                    const mln_render_session_attach_options& options,
                    mln_render_session* out_session,
                    const AsyncCall& call) override {
    Ring ring{};
    mln_metal_borrowed_texture_descriptor descriptor = Descriptor(size, &ring);
    return mln_map_attach_metal_borrowed_texture(
        map, &descriptor, &options, out_session, call.completion,
        call.diagnostic);
  }
  mln_status SetTarget(mln_render_session session, const TargetSize& size,
                       const AsyncCall& call) override {
    Ring ring{};
    mln_metal_borrowed_texture_descriptor descriptor = Descriptor(size, &ring);
    return mln_render_session_set_metal_borrowed_texture_target(
        session, &descriptor, call.completion, call.diagnostic);
  }
  void Unregister() override {}

  bool PrepareBuffers(const TargetSize& size) override {
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:size.physical_width
                                    height:size.physical_height
                                 mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;
    for (auto& texture : prepared_) {
      texture = [Device() newTextureWithDescriptor:descriptor];
      if (texture == nil) return false;
    }
    return true;
  }
  void SwapBuffersLocked(int chosen) override {
    has_fallback = chosen >= 0 || has_fallback;
    current_ = prepared_;
    for (auto& texture : prepared_) texture = nil;
  }
  void* CopyBufferLocked(int index) override {
    if (index >= 0) return reinterpret_cast<void*>(intptr_t{index + 1});
    return has_fallback ? reinterpret_cast<void*>(intptr_t{100}) : nullptr;
  }
  void ReleaseFallbackLocked() override { has_fallback = false; }
  bool CopyToBuffer(int) override { return true; }
  bool RendersIntoBuffers() const override { return true; }

  // Map thread, when it acquires a frame: counts frames in a slot that the
  // test records as held by Dart.
  int FrameSlot(mln_acquired_frame frame, bool* out_current) override {
    mln_metal_texture_frame metal{};
    metal.size = sizeof(metal);
    if (mln_acquired_frame_get_metal_texture(frame, &metal, nullptr) !=
            MLN_STATUS_OK ||
        metal.slot >= current_.size()) {
      return -1;
    }
    *out_current = metal.texture == (__bridge void*)current_[metal.slot];
    std::lock_guard lock(mutex);
    if (held.count(static_cast<int>(metal.slot)) > 0) ++renders_into_held;
    return static_cast<int>(metal.slot);
  }

  void FrameAvailable(int slot) override {
    std::lock_guard lock(mutex);
    available.push_back(slot);
  }
  void FrameAvailable() override {}
  void ReleaseBuffersLocked() override {
    for (auto& texture : current_) texture = nil;
  }

  std::mutex mutex;
  // The slots the test has chosen and not seen freed.
  std::set<int> held;
  int renders_into_held = 0;
  // The slots marked available by Select, in order.
  std::vector<int> available;
  bool has_fallback = false;

 private:
  using Ring = std::array<mln_metal_borrowed_texture, map_texture::kBufferCount>;

  mln_metal_borrowed_texture_descriptor Descriptor(const TargetSize& size,
                                                   Ring* ring) {
    mln_metal_borrowed_texture_descriptor descriptor =
        mln_metal_borrowed_texture_descriptor_default();
    descriptor.extent = size.extent;
    descriptor.physical_width = size.physical_width;
    descriptor.physical_height = size.physical_height;
    for (size_t i = 0; i < ring->size(); ++i) {
      (*ring)[i].texture = (__bridge void*)current_[i];
    }
    descriptor.textures = ring->data();
    descriptor.texture_count = ring->size();
    return descriptor;
  }

  std::array<id<MTLTexture>, map_texture::kBufferCount> current_{};
  std::array<id<MTLTexture>, map_texture::kBufferCount> prepared_{};
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
  double pitch;
  int32_t physical_width;
  int64_t display_time_us;
  std::string message;
  int32_t slot;
  int64_t seq;
  int64_t request_id;
  int32_t status;
};
std::mutex events_mutex;
std::vector<Event> events;

void OnEvent(map_texture_event* event) {
  {
    std::lock_guard lock(events_mutex);
    events.push_back({event->type, event->frame_id, event->zoom,
                      event->pitch, event->physical_width, event->display_time_us,
                      event->message == nullptr ? "" : event->message,
                      event->slot, event->seq, event->request_id,
                      event->status});
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

// Waits up to five seconds for `condition`.
bool WaitFor(const std::function<bool()>& condition) {
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
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

// Publishes a render update without a camera change, as a tile load would:
// loads a style with another background color.
void QueueRenderUpdate(int64_t handle) {
  map_texture_load_style_json(handle, NextStyle().c_str());
}

// Waits until the map has rendered `frames` frames and renders no more for
// 200 ms, so that a test counts from a settled map.
bool Settled(int64_t handle, int64_t frames) {
  if (!WaitFor([&] { return Stats(handle).rendered_frames >= frames; })) {
    return false;
  }
  int64_t rendered = -1;
  while (rendered != Stats(handle).rendered_frames) {
    rendered = Stats(handle).rendered_frames;
    Sleep(200);
  }
  return true;
}

// Sets `error` to the message of map_texture_create().
int64_t CreateMapWithRules(const std::vector<const char*>& strings,
                           const std::vector<int32_t>& counts,
                           std::string* error = nullptr,
                           int64_t engine = kEngine, double max_pitch = 85) {
  ffi_wrappers::Reset();
  {
    std::lock_guard lock(events_mutex);
    events.clear();
  }
  char* message = nullptr;
  int64_t handle = map_texture_create(
      engine, 2.0, 1, max_pitch, OnEvent,
      strings.empty() ? nullptr : strings.data(),
      counts.empty() ? nullptr : counts.data(),
      static_cast<int32_t>(counts.size()), &message);
  CHECK((handle > 0) == (message == nullptr));
  if (error != nullptr) *error = message == nullptr ? "" : message;
  map_texture_string_free(message);
  return handle;
}

// Creates a map, and with `style`, loads a style that renders without network
// access.
int64_t CreateMap(bool style = true, double max_pitch = 85) {
  int64_t handle = CreateMapWithRules({}, {}, nullptr, kEngine, max_pitch);
  CHECK(handle > 0);
  if (style) map_texture_load_style_json(handle, NextStyle().c_str());
  return handle;
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

// A clock the test advances, when a test installs it.
std::atomic<int64_t> fake_now{0};
std::atomic<bool> fake_clock{false};
int64_t FakeNow() { return fake_now.load(); }

void FakeSurfaceTarget::WillRender(uint64_t frame_id) {
  {
    std::lock_guard lock(mutex);
    if (!will_render.empty() && will_render.back() == frame_id) return;
    will_render.push_back(frame_id);
    render_starts.push_back(fake_clock ? FakeNow() : 0);
  }
  if (!deliver_early) return;
  // Delivers the image before the service call returns, as the listener can
  // on a device.
  auto owner = last_owner.lock();
  if (!owner) return;
  bool kept = owner->OnFrameImage(frame_id, [this, frame_id](int slot) {
    std::lock_guard lock(mutex);
    images[slot] = frame_id;
  });
  CHECK(kept);
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
    map_texture_set_camera(handle, 51.5, -0.1, 12.5, 0, 0, 1);
    map_texture_resize(handle, 200, 100, 2.0);
    CHECK(last_target->will_resize_width.load() == 400);
    CHECK(WaitFor([] { return !FrameEvents().empty(); }));
    CHECK(Settled(handle, 1));
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
  CHECK(stats.rendered_frames >= 1);
  CHECK(stats.presented_frames >= 1);
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
  Sleep(300);
  CHECK(Stats(handle).rendered_frames == 0);
  // The surface returns through a target task, which renders the pending
  // frame.
  auto owner = last_owner.lock();
  FakeSurfaceTarget* target = last_target;
  std::thread::id task_thread;
  owner->RunTargetTask(
      [&](mln_render_session session, const TargetSize& size) {
        task_thread = std::this_thread::get_id();
        CHECK(session != MLN_HANDLE_NULL);
        CHECK(size.physical_width == 200);
        target->can_present = true;
      },
      /*wait=*/true);
  CHECK(task_thread != std::thread::id());
  CHECK(task_thread != std::this_thread::get_id());
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames >= 1; }));
  // Under #760, a task after the first frame renders again only when it
  // replaces the target, which makes the session run the waiting demand
  // again; this fake surface has no target to replace.
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

// Designs D53 and D134: renders are paced to one per display refresh
// interval.
void RendersArePacedByRefreshInterval() {
  fake_now = 1'000'000'000;
  fake_clock = true;
  map_texture::SetClockForTesting(FakeNow);
  int64_t handle = CreateMap();
  map_texture_set_display_refresh_rate(handle, 120);
  constexpr int64_t kInterval = 1'000'000'000 / 120;
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;
  // Under #760 the map thread arms the next frame demand as soon as a frame
  // has rendered, so the wait for the interval's end is counted then, once.
  int64_t waits = Stats(handle).interval_waits;
  CHECK(waits >= 1);

  // A render update arrives at once, so the next render waits for the end of
  // the interval.
  QueueRenderUpdate(handle);
  Sleep(100);
  CHECK(Stats(handle).rendered_frames == rendered);
  fake_now += kInterval - 1;
  QueueRenderUpdate(handle);
  Sleep(100);
  CHECK(Stats(handle).rendered_frames == rendered);
  // Counted once per deferred render.
  CHECK(Stats(handle).interval_waits == waits);
  fake_now += 1;
  CHECK(WaitFor([handle, rendered] {
    return Stats(handle).rendered_frames == rendered + 1;
  }));
  {
    std::lock_guard lock(last_target->mutex);
    auto& starts = last_target->render_starts;
    CHECK(starts.size() >= 2);
    if (starts.size() >= 2) {
      CHECK(starts[starts.size() - 1] - starts[starts.size() - 2] >= kInterval);
    }
  }

  // Renders don't wait for Dart to choose a frame (design D134).
  CHECK(ReadyEvents().empty());
  CHECK(Stats(handle).waits_for_display == 0);

  // A render update after more than an interval renders at once.
  fake_now += 5 * kInterval;
  QueueRenderUpdate(handle);
  CHECK(WaitFor([handle, rendered] {
    return Stats(handle).rendered_frames == rendered + 2;
  }));
  CHECK(Stats(handle).interval_waits <= waits + 2);

  map_texture_dispose(handle);
  map_texture::SetClockForTesting(nullptr);
  fake_clock = false;
}

// The frame-ready event comes only when the frame's image arrives, and Dart's
// first choice of a frame gives its image to Flutter once (designs D131 and
// D132).
void SurfaceFrameIsReadyWhenItsImageArrives() {
  int64_t handle = CreateMap();
  map_texture_set_camera(handle, 0, 0, 6, 0, 0, 4);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames == 1; }));
  Sleep(50);
  CHECK(ReadyEvents().empty());
  {
    std::lock_guard lock(last_target->mutex);
    CHECK(!last_target->will_render.empty() &&
          last_target->will_render.front() == 1);
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

// Design D131: the listener can receive a frame's image before the service
// call returns; the map thread then publishes the frame when the frame result
// arrives.
void SurfaceImageBeforeRenderReturns() {
  int64_t handle = CreateMap();
  last_target->deliver_early = true;
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return ReadyEvents().size() >= 1; }));
  CHECK(Settled(handle, 1));
  size_t ready = ReadyEvents().size();
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  QueueRenderUpdate(handle);
  CHECK(WaitFor([ready] { return ReadyEvents().size() == ready + 1; }));
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).empty());
  map_texture_dispose(handle);
}

// Design D131: a frame whose image never arrives, because a newer frame
// replaced it on the surface, frees its slot when the newer frame arrives.
void SurfaceFrameWithoutImageIsFreedByNewerFrame() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(Settled(handle, 1));
  int64_t first = Stats(handle).rendered_frames;
  QueueRenderUpdate(handle);
  CHECK(WaitFor([handle, first] {
    return Stats(handle).rendered_frames == first + 1;
  }));
  uint64_t newer = static_cast<uint64_t>(first + 1);
  CHECK(DeliverImage(newer));
  auto ready = ReadyEvents();
  CHECK(ready.size() == 1);
  CHECK(!ready.empty() && ready[0].frame_id == static_cast<int64_t>(newer));
  // The image of a replaced frame is refused without an error.
  CHECK(!DeliverImage(newer - 1));
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).empty());
  // Frames keep rendering into free slots while Dart chooses none.
  for (uint64_t frame = newer + 1; frame <= newer + 10; ++frame) {
    QueueRenderUpdate(handle);
    CHECK(WaitFor([handle, frame] {
      return Stats(handle).rendered_frames == static_cast<int64_t>(frame);
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
}

// Design D133: Dart chooses every frame, and each chosen image is released
// after three later choices.
void SurfaceSlotIsFreedAfterThreeLaterChoices() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(Settled(handle, 1));
  int64_t base = Stats(handle).rendered_frames;
  for (int64_t frame = 1; frame <= base; ++frame) DeliverImage(frame);
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  std::vector<uint64_t> closed_before;
  {
    std::lock_guard lock(last_target->mutex);
    closed_before = last_target->closed;
  }
  for (int64_t i = 1; i <= 8; ++i) {
    int64_t frame = base + i;
    QueueRenderUpdate(handle);
    CHECK(WaitFor([handle, frame] {
      return Stats(handle).rendered_frames == frame;
    }));
    CHECK(DeliverImage(frame));
    map_texture_frame chosen{};
    CHECK(SelectNewest(handle, &chosen) == MAP_TEXTURE_OK);
    CHECK(chosen.frame_id == frame);
    {
      // Choosing frame `frame` releases the image of the frame chosen three
      // choices before it.
      std::lock_guard lock(last_target->mutex);
      auto& closed = last_target->closed;
      if (i >= 3) {
        CHECK(!closed.empty() &&
              closed.back() == static_cast<uint64_t>(frame - 3));
      }
    }
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
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames >= 1; }));
  CHECK(!DeliverImage(1000));
  CHECK(!DeliverImage(1001));
  auto errors = EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR);
  CHECK(errors.size() == 1);
  CHECK(!errors.empty() &&
        errors[0].message == "received an image of unknown frame 1000");
  map_texture_dispose(handle);
}

// A target task, which replaces or removes the surface, frees the slot of a
// frame whose image hasn't arrived, so that the map renders again.
void SurfaceTargetTaskFreesQueuedFrame() {
  map_texture::SetRenderAheadModeForTesting(map_texture::RenderAheadMode::kNever);
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;
  auto owner = last_owner.lock();
  owner->RunTargetTask([](mln_render_session, const TargetSize&) {}, true);
  QueueRenderUpdate(handle);
  CHECK(WaitFor([handle, rendered] {
    return Stats(handle).rendered_frames > rendered;
  }));
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
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;
  CHECK(DeliverImage(rendered));
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  last_owner.lock()->ResetSlots();
  {
    std::lock_guard lock(last_target->mutex);
    CHECK(last_target->images.empty());
    CHECK(!last_target->closed.empty() &&
          last_target->closed.back() == static_cast<uint64_t>(rendered));
  }
  CHECK(SelectNewest(handle) == MAP_TEXTURE_NOT_SELECTED);
  map_texture_dispose(handle);
}

void IdleMapRendersNothing() {
  int64_t handle = CreateMap();
  SurfaceDart dart(handle);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return FrameEvents().size() >= 1; }));
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;
  Sleep(10'000);
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames == rendered);
  map_texture_dispose(handle);
}

void NoRenderWhilePaused() {
  int64_t handle = CreateMap();
  SurfaceDart dart(handle);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;
  map_texture_set_paused_for_testing(1);
  map_texture_set_camera(handle, 0, 0, 3, 0, 0, 1);
  Sleep(300);
  CHECK(Stats(handle).rendered_frames == rendered);
  CHECK(Stats(handle).paused_renders > 0);
  map_texture_set_paused_for_testing(0);
  CHECK(WaitFor([] {
    auto frames = FrameEvents();
    return !frames.empty() && frames.back().zoom == 3;
  }));
  map_texture_dispose(handle);
}

void FrameReportsLatestCameraSequenceNumber() {
  int64_t handle = CreateMap();
  SurfaceDart dart(handle);
  map_texture_set_camera(handle, 0, 0, 1, 0, 0, 1);
  map_texture_set_camera(handle, 0, 0, 2, 0, 0, 2);
  map_texture_set_camera(handle, 0, 0, 3, 0, 0, 3);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return FrameEvents().size() >= 1; }));
  CHECK(Settled(handle, 1));
  CHECK(FrameEvents().back().seq == 3);
  CHECK(FrameEvents().back().zoom == 3);
  // A frame after a style change, without a camera change, reports the last
  // applied number.
  size_t frames = FrameEvents().size();
  QueueRenderUpdate(handle);
  CHECK(WaitFor([frames] { return FrameEvents().size() > frames; }));
  CHECK(FrameEvents().back().seq == 3);
  map_texture_dispose(handle);
}

// The view that a rendered query reads is the camera and logical size of the
// last frame rendered.
void LastRenderedViewIsNewestFrame() {
  int64_t handle = CreateMap();
  auto owner = last_owner.lock();
  SurfaceDart dart(handle);
  CHECK(!owner->LastRenderedViewForTesting().has_value());
  map_texture_resize(handle, 120, 90, 2.0);
  const double cameras[][4] = {
      {48.2, 16.37, 12, 0}, {48.21, 16.4, 12.5, 15}, {-33.9, 151.2, 9.75, -40}};
  int64_t seq = 0;
  for (const auto& c : cameras) {
    map_texture_set_camera(handle, c[0], c[1], c[2], c[3], 0, ++seq);
    CHECK(WaitFor([seq] {
      auto ready = ReadyEvents();
      return !ready.empty() && ready.back().seq == seq;
    }));
  }
  CHECK(Settled(handle, 1));
  auto view = owner->LastRenderedViewForTesting();
  CHECK(view.has_value());
  if (view) {
    CHECK(std::abs(view->camera.latitude - -33.9) < 1e-9);
    CHECK(std::abs(view->camera.longitude - 151.2) < 1e-9);
    CHECK(view->camera.zoom == ReadyEvents().back().zoom);
    CHECK(std::abs(view->camera.bearing - -40) < 1e-9);
    CHECK(view->width == 120);
    CHECK(view->height == 90);
  }
  map_texture_dispose(handle);
}

// A camera set with a pitch is rendered with it, and the frame-ready event, the
// chosen frame and the last rendered view report it.
void PitchIsSetAndReported() {
  int64_t handle = CreateMap();
  auto owner = last_owner.lock();
  SurfaceDart dart(handle);
  map_texture_resize(handle, 120, 90, 2.0);
  map_texture_set_camera(handle, 48.2, 16.37, 12, 20, 45, 1);
  CHECK(WaitFor([] {
    auto ready = ReadyEvents();
    return !ready.empty() && ready.back().seq == 1;
  }));
  CHECK(std::abs(ReadyEvents().back().pitch - 45) < 1e-9);
  CHECK(Settled(handle, 1));
  auto view = owner->LastRenderedViewForTesting();
  CHECK(view.has_value());
  if (view) CHECK(std::abs(view->camera.pitch - 45) < 1e-9);
  map_texture_dispose(handle);
}

// The map renders a pitch up to the maximum pitch given to map_texture_create,
// and the maximum pitch in place of a larger one.
void MaxPitchLimitsThePitch() {
  for (double max_pitch : {85.0, 60.0}) {
    int64_t handle = CreateMap(true, max_pitch);
    auto owner = last_owner.lock();
    SurfaceDart dart(handle);
    map_texture_resize(handle, 120, 90, 2.0);
    map_texture_set_camera(handle, 48.2, 16.37, 12, 20, 85, 1);
    CHECK(Settled(handle, 1));
    auto view = owner->LastRenderedViewForTesting();
    CHECK(view.has_value());
    if (view) CHECK(std::abs(view->camera.pitch - max_pitch) < 1e-9);
    map_texture_dispose(handle);
  }
}

// An invalid maximum pitch fails the creation.
void InvalidMaxPitchFailsCreation() {
  for (double max_pitch : {-1.0, std::numeric_limits<double>::quiet_NaN(),
                           std::numeric_limits<double>::infinity()}) {
    std::string error;
    CHECK(CreateMapWithRules({}, {}, &error, kEngine, max_pitch) ==
          MAP_TEXTURE_ERROR_CREATE_FAILED);
    CHECK(error == "invalid maximum pitch");
  }
}

// A style with one GeoJSON line along the meridian from 20 degrees south to
// 20 degrees north, 1 logical pixel wide, so that the map renders it without
// network access. The source ID, `lines "a\b"`, needs escaping in JSON.
constexpr char kLineStyle[] = R"({"version": 8,
  "sources": {"lines \"a\\b\"": {"type": "geojson", "data": {
    "type": "Feature", "id": 1, "properties": {"class": "primary"},
    "geometry": {"type": "LineString", "coordinates": [[0, -20], [0, 20]]}}}},
  "layers": [{"id": "line", "type": "line", "source": "lines \"a\\b\"",
    "paint": {"line-width": 1, "line-color": "#ff0000"}}]})";

constexpr double kQueryZoom = 4;

// The corners of the square of side 2 * `half` logical pixels at zoom
// kQueryZoom, centered `offset` logical pixels east of the line at the
// equator.
std::array<double, 8> QuerySquare(double half, double offset = 0) {
  double unit = 1 / map_texture::WorldSize(kQueryZoom);
  map_texture::WorldPoint c = map_texture::Mercator(0, 0);
  double x = c.x + offset * unit;
  double h = half * unit;
  return {x - h, c.y - h, x + h, c.y - h, x + h, c.y + h, x - h, c.y + h};
}

std::atomic<int64_t> next_request_id{0};

// Queries and waits for the result event.
Event Query(int64_t handle, const std::array<double, 8>& corners,
            const std::vector<const char*>* layer_ids = nullptr,
            const char* filter = nullptr) {
  int64_t id = ++next_request_id;
  CHECK(map_texture_query_rendered_features(
            handle, id, corners.data(),
            layer_ids == nullptr ? nullptr : layer_ids->data(),
            layer_ids == nullptr ? 0 : static_cast<int32_t>(layer_ids->size()),
            filter) == MAP_TEXTURE_OK);
  Event result{};
  result.status = -1;
  CHECK(WaitFor([&] {
    for (const Event& event : EventsOfType(MAP_TEXTURE_EVENT_QUERY_RESULT)) {
      if (event.request_id == id) {
        result = event;
        return true;
      }
    }
    return false;
  }));
  return result;
}

bool FindsLine(const Event& result) {
  return result.status == 0 &&
         result.message.find(R"("id":1)") != std::string::npos;
}

bool WaitForStyleLoaded() {
  return WaitFor(
      [] { return !EventsOfType(MAP_TEXTURE_EVENT_STYLE_LOADED).empty(); });
}

// A surface map at kQueryZoom that shows the line.
int64_t CreateLineMap() {
  int64_t handle = CreateMap(false);
  map_texture_load_style_json(handle, kLineStyle);
  map_texture_resize(handle, 120, 90, 2.0);
  map_texture_set_camera(handle, 0, 0, kQueryZoom, 0, 0, 1);
  return handle;
}

void QueryBeforeFirstRenderIsEmpty() {
  int64_t handle = CreateMap();
  Event result = Query(handle, QuerySquare(2));
  CHECK(result.status == 0);
  CHECK(result.message == "[]");
  map_texture_dispose(handle);
}

void QueryFindsLineAtRest() {
  int64_t handle = CreateLineMap();
  SurfaceDart dart(handle);
  CHECK(WaitForStyleLoaded());
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;

  Event hit = Query(handle, QuerySquare(2));
  CHECK(FindsLine(hit));
  CHECK(hit.message.find(R"("source":"lines \"a\\b\"")") != std::string::npos);
  CHECK(hit.message.find(R"("sourceLayer":null)") != std::string::npos);
  CHECK(hit.message.find(R"("class":"primary")") != std::string::npos);
  CHECK(Query(handle, QuerySquare(2, 6)).message == "[]");

  std::vector<const char*> line = {"line"};
  std::vector<const char*> missing = {"missing"};
  CHECK(FindsLine(Query(handle, QuerySquare(2), &line)));
  CHECK(Query(handle, QuerySquare(2), &missing).message == "[]");
  CHECK(FindsLine(Query(handle, QuerySquare(2), nullptr,
                        R"(["==", ["get", "class"], "primary"])")));
  CHECK(Query(handle, QuerySquare(2), nullptr,
              R"(["==", ["get", "class"], "minor"])")
            .message == "[]");

  // Queries at rest end the waiting demand, but render no frame.
  Sleep(300);
  CHECK(Stats(handle).rendered_frames == rendered);
  map_texture_dispose(handle);
}

// The camera jumps 45 logical pixels between renders, so a query converted
// with a camera other than that of the frame it reads misses the line.
void QueryReadsLastRenderedFrameWhileCameraMoves() {
  int64_t handle = CreateLineMap();
  SurfaceDart dart(handle);
  CHECK(WaitForStyleLoaded());
  CHECK(Settled(handle, 1));
  int misses = 0;
  int false_hits = 0;
  for (int i = 0; i < 40; ++i) {
    map_texture_set_camera(handle, 0, i % 2 == 0 ? -1 : 1, kQueryZoom, 0, 0,
                           2 + i);
    if (i % 4 == 0) Sleep(5);
    if (!FindsLine(Query(handle, QuerySquare(2)))) ++misses;
    if (Query(handle, QuerySquare(2, 6)).message != "[]") ++false_hits;
  }
  CHECK(misses == 0);
  CHECK(false_hits == 0);
  map_texture_dispose(handle);
}

void InvalidFilterFailsQuery() {
  int64_t handle = CreateLineMap();
  SurfaceDart dart(handle);
  CHECK(WaitForStyleLoaded());
  CHECK(Settled(handle, 1));
  Event result = Query(handle, QuerySquare(2), nullptr, R"(["no-such-operator"])");
  CHECK(result.status != 0);
  CHECK(!result.message.empty());
  map_texture_dispose(handle);
}

constexpr char kLineSource[] = "lines \"a\\b\"";

bool HasState(const Event& result, const std::string& state) {
  return result.status == 0 &&
         result.message.find(R"("state":)" + state) != std::string::npos;
}

void FeatureStateIsReturnedByQuery() {
  int64_t handle = CreateLineMap();
  SurfaceDart dart(handle);
  CHECK(WaitForStyleLoaded());
  CHECK(Settled(handle, 1));
  CHECK(HasState(Query(handle, QuerySquare(2)), "{}"));

  // A query right after the set returns the new state: it waits for the
  // frame that includes the set.
  CHECK(map_texture_set_feature_state(handle, kLineSource, nullptr, "1",
                                      R"({"selected":true})") == MAP_TEXTURE_OK);
  CHECK(HasState(Query(handle, QuerySquare(2)), R"({"selected":true})"));

  CHECK(map_texture_remove_feature_state(handle, kLineSource, nullptr, "1",
                                         "selected") == MAP_TEXTURE_OK);
  CHECK(HasState(Query(handle, QuerySquare(2)), "{}"));

  map_texture_set_feature_state(handle, kLineSource, nullptr, "1",
                                R"({"selected":true})");
  CHECK(HasState(Query(handle, QuerySquare(2)), R"({"selected":true})"));
  map_texture_remove_feature_state(handle, kLineSource, nullptr, nullptr,
                                   nullptr);
  CHECK(HasState(Query(handle, QuerySquare(2)), "{}"));

  // A failed command doesn't hold back later queries.
  map_texture_set_feature_state(handle, kLineSource, nullptr, "1", "not json");
  CHECK(Query(handle, QuerySquare(2)).status == 0);
  map_texture_dispose(handle);
}

void FeatureStateFailureIsReported() {
  int64_t handle = CreateLineMap();
  CHECK(map_texture_set_feature_state(handle, kLineSource, nullptr, "1",
                                      "not json") == MAP_TEXTURE_OK);
  CHECK(WaitFor([] {
    for (const Event& e : EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR)) {
      if (e.message.find("mln_map_set_feature_state") != std::string::npos) {
        return true;
      }
    }
    return false;
  }));
  CHECK(map_texture_set_feature_state(handle, kLineSource, nullptr, nullptr,
                                      "{}") ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(map_texture_set_feature_state(handle, "", nullptr, "1", "{}") ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(map_texture_remove_feature_state(handle, kLineSource, nullptr, nullptr,
                                         "selected") ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  map_texture_dispose(handle);
}

void QueryResultsArriveInRequestOrder() {
  int64_t handle = CreateLineMap();
  SurfaceDart dart(handle);
  CHECK(WaitForStyleLoaded());
  CHECK(Settled(handle, 1));
  auto corners = QuerySquare(2);
  std::vector<int64_t> ids;
  for (int i = 0; i < 5; ++i) {
    ids.push_back(++next_request_id);
    map_texture_query_rendered_features(handle, ids.back(), corners.data(),
                                        nullptr, 0, nullptr);
  }
  CHECK(WaitFor([] {
    return EventsOfType(MAP_TEXTURE_EVENT_QUERY_RESULT).size() >= 5;
  }));
  auto results = EventsOfType(MAP_TEXTURE_EVENT_QUERY_RESULT);
  CHECK(results.size() == 5);
  for (size_t i = 0; i < results.size() && i < ids.size(); ++i) {
    CHECK(results[i].request_id == ids[i]);
  }
  map_texture_dispose(handle);
}

void InvalidQueryArgumentsAreRejected() {
  int64_t handle = CreateMap();
  auto corners = QuerySquare(2);
  CHECK(map_texture_query_rendered_features(handle, 1, nullptr, nullptr, 0,
                                            nullptr) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(map_texture_query_rendered_features(handle, 1, corners.data(), nullptr,
                                            1, nullptr) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  corners[3] = std::nan("");
  CHECK(map_texture_query_rendered_features(handle, 1, corners.data(), nullptr,
                                            0, nullptr) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  map_texture_dispose(handle);
  CHECK(map_texture_query_rendered_features(handle, 1, QuerySquare(2).data(),
                                            nullptr, 0, nullptr) ==
        MAP_TEXTURE_ERROR_DISPOSED);
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

// Waits until the buffer map has published `ready` frames and publishes no
// more for 200 ms, choosing none.
bool ReadySettled(size_t ready) {
  if (!WaitFor([ready] { return ReadyEvents().size() >= ready; })) {
    return false;
  }
  size_t count = 0;
  while (count != ReadyEvents().size()) {
    count = ReadyEvents().size();
    Sleep(200);
  }
  return true;
}

void ReadyEventPrecedesDisplayedEvent() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_set_camera(handle, 0, 0, 4, 0, 0, 7);
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(ReadySettled(1));
  // Not displayed until Dart chooses the frame.
  CHECK(owner->Present(0) == nullptr);
  CHECK(FrameEvents().empty());
  auto ready = ReadyEvents().back();
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
  CHECK(ReadySettled(1));
  auto shown = ReadyEvents().back();
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  void* shown_buffer = reinterpret_cast<void*>(intptr_t{shown.slot + 1});
  CHECK(owner->Present(shown.slot) == shown_buffer);
  // Rendered ahead, the newer frame replaces the one before it.
  size_t ready = ReadyEvents().size();
  QueueRenderUpdate(handle);
  CHECK(WaitFor([ready] { return ReadyEvents().size() >= ready + 1; }));
  QueueRenderUpdate(handle);
  CHECK(WaitFor([ready] { return ReadyEvents().size() >= ready + 2; }));
  CHECK(ReadySettled(ready + 2));
  auto newest = ReadyEvents().back();
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
  CHECK(ReadySettled(1));
  int64_t rendered = Stats(handle).rendered_frames;
  QueueRenderUpdate(handle);
  CHECK(WaitFor([handle] { return Stats(handle).waits_for_display > 0; }));
  Sleep(200);
  CHECK(Stats(handle).rendered_frames == rendered);
  CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
  CHECK(WaitFor([handle, rendered] {
    return Stats(handle).rendered_frames == rendered + 1;
  }));
  owner.reset();
  map_texture_dispose(handle);
}

void MapDoesNotRenderIntoHeldSlot() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(ReadySettled(1));
  std::vector<int> chosen_order;
  int previous = -1;
  for (int i = 0; i < 40; ++i) {
    size_t ready = ReadyEvents().size();
    if (i > 0) {
      CHECK(WaitFor([ready] { return ReadyEvents().size() > ready; }));
    }
    auto newest = ReadyEvents().back();
    Choose(handle, newest);
    chosen_order.push_back(newest.slot);
    // The next frame renders while Flutter presents the frame chosen
    // before.
    QueueRenderUpdate(handle);
    if (previous >= 0) PresentSlot(*owner, previous, chosen_order);
    previous = newest.slot;
  }
  {
    std::lock_guard lock(last_buffer_target->mutex);
    CHECK(last_buffer_target->renders_into_held == 0);
  }
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames >= 40);
  CHECK(stats.skipped_renders == 0);
  CHECK(stats.max_slots_in_use <= 4);
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).empty());
  owner.reset();
  map_texture_dispose(handle);
}

void IdleBufferMapRendersNothing() {
  int64_t handle = CreateBufferMap();
  auto owner = last_owner.lock();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(ReadySettled(1));
  auto ready = ReadyEvents().back();
  Choose(handle, ready);
  owner->Present(ready.slot);
  CHECK(Settled(handle, 1));
  int64_t rendered = Stats(handle).rendered_frames;
  Sleep(10'000);
  CHECK(Stats(handle).rendered_frames == rendered);
  owner.reset();
  map_texture_dispose(handle);
}

void AllSlotsHeldWithoutPresent() {
  int64_t handle = CreateBufferMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(ReadySettled(1));
  // Dart chooses each frame, and Flutter never presents.
  for (int i = 0; i < 4; ++i) {
    size_t ready = ReadyEvents().size();
    CHECK(SelectNewest(handle) == MAP_TEXTURE_OK);
    QueueRenderUpdate(handle);
    if (i < 3) CHECK(WaitFor([ready] { return ReadyEvents().size() > ready; }));
  }
  CHECK(WaitFor([handle] { return Stats(handle).skipped_renders > 0; }));
  auto stats = Stats(handle);
  CHECK(stats.max_slots_in_use == 4);
  // A present frees the slots chosen before the presented one.
  size_t ready = ReadyEvents().size();
  auto owner = last_owner.lock();
  owner->Present(ReadyEvents().back().slot);
  CHECK(WaitFor([ready] { return ReadyEvents().size() > ready; }));
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
  CHECK(map_texture_set_camera(handle, 0, 0, 0, 0, 0, 1) ==
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
    "mln_runtime_set_maximum_ambient_cache_size";

// The names of the calls recorded since the last map was created.
std::vector<std::string> CallNames() {
  std::vector<std::string> names;
  for (const auto& call : ffi_wrappers::Calls()) names.push_back(call.name);
  return names;
}

// The sizes passed to mln_runtime_set_maximum_ambient_cache_size since the
// last map was created.
std::vector<uint64_t> CacheSizes() {
  std::vector<uint64_t> sizes;
  for (const auto& call : ffi_wrappers::Calls()) {
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
  int64_t handle = CreateMap(/*style=*/false);
  map_texture_load_style_url(handle, "https://example.com/style.json");
  CHECK(WaitFor(StyleLoaded));
  CHECK(CacheSizes().empty());
  map_texture_dispose(handle);
}

void CacheSizeIsSetBeforeMapAndStyle() {
  CHECK(map_texture_set_maximum_cache_size(200 << 20) == MAP_TEXTURE_OK);
  int64_t handle = CreateMap(/*style=*/false);
  map_texture_load_style_url(handle, "https://example.com/style.json");
  CHECK(WaitFor(StyleLoaded));
  CHECK((CallNames() == std::vector<std::string>{
                            "mln_runtime_create", kSetCacheSize,
                            "mln_runtime_create_map",
                            "mln_map_set_style_url"}));
  CHECK((CacheSizes() == std::vector<uint64_t>{200 << 20}));
  map_texture_dispose(handle);
}

void CacheSizeAppliesToMapsCreatedAfterIt() {
  CHECK(map_texture_set_maximum_cache_size(200 << 20) == MAP_TEXTURE_OK);
  int64_t first = CreateMap(/*style=*/false);
  CHECK(map_texture_set_maximum_cache_size(10 << 20) == MAP_TEXTURE_OK);
  map_texture_load_style_url(first, "https://example.com/style.json");
  CHECK(WaitFor(StyleLoaded));
  CHECK((CacheSizes() == std::vector<uint64_t>{200 << 20}));
  int64_t second = CreateMap(/*style=*/false);
  CHECK((CacheSizes() == std::vector<uint64_t>{10 << 20}));
  map_texture_dispose(first);
  map_texture_dispose(second);
}

void NegativeCacheSizeIsRejected() {
  CHECK(map_texture_set_maximum_cache_size(10 << 20) == MAP_TEXTURE_OK);
  CHECK(map_texture_set_maximum_cache_size(-1) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  int64_t handle = CreateMap(/*style=*/false);
  CHECK((CacheSizes() == std::vector<uint64_t>{10 << 20}));
  map_texture_dispose(handle);
}

void ZeroCacheSizeIsApplied() {
  CHECK(map_texture_set_maximum_cache_size(0) == MAP_TEXTURE_OK);
  int64_t handle = CreateMap(/*style=*/false);
  CHECK((CacheSizes() == std::vector<uint64_t>{0}));
  map_texture_dispose(handle);
}

void CacheSizeFailureIsReportedAndMapRenders() {
  CHECK(map_texture_set_maximum_cache_size(10 << 20) == MAP_TEXTURE_OK);
  ffi_wrappers::Reset();
  ffi_wrappers::SetMaximumCacheSizeStatus(MLN_STATUS_NATIVE_ERROR);
  {
    std::lock_guard lock(events_mutex);
    events.clear();
  }
  int64_t handle = map_texture_create(kEngine, 2.0, 1, 85.0, OnEvent, nullptr,
                                      nullptr, 0, nullptr);
  ffi_wrappers::SetMaximumCacheSizeStatus(MLN_STATUS_OK);
  CHECK(handle > 0);
  CHECK(EventsOfType(MAP_TEXTURE_EVENT_RENDER_ERROR).size() == 1);
  CHECK((CallNames() == std::vector<std::string>{
                            "mln_runtime_create", kSetCacheSize,
                            "mln_runtime_create_map"}));
  map_texture_load_style_json(handle, NextStyle().c_str());
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([handle] { return Stats(handle).rendered_frames >= 1; }));
  map_texture_dispose(handle);
}

// CallNames() without the process-wide cache size call.
std::vector<std::string> InitCallNames() {
  std::vector<std::string> names;
  for (const auto& name : CallNames()) {
    if (name != kSetCacheSize) names.push_back(name);
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
  auto rules = ffi_wrappers::HeaderRules();
  CHECK(rules.size() == 2);
  if (rules.size() == 2) {
    for (const auto& rule : rules) {
      CHECK(rule.kinds == MLN_RESOURCE_KIND_MASK_ALL);
      CHECK(rule.flags == MLN_URL_MATCH_GLOB);
    }
    CHECK(rules[0].url == "https://tiles.example.com/v2/**");
    CHECK((rules[0].headers == std::vector<ffi_wrappers::Header>{
                                   {"X-Access-Key", "k2"}, {"X-Other", "o"}}));
    CHECK(rules[1].url == "https://tiles.example.com/**");
    CHECK((rules[1].headers ==
           std::vector<ffi_wrappers::Header>{{"X-Access-Key", "k1"}}));
  }
  CHECK((InitCallNames() == std::vector<std::string>{
                                "mln_runtime_create",
                                "mln_runtime_set_http_header_transform",
                                "mln_runtime_create_map"}));
  map_texture_dispose(handle);
}

void RuleWithoutHeadersIsRegistered() {
  int64_t handle = CreateMapWithRules({"https://a.example.com/**"}, {0});
  CHECK(handle > 0);
  auto rules = ffi_wrappers::HeaderRules();
  CHECK(rules.size() == 1 && rules[0].headers.empty());
  map_texture_dispose(handle);
}

void NoHeaderTransformWithoutRules() {
  int64_t handle = CreateMap(/*style=*/false);
  CHECK(ffi_wrappers::HeaderRules().empty());
  CHECK((InitCallNames() == std::vector<std::string>{
                                "mln_runtime_create",
                                "mln_runtime_create_map"}));
  map_texture_dispose(handle);
}

void EmptyAssetPathKeepsDefault() {
  int64_t handle = CreateMap(/*style=*/false);
  CHECK(ffi_wrappers::LastAssetPath() == "<null>");
  map_texture_dispose(handle);
}

// Under #760 the runtime validates the rules when the map thread registers
// them, so the creation fails with the runtime's message.
void RejectedHeaderFailsCreate() {
  std::string error;
  int64_t result = CreateMapWithRules(
      {"https://a.example.com/**", "X-Ok", "1", "Host", "secret"}, {2},
      &error);
  CHECK(result == MAP_TEXTURE_ERROR_CREATE_FAILED);
  CHECK(error.find("Host") != std::string::npos);
  CHECK(error.find("secret") == std::string::npos);
}

void InvalidRuleArraysFailCreate() {
  std::string error;
  ffi_wrappers::Reset();
  char* message = nullptr;
  CHECK(map_texture_create(kEngine, 2.0, 1, 85.0, OnEvent, nullptr, nullptr, 1,
                           &message) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(message != nullptr);
  map_texture_string_free(message);
  CHECK(CreateMapWithRules({"https://a.example.com/**"}, {-1}, &error) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(!error.empty());
  // A null out_error is allowed.
  CHECK(map_texture_create(kEngine, 2.0, 1, 85.0, nullptr, nullptr, nullptr, 0,
                           nullptr) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(ffi_wrappers::Calls().empty());
}

void FailedInitReportsMessage() {
  ffi_wrappers::Reset();
  ffi_wrappers::SetRuntimeCreateResult(MLN_STATUS_NATIVE_ERROR, "no runtime");
  {
    std::lock_guard lock(events_mutex);
    events.clear();
  }
  char* message = nullptr;
  int64_t result = map_texture_create(kEngine, 2.0, 1, 85.0, OnEvent, nullptr,
                                      nullptr, 0, &message);
  ffi_wrappers::SetRuntimeCreateResult(MLN_STATUS_OK, "");
  std::string error = message == nullptr ? "" : message;
  map_texture_string_free(message);
  CHECK(result == MAP_TEXTURE_ERROR_CREATE_FAILED);
  CHECK(error.find("mln_runtime_create") != std::string::npos);
  CHECK(error.find("no runtime") != std::string::npos);
}

constexpr const char* kGlyphFailure =
    "Failed to load glyph range 0-255 for font stack Noto Sans Regular:( "
    "HTTP status code 404)";

// Logs `records` on the map thread of the last map, as MapLibre's renderer
// does with a caller-graphics-thread driver.
void LogOnMapThread(std::vector<ffi_wrappers::LogRecord> records) {
  auto owner = last_owner.lock();
  owner->RunTargetTask(
      [records = std::move(records)](mln_render_session, const TargetSize&) {
        for (const auto& record : records) CHECK(ffi_wrappers::Log(record));
      },
      /*wait=*/true);
}

void GlyphFailureIsReportedAsLoadFailure() {
  int64_t handle = CreateMap(/*style=*/false);
  // Once for the process, however many maps are created.
  CHECK(ffi_wrappers::LogCallbackRegistrations() == 1);
  LogOnMapThread({{.message = kGlyphFailure}});
  CHECK(WaitFor([] { return !LoadFailures().empty(); }));
  auto reported = LoadFailures();
  CHECK(reported.size() == 1);
  CHECK(!reported.empty() && reported[0] == kGlyphFailure);
  map_texture_dispose(handle);
}

void OtherLogRecordsAreNotReported() {
  int64_t handle = CreateMap(/*style=*/false);
  LogOnMapThread({
      {.message = "Failed to load tile 1/0/0"},
      {.severity = MLN_LOG_SEVERITY_WARNING, .message = kGlyphFailure},
      {.event = MLN_LOG_EVENT_GLYPH, .message = kGlyphFailure},
  });
  // Logged off the map thread, so it belongs to no map.
  CHECK(ffi_wrappers::Log({.message = kGlyphFailure}));
  // The last record shows that the map thread has passed the others on.
  LogOnMapThread({{.message = std::string(kGlyphFailure) + " last"}});
  CHECK(WaitFor([] { return !LoadFailures().empty(); }));
  Sleep(50);
  auto reported = LoadFailures();
  CHECK(reported.size() == 1);
  CHECK(!reported.empty() &&
        reported[0] == std::string(kGlyphFailure) + " last");
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
  int64_t first = CreateMap(/*style=*/false);
  // Without the reset of CreateMapWithRules, which the live map uses.
  int64_t second =
      map_texture_create(kEngine, 2.0, 1, 85.0, OnEvent, nullptr, nullptr, 0, nullptr);
  int64_t other = map_texture_create(kOtherEngine, 2.0, 1, 85.0, OnEvent, nullptr,
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
  CHECK(ffi_wrappers::Calls().empty());
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

void RunInPlatformScope(const std::function<void()>& work) {
  @autoreleasepool {
    work();
  }
}

}  // namespace map_texture

int main(int argc, char** argv) {
  struct Test {
    const char* name;
    void (*run)();
  };
  const Test tests[] = {
      {"SurfaceFrameIsReportedWithoutDisplayTime",
       SurfaceFrameIsReportedWithoutDisplayTime},
      {"NoRenderWithoutSurface", NoRenderWithoutSurface},
      {"TaskWaitEndsAtDispose", TaskWaitEndsAtDispose},
      {"RendersArePacedByRefreshInterval", RendersArePacedByRefreshInterval},
      {"SurfaceFrameIsReadyWhenItsImageArrives",
       SurfaceFrameIsReadyWhenItsImageArrives},
      {"SurfaceImageBeforeRenderReturns", SurfaceImageBeforeRenderReturns},
      {"SurfaceFrameWithoutImageIsFreedByNewerFrame",
       SurfaceFrameWithoutImageIsFreedByNewerFrame},
      {"SurfaceSlotIsFreedAfterThreeLaterChoices",
       SurfaceSlotIsFreedAfterThreeLaterChoices},
      {"SurfaceImageOfUnknownFrameIsReportedOnce",
       SurfaceImageOfUnknownFrameIsReportedOnce},
      {"SurfaceTargetTaskFreesQueuedFrame", SurfaceTargetTaskFreesQueuedFrame},
      {"SurfaceResetSlotsReleasesImages", SurfaceResetSlotsReleasesImages},
      {"IdleMapRendersNothing", IdleMapRendersNothing},
      {"NoRenderWhilePaused", NoRenderWhilePaused},
      {"FrameReportsLatestCameraSequenceNumber",
       FrameReportsLatestCameraSequenceNumber},
      {"LastRenderedViewIsNewestFrame", LastRenderedViewIsNewestFrame},
      {"PitchIsSetAndReported", PitchIsSetAndReported},
      {"MaxPitchLimitsThePitch", MaxPitchLimitsThePitch},
      {"InvalidMaxPitchFailsCreation", InvalidMaxPitchFailsCreation},
      {"QueryBeforeFirstRenderIsEmpty", QueryBeforeFirstRenderIsEmpty},
      {"QueryFindsLineAtRest", QueryFindsLineAtRest},
      {"QueryReadsLastRenderedFrameWhileCameraMoves",
       QueryReadsLastRenderedFrameWhileCameraMoves},
      {"InvalidFilterFailsQuery", InvalidFilterFailsQuery},
      {"QueryResultsArriveInRequestOrder", QueryResultsArriveInRequestOrder},
      {"FeatureStateIsReturnedByQuery", FeatureStateIsReturnedByQuery},
      {"FeatureStateFailureIsReported", FeatureStateFailureIsReported},
      {"InvalidQueryArgumentsAreRejected", InvalidQueryArgumentsAreRejected},
      {"ReadyEventPrecedesDisplayedEvent", ReadyEventPrecedesDisplayedEvent},
      {"NewestFrameIsChosenAfterReplacement",
       NewestFrameIsChosenAfterReplacement},
      {"RenderWaitingForChoiceStartsAfterChoice",
       RenderWaitingForChoiceStartsAfterChoice},
      {"MapDoesNotRenderIntoHeldSlot", MapDoesNotRenderIntoHeldSlot},
      {"IdleBufferMapRendersNothing", IdleBufferMapRendersNothing},
      {"AllSlotsHeldWithoutPresent", AllSlotsHeldWithoutPresent},
      {"SelectAfterDisposeReportsDisposed", SelectAfterDisposeReportsDisposed},
      {"SurfaceMapHasSixSlotsWithOneTexture",
       SurfaceMapHasSixSlotsWithOneTexture},
      {"NoCacheSizeWithoutValue", NoCacheSizeWithoutValue},
      {"CacheSizeIsSetBeforeMapAndStyle", CacheSizeIsSetBeforeMapAndStyle},
      {"CacheSizeAppliesToMapsCreatedAfterIt",
       CacheSizeAppliesToMapsCreatedAfterIt},
      {"NegativeCacheSizeIsRejected", NegativeCacheSizeIsRejected},
      {"ZeroCacheSizeIsApplied", ZeroCacheSizeIsApplied},
      {"CacheSizeFailureIsReportedAndMapRenders",
       CacheSizeFailureIsReportedAndMapRenders},
      {"HeaderRulesAreCopiedAndRegistered", HeaderRulesAreCopiedAndRegistered},
      {"RuleWithoutHeadersIsRegistered", RuleWithoutHeadersIsRegistered},
      {"NoHeaderTransformWithoutRules", NoHeaderTransformWithoutRules},
      {"EmptyAssetPathKeepsDefault", EmptyAssetPathKeepsDefault},
      {"RejectedHeaderFailsCreate", RejectedHeaderFailsCreate},
      {"InvalidRuleArraysFailCreate", InvalidRuleArraysFailCreate},
      {"FailedInitReportsMessage", FailedInitReportsMessage},
      {"GlyphFailureIsReportedAsLoadFailure",
       GlyphFailureIsReportedAsLoadFailure},
      {"OtherLogRecordsAreNotReported", OtherLogRecordsAreNotReported},
      {"MapKeepsItsEngineToken", MapKeepsItsEngineToken},
      {"DisposeEngineMapsDisposesOnlyThatEngine",
       DisposeEngineMapsDisposesOnlyThatEngine},
      {"UnknownEngineFailsCreate", UnknownEngineFailsCreate},
  };
  // A name as argument runs only the tests whose names contain it.
  const char* only = nullptr;
  if (argc > 1) only = argv[1];
  for (const Test& test : tests) {
    if (only != nullptr && std::strstr(test.name, only) == nullptr) continue;
    int before = failures;
    @autoreleasepool {
      test.run();
    }
    std::printf("%s %s\n", failures == before ? "PASS" : "FAIL", test.name);
    std::fflush(stdout);
  }
  if (failures > 0) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("map texture tests passed\n");
  return 0;
}
