// Tests of MapTexture with a surface render target (design D52), its pacing by
// display refresh interval (D53), the maximum size of the tile cache
// (D61-D63), and the HTTP header rules (D81, D82), on the fake FFI in
// fake_mln.cpp.
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "fake_mln.h"
#include "map_texture.h"
#include "map_texture_api.h"
#include "render_target.h"

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

class FakeSurfaceTarget : public SurfaceRenderTarget {
 public:
  int64_t texture_id() const override { return 42; }

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
};

// The target and owner of the last map created.
FakeSurfaceTarget* last_target = nullptr;
std::weak_ptr<MapTexture> last_owner;

// Events received through the callback.
struct Event {
  int32_t type;
  int64_t frame_id;
  double zoom;
  int32_t physical_width;
  int64_t display_time_us;
  std::string message;
};
std::mutex events_mutex;
std::vector<Event> events;

void OnEvent(map_texture_event* event) {
  {
    std::lock_guard lock(events_mutex);
    events.push_back({event->type, event->frame_id, event->zoom,
                      event->physical_width, event->display_time_us,
                      event->message == nullptr ? "" : event->message});
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

std::vector<Event> FrameEvents() {
  std::lock_guard lock(events_mutex);
  std::vector<Event> frames;
  for (const auto& event : events) {
    if (event.type == MAP_TEXTURE_EVENT_FRAME_DISPLAYED) frames.push_back(event);
  }
  return frames;
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

// A clock the test advances.
std::atomic<int64_t> fake_now{0};
int64_t FakeNow() { return fake_now.load(); }

// Sets `error` to the message of map_texture_create().
int64_t CreateMapWithRules(const std::vector<const char*>& strings,
                           const std::vector<int32_t>& counts,
                           std::string* error = nullptr) {
  fake_mln::Reset();
  {
    std::lock_guard lock(events_mutex);
    events.clear();
  }
  char* message = nullptr;
  int64_t handle = map_texture_create(
      2.0, 1, OnEvent, strings.empty() ? nullptr : strings.data(),
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

void SurfaceFrameIsReportedWithoutDisplayTime() {
  int64_t handle = CreateMap();
  map_texture_set_camera(handle, 51.5, -0.1, 12.5, 0);
  map_texture_resize(handle, 200, 100, 2.0);
  CHECK(last_target->will_resize_width.load() == 400);
  CHECK(WaitFor([] { return !FrameEvents().empty(); }));
  auto frames = FrameEvents();
  CHECK(frames[0].display_time_us == -1);
  CHECK(frames[0].physical_width == 400);
  CHECK(frames[0].zoom == 12.5);
  CHECK(last_target->attached_size.physical_height == 200);
  // A surface target has no display buffers for Flutter to take.
  auto owner = last_owner.lock();
  CHECK(owner->Present() == nullptr);
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames == 1);
  CHECK(stats.presented_frames == 1);
  CHECK(stats.waits_for_display == 0);
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

  // A render update after more than an interval renders at once.
  fake_now += 5 * kInterval;
  fake_mln::QueueRenderUpdate();
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 3; }));
  CHECK(Stats(handle).interval_waits == 1);

  map_texture_dispose(handle);
  map_texture::SetClockForTesting(nullptr);
  fake_mln::SetClock(nullptr);
}

void IdleMapRendersNothing() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 1; }));
  Sleep(600);
  CHECK(fake_mln::RenderCount() == 1);
  auto stats = Stats(handle);
  CHECK(stats.rendered_frames == 1);
  CHECK(stats.interval_waits == 0);
  map_texture_dispose(handle);
}

void NoRenderWhilePaused() {
  int64_t handle = CreateMap();
  map_texture_resize(handle, 100, 100, 2.0);
  CHECK(WaitFor([] { return fake_mln::RenderCount() == 1; }));
  map_texture_set_paused_for_testing(1);
  map_texture_set_camera(handle, 0, 0, 3, 0);
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
  CHECK(WaitFor([] { return FrameEvents().size() == 1; }));
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
  CHECK(map_texture_create(2.0, 1, OnEvent, nullptr, nullptr, 1, &message) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(message != nullptr);
  map_texture_string_free(message);
  CHECK(CreateMapWithRules({"https://a.example.com/**"}, {-1}, &error) ==
        MAP_TEXTURE_ERROR_INVALID_ARGUMENT);
  CHECK(!error.empty());
  // A null out_error is allowed.
  CHECK(map_texture_create(2.0, 1, nullptr, nullptr, nullptr, 0, nullptr) ==
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

}  // namespace

namespace map_texture {

std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner, bool) {
  auto target = std::make_unique<FakeSurfaceTarget>();
  last_target = target.get();
  last_owner = std::move(owner);
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
  IdleMapRendersNothing();
  NoRenderWhilePaused();
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
  if (failures > 0) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("map texture tests passed\n");
  return 0;
}
