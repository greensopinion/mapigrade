// Unit tests for CommandQueue, BufferState, RenderGate and the projection.
#include <atomic>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <thread>
#include <vector>

#include "buffer_state.h"
#include "command_queue.h"
#include "projection.h"
#include "render_gate.h"

using map_texture::BufferState;
using map_texture::Camera;
using map_texture::Command;
using map_texture::CommandQueue;
using map_texture::FrameInfo;
using map_texture::RenderGate;
using Slot = map_texture::BufferState::Slot;
using map_texture::Viewport;
using map_texture::WorldPoint;

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

FrameInfo Frame(uint64_t id) {
  FrameInfo info;
  info.frame_id = id;
  return info;
}

int PresentIndex(BufferState& state, int index) {
  return state.Present(index, [](const BufferState::Presented&) {}).index;
}

// Acquires slot `index`, as the map thread does, and publishes frame `id`
// into it. Returns false if the slot wasn't free.
bool PublishAt(BufferState& state, int index, uint64_t id) {
  if (state.AcquireFree(index) != index) return false;
  state.Publish(index, Frame(id));
  return true;
}

void CommandsKeepOrder() {
  CommandQueue queue;
  queue.Push(Command::StyleUrl("a"));
  queue.Push(Command::Resize({100, 100, 2}));
  queue.Push(Command::StyleJson("{}"));
  queue.Push(Command::Dispose());

  auto commands = queue.TakeAll();
  CHECK(commands.size() == 4);
  CHECK(commands[0].kind == Command::Kind::kStyleUrl);
  CHECK(commands[0].text == "a");
  CHECK(commands[1].kind == Command::Kind::kResize);
  CHECK(commands[2].kind == Command::Kind::kStyleJson);
  CHECK(commands[2].text == "{}");
  CHECK(commands[3].kind == Command::Kind::kDispose);
  CHECK(queue.TakeAll().empty());
}

void StyleCommandsAreNotCoalesced() {
  CommandQueue queue;
  queue.Push(Command::StyleUrl("a"));
  queue.Push(Command::StyleUrl("b"));
  auto commands = queue.TakeAll();
  CHECK(commands.size() == 2);
  CHECK(commands[0].text == "a");
  CHECK(commands[1].text == "b");
}

void ConsecutiveResizesAreCoalesced() {
  CommandQueue queue;
  queue.Push(Command::Resize({100, 100, 1}));
  queue.Push(Command::Resize({200, 100, 1}));
  queue.Push(Command::Resize({300, 100, 2}));
  auto commands = queue.TakeAll();
  CHECK(commands.size() == 1);
  CHECK((commands[0].viewport == Viewport{300, 100, 2}));
}

void ResizesSeparatedByOtherCommandsAreKept() {
  CommandQueue queue;
  queue.Push(Command::Resize({100, 100, 1}));
  queue.Push(Command::StyleUrl("a"));
  queue.Push(Command::Resize({200, 100, 1}));
  auto commands = queue.TakeAll();
  CHECK(commands.size() == 3);
  CHECK(commands[0].viewport.logical_width == 100);
  CHECK(commands[2].viewport.logical_width == 200);
}

void LatestCameraWins() {
  CommandQueue queue;
  CHECK(!queue.TakeCamera().has_value());
  for (int i = 0; i < 100; ++i) queue.SetCamera({0, 0, double(i), 0}, i);
  auto camera = queue.TakeCamera();
  CHECK(camera.has_value());
  CHECK(camera->camera.zoom == 99);
  CHECK(!queue.TakeCamera().has_value());
}

void CameraFromManyThreadsCoalescesToOne() {
  CommandQueue queue;
  std::vector<std::thread> threads;
  for (int t = 0; t < 4; ++t) {
    threads.emplace_back([&queue, t] {
      for (int i = 0; i < 1000; ++i) queue.SetCamera({double(t), 0, 0, 0}, i);
    });
  }
  for (auto& thread : threads) thread.join();
  CHECK(queue.TakeCamera().has_value());
  CHECK(!queue.TakeCamera().has_value());
}

void LatestCameraKeepsItsSequenceNumber() {
  CommandQueue queue;
  queue.SetCamera({0, 0, 1, 0}, 1);
  queue.SetCamera({0, 0, 2, 0}, 2);
  queue.SetCamera({0, 0, 3, 0}, 3);
  auto camera = queue.TakeCamera();
  CHECK(camera.has_value());
  CHECK(camera->seq == 3);
  CHECK(camera->camera.zoom == 3);
}

void EmptyStateHasNothingToPresent() {
  BufferState state;
  auto presented = state.Present(0, [](const BufferState::Presented&) {});
  CHECK(presented.index == -1);
  CHECK(!presented.is_new);
  CHECK(state.AcquireFree(-1) == 0);
}

void AcquirePrefersCurrentTarget() {
  BufferState state;
  CHECK(state.AcquireFree(2) == 2);
  CHECK(state.slot(2) == Slot::kRendering);
}

void ReleasedSlotIsFree() {
  BufferState state;
  int index = state.AcquireFree(-1);
  state.Release(index);
  CHECK(state.slot(index) == Slot::kFree);
  CHECK(state.AcquireFree(index) == index);
}

void ReadySlotIsNotFree() {
  BufferState state;
  CHECK(state.AcquireFree(0) == 0);
  state.Publish(0, Frame(1));
  CHECK(state.slot(0) == Slot::kReady);
  int next = state.AcquireFree(0);
  CHECK(next != 0);
  CHECK(next >= 0);
}

void ChosenSlotStaysHeldUntilLaterChosenSlotIsPresented() {
  BufferState state;
  // Dart chooses slot 0, then slot 1. Flutter presents 0, then 1.
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.SelectNewest() == 1);
  CHECK(PresentIndex(state, 0) == 0);
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(state.slot(1) == Slot::kHeld);
  CHECK(PresentIndex(state, 1) == 1);
  CHECK(state.slot(0) == Slot::kFree);
  CHECK(state.slot(1) == Slot::kHeld);
}

void ChosenSlotIsHeldBeforeAnyPresent() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.SelectNewest() == 1);
  // Neither has been presented, so a raster of either may still run.
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(state.slot(1) == Slot::kHeld);
}

void PresentedSlotStaysHeldUntilAnotherSlotIsPresented() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  CHECK(PresentIndex(state, 0) == 0);
  // Presenting it again, or a slot Dart didn't choose, frees nothing.
  CHECK(PresentIndex(state, 0) == 0);
  CHECK(PresentIndex(state, 2) == -1);
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.SelectNewest() == 1);
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PresentIndex(state, 1) == 1);
  CHECK(state.slot(0) == Slot::kFree);
}

void ChoiceWithoutNewFrameChangesNothing() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.SelectNewest() == 1);
  // No newer frame: nothing is chosen, and slot 1 stays the slot chosen last.
  CHECK(state.SelectNewest() == -1);
  CHECK(state.SelectNewest() == -1);
  CHECK(state.slot(1) == Slot::kHeld);
  CHECK(PresentIndex(state, 1) == 1);
  CHECK(state.slot(0) == Slot::kFree);
  CHECK(state.slot(1) == Slot::kHeld);
}

void ReplacedReadyFrameFreesItsSlot() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.slot(0) == Slot::kFree);
  CHECK(state.slot(1) == Slot::kReady);
  // The newer frame is chosen.
  FrameInfo chosen;
  CHECK(state.SelectNewest([&](int, const FrameInfo& info) {
    chosen = info;
  }) == 1);
  CHECK(chosen.frame_id == 2);
  CHECK(state.slot(0) == Slot::kFree);
  CHECK(state.slot(1) == Slot::kHeld);
}

void NothingToChooseWithoutReadySlot() {
  BufferState state;
  bool called = false;
  CHECK(state.SelectNewest([&](int, const FrameInfo&) { called = true; }) ==
        -1);
  CHECK(!called);
  CHECK(state.slot(0) == Slot::kFree);
  // A frame still rendering, or queued on Android, isn't finished.
  int index = state.AcquireFree(-1);
  CHECK(state.SelectNewest() == -1);
  CHECK(state.slot(index) == Slot::kRendering);
  state.Publish(index, Frame(5));
  CHECK(!state.LatestReadyChosen());
  CHECK(state.SelectNewest() == index);
  CHECK(state.LatestReadyChosen());
}

void PresentReportsNewFramesOnce() {
  BufferState state;
  CHECK(PublishAt(state, 1, 7));
  CHECK(state.SelectNewest() == 1);
  auto first = state.Present(1, [](const BufferState::Presented&) {});
  CHECK(first.index == 1);
  CHECK(first.info.frame_id == 7);
  CHECK(first.is_new);
  auto again = state.Present(1, [](const BufferState::Presented&) {});
  CHECK(again.index == 1);
  CHECK(!again.is_new);
}

void PresentRunsCallbackWithResult() {
  BufferState state;
  CHECK(PublishAt(state, 2, 3));
  CHECK(state.SelectNewest() == 2);
  int seen = -1;
  state.Present(2, [&](const BufferState::Presented& p) { seen = p.index; });
  CHECK(seen == 2);
}

void NewFramesHaveIncreasingDisplayTime() {
  BufferState state;
  int64_t previous = 0;
  for (uint64_t id = 1; id <= 20; ++id) {
    int index = state.AcquireFree(-1);
    CHECK(index >= 0);
    state.Publish(index, Frame(id));
    CHECK(state.SelectNewest() == index);
    int64_t before = map_texture::DisplayClockUs();
    auto presented =
        state.Present(index, [](const BufferState::Presented&) {});
    int64_t after = map_texture::DisplayClockUs();
    CHECK(presented.is_new);
    CHECK(presented.display_time_us >= before);
    CHECK(presented.display_time_us <= after);
    CHECK(presented.display_time_us >= previous);
    previous = presented.display_time_us;
    std::this_thread::sleep_for(std::chrono::microseconds(100));
    auto again = state.Present(index, [](const BufferState::Presented&) {});
    CHECK(!again.is_new);
    CHECK(again.display_time_us == 0);
  }
}

// In each Flutter frame Dart chooses the newest ready frame and the raster
// thread presents the slot chosen in the previous Flutter frame. The map
// renders two frames per Flutter frame, the second ahead of Dart's choice.
void FourSlotsAlwaysHaveAFreeSlot() {
  BufferState state;
  uint64_t next_frame = 1;
  int ready = -1;
  uint64_t ready_frame = 0;
  int chosen_before = -1;
  for (int flutter_frame = 0; flutter_frame < 50; ++flutter_frame) {
    int chosen = -1;
    if (ready >= 0) {
      CHECK(state.SelectNewest() == ready);
      chosen = ready;
      ready = -1;
    }
    if (chosen_before >= 0) PresentIndex(state, chosen_before);
    for (int render = 0; render < 2; ++render) {
      int index = state.AcquireFree(-1);
      CHECK(index >= 0);
      if (index < 0) return;
      ready_frame = next_frame++;
      state.Publish(index, Frame(ready_frame));
      ready = index;
    }
    if (chosen >= 0) chosen_before = chosen;
  }
  CHECK(state.max_in_use() <= 4);
}

void NoFreeSlotWithoutPresent() {
  BufferState state;
  for (uint64_t frame = 1; frame <= 4; ++frame) {
    int index = state.AcquireFree(-1);
    CHECK(index >= 0);
    state.Publish(index, Frame(frame));
    CHECK(state.SelectNewest() == index);
    CHECK(state.LatestReadyChosen());
  }
  CHECK(state.AcquireFree(-1) == -1);
  CHECK(state.max_in_use() == 4);
}

// Android's release rule (design D133): Dart chooses A, B, C and D in order.
void HeldUntilThreeLaterChoices() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  for (int slot = 0; slot < 4; ++slot) {
    CHECK(PublishAt(state, slot, slot + 1));
    CHECK(state.SelectNewest() == slot);
    CHECK(state.slot(0) == (slot < 3 ? Slot::kHeld : Slot::kFree));
  }
  CHECK(state.slot(1) == Slot::kHeld);
  CHECK(state.slot(2) == Slot::kHeld);
  CHECK(state.slot(3) == Slot::kHeld);
}

void ChoiceWithoutNewFrameDoesNotCountWithLaterChoices() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.SelectNewest() == 1);
  CHECK(PublishAt(state, 2, 3));
  CHECK(state.SelectNewest() == 2);
  for (int i = 0; i < 5; ++i) CHECK(state.SelectNewest() == -1);
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PublishAt(state, 3, 4));
  CHECK(state.SelectNewest() == 3);
  CHECK(state.slot(0) == Slot::kFree);
  CHECK(state.slot(1) == Slot::kHeld);
}

void PresentFreesNothingWithLaterChoices() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.SelectNewest() == 1);
  CHECK(PresentIndex(state, 1) == 1);
  CHECK(state.slot(0) == Slot::kHeld);
}

// Android (design D133): in each Flutter frame Dart chooses the newest ready
// frame. The map, paced by its own clock, renders two frames in some Flutter
// frames, and each frame's image arrives only after the next render has
// started. Then three slots are held, one is ready, one queued and one
// rendering.
void SixSlotsAlwaysHaveAFreeSlotWithLaterChoices() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  uint64_t next_frame = 1;
  uint64_t queued_frame = 0;
  for (int flutter_frame = 0; flutter_frame < 50; ++flutter_frame) {
    int renders = flutter_frame % 2 == 0 ? 2 : 1;
    for (int render = 0; render < renders; ++render) {
      int index = state.AcquireFree(-1);
      CHECK(index >= 0);
      if (index < 0) return;
      uint64_t frame = next_frame++;
      state.Expect(index, frame);
      CHECK(!state.Queue(index, Frame(frame)));
      // The image of the frame queued before arrives.
      if (queued_frame != 0) {
        int published = -1;
        FrameInfo info;
        bool known = false;
        CHECK(state.OnImage(queued_frame, &published, &info, &known,
                            [](int) {}) ==
              BufferState::ImageResult::kPublished);
      }
      queued_frame = frame;
    }
    // Dart chooses the newest ready frame, the one published last.
    for (int i = 0; i < map_texture::kChoiceReleasedBufferCount; ++i) {
      if (state.slot(i) == Slot::kReady) {
        CHECK(state.SelectNewest() == i);
      }
    }
  }
  CHECK(state.max_in_use() == 6);
}

void FreedSlotsAreReported() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  std::vector<int> freed;
  state.set_on_freed([&](int slot) { freed.push_back(slot); });
  // A ready frame replaced by a newer one.
  CHECK(PublishAt(state, 0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK((freed == std::vector<int>{0}));
  // The release rule.
  CHECK(state.SelectNewest() == 1);
  for (int slot = 2; slot < 5; ++slot) {
    CHECK(PublishAt(state, slot, slot + 1));
    CHECK(state.SelectNewest() == slot);
  }
  CHECK((freed == std::vector<int>{0, 1}));
  // A render that published nothing.
  CHECK(state.AcquireFree(0) == 0);
  state.Release(0);
  CHECK((freed == std::vector<int>{0, 1, 0}));
  // A reset reports each slot in use.
  state.WithLock([&](int) { state.ResetLocked(); });
  CHECK((freed == std::vector<int>{0, 1, 0, 2, 3, 4}));
}

void LatestReadyChosenPacesRendering() {
  BufferState state;
  CHECK(state.LatestReadyChosen());  // No frame yet.
  CHECK(PublishAt(state, 0, 1));
  CHECK(!state.LatestReadyChosen());
  CHECK(state.SelectNewest() == 0);
  CHECK(state.LatestReadyChosen());
  CHECK(PublishAt(state, 1, 2));
  CHECK(!state.LatestReadyChosen());
}

void ResetFreesAllSlots() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.SelectNewest() == 0);
  PresentIndex(state, 0);
  CHECK(PublishAt(state, 1, 2));
  int chosen_seen = -2;
  state.WithLock([&](int chosen) {
    chosen_seen = chosen;
    state.ResetLocked();
  });
  CHECK(chosen_seen == 0);
  for (int i = 0; i < map_texture::kBufferCount; ++i) {
    CHECK(state.slot(i) == Slot::kFree);
  }
  CHECK(PresentIndex(state, 0) == -1);
  CHECK(state.SelectNewest() == -1);
  CHECK(state.LatestReadyChosen());
  int none_seen = -2;
  state.WithLock([&](int chosen) { none_seen = chosen; });
  CHECK(none_seen == -1);
}

void ReduceMemoryUseKeepsOrder() {
  CommandQueue queue;
  queue.Push(Command::StyleUrl("a"));
  queue.Push(Command::ReduceMemoryUse());
  queue.Push(Command::Resize({100, 100, 2}));
  queue.Push(Command::ReduceMemoryUse());
  queue.Push(Command::Resize({200, 100, 2}));
  auto commands = queue.TakeAll();
  CHECK(commands.size() == 5);
  CHECK(commands[0].kind == Command::Kind::kStyleUrl);
  CHECK(commands[1].kind == Command::Kind::kReduceMemoryUse);
  CHECK(commands[2].kind == Command::Kind::kResize);
  CHECK(commands[3].kind == Command::Kind::kReduceMemoryUse);
  CHECK(commands[4].viewport.logical_width == 200);
}

void GateAllowsRendersUntilPaused() {
  RenderGate gate;
  CHECK(!gate.paused());
  CHECK(gate.TryBeginRender());
  gate.EndRender();
  gate.SetPaused(true);
  CHECK(gate.paused());
  CHECK(!gate.TryBeginRender());
  gate.SetPaused(false);
  CHECK(gate.TryBeginRender());
  gate.EndRender();
}

void PauseWaitsForRenderInProgress() {
  RenderGate gate;
  CHECK(gate.TryBeginRender());
  std::atomic<bool> paused{false};
  std::thread pauser([&] {
    gate.SetPaused(true);
    paused.store(true);
  });
  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  CHECK(!paused.load());
  gate.EndRender();
  pauser.join();
  CHECK(paused.load());
  CHECK(!gate.TryBeginRender());
}

void PauseWithoutRenderReturnsAtOnce() {
  RenderGate gate;
  auto start = std::chrono::steady_clock::now();
  gate.SetPaused(true);
  CHECK(std::chrono::steady_clock::now() - start <
        std::chrono::milliseconds(50));
  CHECK(!gate.TryBeginRender());
}

// Expected values are those of `mercator` and `screenPosition` in
// lib/src/layer/camera_projection.dart for the same inputs.
struct ProjectionCase {
  Camera camera;
  double width;
  double height;
  double latitude;
  double longitude;
  WorldPoint world;
  double x;
  double y;
};

constexpr double kTolerance = 1e-6;

void CheckProjection(const ProjectionCase& c, WorldPoint world) {
  auto p = map_texture::ScreenPosition(c.camera, c.width, c.height, world);
  CHECK(std::abs(p.x - c.x) < kTolerance);
  CHECK(std::abs(p.y - c.y) < kTolerance);
}

const ProjectionCase kProjectionCases[] = {
    {{48.2, 16.37, 12.5, 0}, 400, 800, 48.21, 16.35,
     {0.54541666666666666, 0.34674085655246356},
     35.232177735582752, 276.38718722981423},
    {{48.2, 16.37, 14, 30}, 390, 844, 48.205, 16.375,
     {0.54548611111111112, 0.34676169713161131},
     208.49608082320015, 212.35900880028581},
    {{80, -20, 9.25, -45}, 1024, 768, 80.02, -19.9,
     {0.44472222222222219, 0.11193914916789455},
     643.82655564601578, 374.63786095412877},
    {{-17, 179.9, 10, 0}, 800, 600, -17.01, 179.95,
     {0.99986111111111109, 0.54795978365423492},
     472.81777777778916, 315.22939639136894},
};

void MercatorMatchesDart() {
  for (const ProjectionCase& c : kProjectionCases) {
    WorldPoint w = map_texture::Mercator(c.latitude, c.longitude);
    CHECK(std::abs(w.x - c.world.x) < 1e-15);
    CHECK(std::abs(w.y - c.world.y) < 1e-15);
  }
}

void ScreenPositionMatchesDart() {
  for (const ProjectionCase& c : kProjectionCases) CheckProjection(c, c.world);
}

void ScreenPositionWrapsAcrossTheAntimeridian() {
  // 180.05 degrees east of the camera at 179.9 is -179.95: Dart places the
  // unwrapped x 1.000138..., the native side must place either copy there.
  const ProjectionCase east = {{-17, 179.9, 10, 0}, 800, 600, -17.01, 180.05,
                               {1.0001388888888889, 0.54795978365423492},
                               618.45333333336748, 315.22939639136894};
  CheckProjection(east, east.world);
  CheckProjection(east, {east.world.x - 1, east.world.y});
  CheckProjection(east, {east.world.x + 1, east.world.y});
}

// Screen positions from MapLibre Native's projection
// (mln_map_projection_pixel_for_lat_lng in maplibre-native-ffi 7698f75d9), at
// center 45.5, -122.6 and MapLibre zoom 11: width, height, bearing, pitch,
// latitude, longitude, x, y.
struct PitchedCase {
  double width, height, bearing, pitch, latitude, longitude, x, y;
};
const PitchedCase kPitchedCases[] = {
    {400, 300, 0, 0, 45.536084144411575, -122.66866455010938, 6.6227383083767364e-10, 1.0199016742262756e-08},
    {400, 300, 0, 0, 45.536084144411575, -122.5999999999991, 200.00000000261599, 1.0199016742262756e-08},
    {400, 300, 0, 0, 45.536084144411575, -122.53133544989106, 399.99999999807943, 1.0199016742262756e-08},
    {400, 300, 0, 0, 45.499999999996362, -122.66866455010938, 6.6227383083767364e-10, 150.0000000152323},
    {400, 300, 0, 0, 45.499999999996362, -122.5999999999991, 200.00000000261599, 150.0000000152323},
    {400, 300, 0, 0, 45.499999999996362, -122.53133544989106, 399.99999999807943, 150.0000000152323},
    {400, 300, 0, 0, 45.463892715291536, -122.66866455010938, 6.6227383083767364e-10, 300.00000000695388},
    {400, 300, 0, 0, 45.463892715291536, -122.5999999999991, 200.00000000261599, 300.00000000695388},
    {400, 300, 0, 0, 45.463892715291536, -122.53133544989106, 399.99999999807943, 300.00000000695388},
    {400, 300, -30, 0, 45.507195536207831, -122.68521445102377, -2.4090210596720376e-09, 1.4106433354754699e-08},
    {400, 300, -30, 0, 45.531251128144078, -122.62574920629021, 199.99999999274812, 1.7815182218328118e-08},
    {400, 300, -30, 0, 45.555296435710204, -122.56628396155438, 400.00000000040563, 1.3245482932688901e-08},
    {400, 300, -30, 0, 45.47593104803363, -122.65946524473185, -3.0630164676242405e-10, 150.0000000152323},
    {400, 300, -30, 0, 45.499999999995424, -122.59999999999829, 199.99999999475148, 150.00000001913972},
    {400, 300, -30, 0, 45.524058667385134, -122.5405347552647, 399.99999999669689, 150.00000001139111},
    {400, 300, -30, 0, 45.444649204390885, -122.63371603844219, -3.9074156019422747e-09, 300.00000001304682},
    {400, 300, -30, 0, 45.46873151662669, -122.57425079370636, 199.99999999700321, 300.00000002013314},
    {400, 300, -30, 0, 45.492803544100525, -122.51478554897278, 399.99999999879964, 300.0000000125832},
    {400, 300, 0, 30, 45.551588932428047, -122.68502824292848, 7.7147665836599321e-09, -3.9576661947648972e-09},
    {400, 300, 0, 30, 45.551588932428047, -122.59999999999557, 200.00000001040851, -3.9576661947648972e-09},
    {400, 300, 0, 30, 45.551588932428047, -122.51497175706544, 400.00000000659082, -3.9576661947648972e-09},
    {400, 300, 0, 30, 45.500000000001052, -122.66866455010737, 7.4671374426599979e-09, 149.99999999635438},
    {400, 300, 0, 30, 45.500000000001052, -122.59999999999641, 200.00000001044324, 149.99999999635438},
    {400, 300, 0, 30, 45.500000000001052, -122.53133544988773, 400.00000000682968, 149.99999999635438},
    {400, 300, 0, 30, 45.465036123048236, -122.65758274564877, 7.1470428142180591e-09, 299.99999999699719},
    {400, 300, 0, 30, 45.465036123048236, -122.59999999999701, 200.0000000103837, 299.99999999699719},
    {400, 300, 0, 30, 45.465036123048236, -122.54241725434525, 400.00000001362037, 299.99999999699719},
    {400, 300, -30, 30, 45.514897299481817, -122.7104549276275, -4.840113523933861e-09, 1.6579519979131874e-09},
    {400, 300, -30, 30, 45.54468007065833, -122.63681830921141, 199.99999998945361, 4.2250576370861381e-09},
    {400, 300, -30, 30, 45.57444707170967, -122.5631816907925, 399.99999999596798, 1.0429062058392446e-09},
    {400, 300, -30, 30, 45.475931048036017, -122.65946524473566, -5.2485201093950128e-09, 150.00000000097904},
    {400, 300, -30, 30, 45.500000000000938, -122.60000000000238, 199.99999999587632, 149.99999999425813},
    {400, 300, -30, 30, 45.524058667387379, -122.5405347552668, 399.99999999603983, 150.00000000028029},
    {400, 300, -30, 30, 45.449527047436021, -122.62493406027787, -5.686045111886017e-09, 300.00000000060214},
    {400, 300, -30, 30, 45.469721653142955, -122.57506593972555, 199.99999999568178, 299.99999999266385},
    {400, 300, -30, 30, 45.489909025926238, -122.5251978191732, 399.99999998974096, 299.99999999645672},
    {400, 300, 0, 45, 45.576518508234358, -122.70299682465944, 3.3334449648373913e-09, -1.3907879292673897e-09},
    {400, 300, 0, 45, 45.576518508234358, -122.60000000000167, 199.99999999677004, -1.3907879292673897e-09},
    {400, 300, 0, 45, 45.576518508234358, -122.49700317534393, 399.99999999015142, -1.3907879292673897e-09},
    {400, 300, 0, 45, 45.500000000000028, -122.6686645501088, 2.3427936765885733e-09, 150.00000000005252},
    {400, 300, 0, 45, 45.500000000000028, -122.60000000000112, 199.99999999676416, 150.00000000005252},
    {400, 300, 0, 45, 45.500000000000028, -122.53133544989345, 399.99999999118558, 150.00000000005252},
    {400, 300, 0, 45, 45.461701696676272, -122.65149841270754, 5.5189485767293247e-09, 299.99999999037493},
    {400, 300, 0, 45, 45.461701696676272, -122.60000000000085, 199.99999999669967, 299.99999999037493},
    {400, 300, 0, 45, 45.461701696676272, -122.54850158729417, 399.99999998783625, 299.99999999037493},
    {400, 300, -30, 45, 45.530208239240466, -122.74382018152914, 1.4790782294624093e-09, 4.9229242904402781e-09},
    {400, 300, -30, 45, 45.566273012745853, -122.65462231486106, 200.00000001414645, 2.4062387637968641e-09},
    {400, 300, -30, 45, 45.602314646950362, -122.5654244481926, 400.00000002132657, 5.2540372053044848e-09},
    {400, 300, -30, 45, 45.475931048035221, -122.65946524472959, 4.6690305074992096e-09, 150.00000000900098},
    {400, 300, -30, 45, 45.499999999997243, -122.59999999999368, 200.00000001015968, 150.00000001358023},
    {400, 300, -30, 45, 45.524058667387123, -122.54053475525762, 400.00000002324583, 150.00000001023628},
    {400, 300, -30, 45, 45.448772828801452, -122.6172877760208, -2.2075794308112806e-09, 300.00000002278085},
    {400, 300, -30, 45, 45.466834206654312, -122.57268884236102, 200.00000001380289, 300.00000000891583},
    {400, 300, -30, 45, 45.484889799316335, -122.52808990870174, 400.00000001340828, 300.00000001215341},
    {400, 300, 0, 60, 45.670547680028534, -122.76246206772109, 9.6831317216132372e-09, -6.7177552409702912e-10},
    {400, 300, 0, 60, 45.670547680028534, -122.59999999998919, 200.00000001331279, -6.7177552409702912e-10},
    {400, 300, 0, 60, 45.670547680028534, -122.43753793226263, 400.0000000103733, -6.7177552409702912e-10},
    {400, 300, 0, 60, 45.500000000002331, -122.66866455010688, 1.1606348885217047e-08, 149.99999999524147},
    {400, 300, 0, 60, 45.500000000002331, -122.59999999999542, 200.00000001335516, 149.99999999524147},
    {400, 300, 0, 60, 45.500000000002331, -122.53133544988623, 400.00000000847297, 149.99999999524147},
    {400, 300, 0, 60, 45.454213866377074, -122.64353158058422, 8.5856169319383668e-09, 299.99999999833921},
    {400, 300, 0, 60, 45.454213866377074, -122.5999999999971, 200.00000001335013, 299.99999999833921},
    {400, 300, 0, 60, 45.454213866377074, -122.55646841941143, 400.00000001137022, 299.99999999833921},
    {400, 300, -30, 60, 45.590913886687929, -122.86254282859359, 1.6766600617708741e-08, -1.7774368643586058e-09},
    {400, 300, -30, 60, 45.647728681413895, -122.72184655079229, 200.00000000855169, -1.2245777725183871e-09},
    {400, 300, -30, 60, 45.704485908275643, -122.58115027299036, 400.00000000540928, -3.0580054044548888e-09},
    {400, 300, -30, 60, 45.475931048038262, -122.6594652447294, 1.4603137970029259e-08, 150.00000000101539},
    {400, 300, -30, 60, 45.500000000003155, -122.59999999999863, 200.00000000994032, 149.99999999533563},
    {400, 300, -30, 60, 45.524058667389625, -122.54053475526548, 400.00000000175709, 149.99999999703709},
    {400, 300, -30, 60, 45.445081552901541, -122.60505076921211, 1.9273567439503888e-08, 299.99999999609486},
    {400, 300, -30, 60, 45.460350203398406, -122.56735131455872, 200.00000001048392, 299.99999999895942},
    {400, 300, -30, 60, 45.475614720183728, -122.52965185990524, 400.0000000051416, 300.00000000162328},
    {390, 844, 0, 0, 45.601457702806982, -122.66694793635082, 1.7631863719102519e-08, -8.112067462207051e-08},
    {390, 844, 0, 0, 45.601457702806982, -122.59999999999492, 195.00000001485407, -8.112067462207051e-08},
    {390, 844, 0, 0, 45.601457702806982, -122.53305206363905, 390.0000000119586, -8.112067462207051e-08},
    {390, 844, 0, 0, 45.500000000016342, -122.66694793635082, 1.7631863719102519e-08, 421.99999993225032},
    {390, 844, 0, 0, 45.500000000016342, -122.59999999999492, 195.00000001485407, 421.99999993225032},
    {390, 844, 0, 0, 45.500000000016342, -122.53305206363905, 390.0000000119586, 421.99999993225032},
    {390, 844, 0, 0, 45.398359145582901, -122.66694793635082, 1.7631863719102519e-08, 843.99999990875688},
    {390, 844, 0, 0, 45.398359145582901, -122.59999999999492, 195.00000001485407, 843.99999990875688},
    {390, 844, 0, 0, 45.398359145582901, -122.53305206363905, 390.0000000119586, 843.99999990875688},
    {390, 844, -30, 0, 45.564445115789596, -122.73041971397875, 3.7788450247115243e-08, -4.86818407807732e-08},
    {390, 844, -30, 0, 45.587875572737829, -122.67244110036515, 195.00000004028374, -6.6902202888741158e-08},
    {390, 844, -30, 0, 45.611296253472233, -122.61446248674523, 390.00000004032495, -4.4020794121024664e-08},
    {390, 844, -30, 0, 45.476532897195085, -122.65797861361082, 4.3608848517539945e-08, 421.99999995456676},
    {390, 844, -30, 0, 45.500000000018844, -122.59999999999722, 195.0000000461277, 421.9999999363464},
    {390, 844, -30, 0, 45.523457326059287, -122.54202138638362, 390.00000003019073, 421.9999999499999},
    {390, 844, -30, 0, 45.388483312908363, -122.58553751324922, 3.3515842416651817e-08, 843.99999994863458},
    {390, 844, -30, 0, 45.411987063525515, -122.52755889962927, 195.00000005208932, 843.99999993950087},
    {390, 844, -30, 0, 45.435481036881157, -122.46958028601568, 390.00000003605822, 843.99999995334269},
    {390, 844, 0, 30, 45.645016187745853, -122.682902536857, 5.1327432568024269e-10, 1.5778482520545367e-08},
    {390, 844, 0, 30, 45.645016187745853, -122.60000000000136, 194.99999999681492, 1.5778482520545367e-08},
    {390, 844, 0, 30, 45.645016187745853, -122.51709746314572, 389.99999999313553, 1.5778482520545367e-08},
    {390, 844, 0, 30, 45.499999999995765, -122.66694793635607, 9.8870263846125658e-10, 422.00000001537859},
    {390, 844, 0, 30, 45.499999999995765, -122.6000000000011, 194.99999999681944, 422.00000001537859},
    {390, 844, 0, 30, 45.499999999995765, -122.53305206364612, 389.99999999267374, 422.00000001537859},
    {390, 844, 0, 30, 45.401579610834176, -122.65614317700867, 1.5158295618245613e-09, 844.00000001313936},
    {390, 844, 0, 30, 45.401579610834176, -122.60000000000092, 194.99999999681626, 844.00000001313936},
    {390, 844, 0, 30, 45.401579610834176, -122.54385682299315, 389.99999999225702, 844.00000001313936},
    {390, 844, -30, 30, 45.596613236900254, -122.77537787953842, -1.5493280571284013e-08, -4.2202827899018303e-09},
    {390, 844, -30, 30, 45.62560942497069, -122.7035821765769, 195.00000000116623, -1.0607664080453105e-08},
    {390, 844, -30, 30, 45.654590622416293, -122.63178647362318, 389.99999998402382, -1.3686758393305354e-09},
    {390, 844, -30, 30, 45.476532897180078, -122.65797861362233, -1.5995796257799203e-08, 421.99999999299212},
    {390, 844, -30, 30, 45.499999999994856, -122.60000000000275, 194.99999998232357, 422.00000001268899},
    {390, 844, -30, 30, 45.523457326044081, -122.54202138638948, 389.99999998353019, 421.99999999677027},
    {390, 844, -30, 30, 45.395066571636107, -122.57847359463698, -1.1228367124399835e-08, 843.99999996046074},
    {390, 844, -30, 30, 45.414775406140279, -122.52985217709465, 194.99999998481044, 843.99999998399392},
    {390, 844, -30, 30, 45.434477364652793, -122.48123075955758, 389.99999998382748, 843.99999996526719},
    {390, 844, 0, 45, 45.715006473860257, -122.7004219040532, -1.3245476681241622e-08, -1.8659761735762004e-08},
    {390, 844, 0, 45, 45.715006473860257, -122.60000000000926, 194.99999998205146, -1.8659761735762004e-08},
    {390, 844, 0, 45, 45.715006473860257, -122.49957809596532, 389.99999997731703, -1.8659761735762004e-08},
    {390, 844, 0, 45, 45.500000000005002, -122.66694793636253, -1.4218485562369855e-08, 421.99999998538419},
    {390, 844, 0, 45, 45.500000000005002, -122.60000000000618, 194.99999998202455, 421.99999998538419},
    {390, 844, 0, 45, 45.500000000005002, -122.53305206364981, 389.99999997836176, 421.99999998538419},
    {390, 844, 0, 45, 45.392187701400076, -122.65021095239153, -2.3540538953025271e-09, 843.99999998371072},
    {390, 844, 0, 45, 45.392187701400076, -122.6000000000016, 194.99999999380805, 843.99999998371072},
    {390, 844, 0, 45, 45.392187701400076, -122.54978904761168, 389.99999998993877, 843.99999998371072},
    {390, 844, -30, 45, 45.651161159428142, -122.8406386991492, 1.1840891180526896e-08, 1.2413693184498698e-08},
    {390, 844, -30, 45, 45.68624887694142, -122.75367077915622, 195.00000001240667, 3.9077576730051078e-09},
    {390, 844, -30, 45, 45.721314599661781, -122.66670285915376, 390.00000001100238, 1.4846250451228116e-08},
    {390, 844, -30, 45, 45.476532897178515, -122.6579786136052, 2.0927539180878727e-08, 422.00000001584721},
    {390, 844, -30, 45, 45.499999999992667, -122.59999999999337, 195.00000000141426, 422.00000002562757},
    {390, 844, -30, 45, 45.523457326041182, -122.54202138637524, 390.00000001662323, 422.00000001940833},
    {390, 844, -30, 45, 45.389015200576267, -122.56664857016409, 8.0822517074842921e-09, 844.00000004199921},
    {390, 844, -30, 45, 45.406643764292312, -122.52316460984903, 195.00000000868823, 844.00000002492482},
    {390, 844, -30, 45, 45.424266828289007, -122.47968064952924, 390.00000002243854, 844.0000000163617},
    {390, 844, 0, 60, 45.978485982154098, -122.75840051603046, 2.5669458731569267e-09, 4.3329464460839517e-09},
    {390, 844, 0, 60, 45.978485982154098, -122.60000000000369, 194.99999999547722, 4.3329464460839517e-09},
    {390, 844, 0, 60, 45.978485982154098, -122.44159948397692, 389.99999998837757, 4.3329464460839517e-09},
    {390, 844, 0, 60, 45.499999999997755, -122.66694793635455, 5.5084861285670719e-09, 422.00000000474847},
    {390, 844, 0, 60, 45.499999999997755, -122.60000000000156, 194.99999999547319, 422.00000000474847},
    {390, 844, 0, 60, 45.499999999997755, -122.53305206364857, 389.99999998548498, 422.00000000474847},
    {390, 844, 0, 60, 45.371093446346435, -122.64244329106717, 1.17336094308235e-08, 844.00000004220078},
    {390, 844, 0, 60, 45.371093446346435, -122.59999999999843, 195.00000000723387, 844.00000004220078},
    {390, 844, 0, 60, 45.371093446346435, -122.5575567089297, 390.00000000273411, 844.00000004220078},
    {390, 844, -30, 60, 45.859489563535817, -123.07997383377484, -3.0086993490054602e-08, 4.6363766159629449e-09},
    {390, 844, -30, 60, 45.91461887941648, -122.94279496290858, 194.99999998864342, 2.8106796889915131e-09},
    {390, 844, -30, 60, 45.969693483721187, -122.80561609205751, 389.99999997352978, 5.7059423852479085e-09},
    {390, 844, -30, 60, 45.476532897168937, -122.65797861362304, -4.5703956490469349e-08, 422.00000001546942},
    {390, 844, -30, 60, 45.499999999992326, -122.60000000000383, 194.9999999743244, 422.00000001107981},
    {390, 844, -30, 60, 45.523457326041381, -122.542021386391, 389.99999997483326, 422.00000000191807},
    {390, 844, -30, 60, 45.373474860481991, -122.54490533325372, -2.3857101452917833e-08, 844.00000001435455},
    {390, 844, -30, 60, 45.388380732555675, -122.50814836496775, 194.99999996015779, 844.00000002524519},
    {390, 844, -30, 60, 45.403282674879136, -122.47139139667777, 389.99999997908759, 844.00000001843068},
};

void ScreenPositionMatchesMapLibreWhenPitched() {
  for (const PitchedCase& c : kPitchedCases) {
    map_texture::Camera camera{45.5, -122.6, 11, c.bearing, c.pitch};
    auto p = map_texture::ScreenPosition(
        camera, c.width, c.height,
        map_texture::Mercator(c.latitude, c.longitude));
    CHECK(std::abs(p.x - c.x) < 0.01);
    CHECK(std::abs(p.y - c.y) < 0.01);
  }
}

void ScreenBoundsContainRotatedCorners() {
  // At a bearing of 45 degrees, a square of side 2 around the center spans
  // 2 * sqrt(2) on each axis.
  Camera camera{0, 0, 3, 45};
  double half = 1 / map_texture::WorldSize(3);
  WorldPoint center = map_texture::Mercator(0, 0);
  WorldPoint corners[4] = {{center.x - half, center.y - half},
                           {center.x + half, center.y - half},
                           {center.x + half, center.y + half},
                           {center.x - half, center.y + half}};
  auto box = map_texture::ScreenBounds(camera, 100, 100, corners);
  CHECK(std::abs(box.min.x - (50 - std::sqrt(2.0))) < kTolerance);
  CHECK(std::abs(box.max.x - (50 + std::sqrt(2.0))) < kTolerance);
  CHECK(std::abs(box.min.y - (50 - std::sqrt(2.0))) < kTolerance);
  CHECK(std::abs(box.max.y - (50 + std::sqrt(2.0))) < kTolerance);
}

}  // namespace

int main() {
  const std::vector<std::pair<const char*, std::function<void()>>> tests = {
      {"CommandsKeepOrder", CommandsKeepOrder},
      {"StyleCommandsAreNotCoalesced", StyleCommandsAreNotCoalesced},
      {"ConsecutiveResizesAreCoalesced", ConsecutiveResizesAreCoalesced},
      {"ResizesSeparatedByOtherCommandsAreKept",
       ResizesSeparatedByOtherCommandsAreKept},
      {"LatestCameraWins", LatestCameraWins},
      {"CameraFromManyThreadsCoalescesToOne",
       CameraFromManyThreadsCoalescesToOne},
      {"LatestCameraKeepsItsSequenceNumber", LatestCameraKeepsItsSequenceNumber},
      {"EmptyStateHasNothingToPresent", EmptyStateHasNothingToPresent},
      {"AcquirePrefersCurrentTarget", AcquirePrefersCurrentTarget},
      {"ReleasedSlotIsFree", ReleasedSlotIsFree},
      {"ReadySlotIsNotFree", ReadySlotIsNotFree},
      {"ChosenSlotStaysHeldUntilLaterChosenSlotIsPresented", ChosenSlotStaysHeldUntilLaterChosenSlotIsPresented},
      {"ChosenSlotIsHeldBeforeAnyPresent", ChosenSlotIsHeldBeforeAnyPresent},
      {"PresentedSlotStaysHeldUntilAnotherSlotIsPresented", PresentedSlotStaysHeldUntilAnotherSlotIsPresented},
      {"ChoiceWithoutNewFrameChangesNothing", ChoiceWithoutNewFrameChangesNothing},
      {"ReplacedReadyFrameFreesItsSlot", ReplacedReadyFrameFreesItsSlot},
      {"NothingToChooseWithoutReadySlot", NothingToChooseWithoutReadySlot},
      {"PresentReportsNewFramesOnce", PresentReportsNewFramesOnce},
      {"PresentRunsCallbackWithResult", PresentRunsCallbackWithResult},
      {"NewFramesHaveIncreasingDisplayTime", NewFramesHaveIncreasingDisplayTime},
      {"FourSlotsAlwaysHaveAFreeSlot", FourSlotsAlwaysHaveAFreeSlot},
      {"NoFreeSlotWithoutPresent", NoFreeSlotWithoutPresent},
      {"HeldUntilThreeLaterChoices", HeldUntilThreeLaterChoices},
      {"ChoiceWithoutNewFrameDoesNotCountWithLaterChoices", ChoiceWithoutNewFrameDoesNotCountWithLaterChoices},
      {"PresentFreesNothingWithLaterChoices", PresentFreesNothingWithLaterChoices},
      {"SixSlotsAlwaysHaveAFreeSlotWithLaterChoices", SixSlotsAlwaysHaveAFreeSlotWithLaterChoices},
      {"FreedSlotsAreReported", FreedSlotsAreReported},
      {"LatestReadyChosenPacesRendering", LatestReadyChosenPacesRendering},
      {"ResetFreesAllSlots", ResetFreesAllSlots},
      {"ReduceMemoryUseKeepsOrder", ReduceMemoryUseKeepsOrder},
      {"GateAllowsRendersUntilPaused", GateAllowsRendersUntilPaused},
      {"PauseWaitsForRenderInProgress", PauseWaitsForRenderInProgress},
      {"PauseWithoutRenderReturnsAtOnce", PauseWithoutRenderReturnsAtOnce},
      {"MercatorMatchesDart", MercatorMatchesDart},
      {"ScreenPositionMatchesDart", ScreenPositionMatchesDart},
      {"ScreenPositionWrapsAcrossTheAntimeridian", ScreenPositionWrapsAcrossTheAntimeridian},
      {"ScreenBoundsContainRotatedCorners", ScreenBoundsContainRotatedCorners},
      {"ScreenPositionMatchesMapLibreWhenPitched", ScreenPositionMatchesMapLibreWhenPitched},
  };
  for (const auto& [name, test] : tests) {
    int before = failures;
    test();
    std::printf("%s %s\n", failures == before ? "PASS" : "FAIL", name);
  }
  std::printf("%d failure(s)\n", failures);
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
