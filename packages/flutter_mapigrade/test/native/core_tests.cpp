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
#include "overlay.h"
#include "projection.h"
#include "render_gate.h"
#include "style_layer_fixtures.h"

using map_texture::Anchor;
using map_texture::BufferState;
using map_texture::Camera;
using map_texture::Command;
using map_texture::CommandQueue;
using map_texture::ComputeAnchor;
using map_texture::FrameInfo;
using map_texture::LayerPlan;
using map_texture::OverlayAction;
using map_texture::OverlayLayout;
using map_texture::Placement;
using map_texture::PlacementKind;
using map_texture::PlanLayers;
using map_texture::RenderGate;
using Slot = map_texture::BufferState::Slot;
using map_texture::StyleLayer;
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

// Overlay placement (design D199 of the add-mapigrade-polyline-layer change).

const Placement kBelowLabels{PlacementKind::kBelowLabels, {}};
const Placement kTop{PlacementKind::kTop, {}};

Placement BelowLayer(const char* id) {
  return {PlacementKind::kBelowLayer, id};
}

// The index of the layer `id` in `layers`, or -1.
int IndexOf(const std::vector<StyleLayer>& layers, const std::string& id) {
  for (size_t i = 0; i < layers.size(); ++i) {
    if (layers[i].id == id) return static_cast<int>(i);
  }
  return -1;
}

// Checks that `anchor` is a layer after every non-symbol layer and before
// every label of `layers`.
void CheckBelowLabelsAnchor(const std::vector<StyleLayer>& layers,
                            const std::string& anchor) {
  int index = IndexOf(layers, anchor);
  CHECK(index >= 0);
  for (int i = 0; i < static_cast<int>(layers.size()); ++i) {
    if (layers[i].type != "symbol") CHECK(i < index);
  }
  CHECK(layers[index].type == "symbol");
}

void BelowLabelsAnchorInLiberty() {
  const auto& liberty = style_fixtures::kLibertyLayers;
  Anchor anchor = ComputeAnchor(liberty, kBelowLabels);
  CHECK(!anchor.missing);
  // The 3D buildings, which are above the bridge layers that follow the
  // one-way arrows and below the last non-symbol layer boundary_disputed.
  CHECK(anchor.before == "building-3d");
  CHECK(liberty[IndexOf(liberty, anchor.before)].type == "fill-extrusion");
  CHECK(IndexOf(liberty, "road_one_way_arrow") <
        IndexOf(liberty, "bridge_motorway"));
  CHECK(IndexOf(liberty, "bridge_motorway") < IndexOf(liberty, anchor.before));
  CHECK(IndexOf(liberty, anchor.before) <
        IndexOf(liberty, "boundary_disputed"));
}

void BelowLabelsAnchorsOnTheFirstExtrusionBeforeTheLabels() {
  std::vector<StyleLayer> layers = {
      {"road", "line"},         {"arrow", "symbol"},
      {"building", "fill"},     {"building-3d", "fill-extrusion"},
      {"bridge", "line"},       {"towers-3d", "fill-extrusion"},
      {"boundary", "line"},     {"label", "symbol"}};
  CHECK((ComputeAnchor(layers, kBelowLabels) == Anchor{"building-3d", false}));
  // An extrusion among the labels is above the anchor and doesn't change it.
  std::vector<StyleLayer> extrusion_after = {
      {"road", "line"}, {"label", "symbol"}, {"building-3d", "fill-extrusion"},
      {"poi", "symbol"}};
  CHECK((ComputeAnchor(extrusion_after, kBelowLabels) ==
         Anchor{"building-3d", false}));
  // The last non-symbol layer is an extrusion: the overlay goes below it.
  std::vector<StyleLayer> extrusion_last = {
      {"road", "line"}, {"building-3d", "fill-extrusion"}};
  CHECK((ComputeAnchor(extrusion_last, kBelowLabels) ==
         Anchor{"building-3d", false}));
  std::vector<StyleLayer> overlay_extrusion = {
      {"road", "line"}, {"mapigrade-overlay-1-0", "fill-extrusion"},
      {"label", "symbol"}};
  CHECK((ComputeAnchor(overlay_extrusion, kBelowLabels) ==
         Anchor{"label", false}));
}

void BelowLabelsAnchorInBright() {
  const auto& bright = style_fixtures::kBrightLayers;
  Anchor anchor = ComputeAnchor(bright, kBelowLabels);
  CHECK(!anchor.missing);
  CHECK(IndexOf(bright, anchor.before) ==
        IndexOf(bright, "boundary_disputed") + 1);
  CHECK(anchor.before == "road_oneway");
  CheckBelowLabelsAnchor(bright, anchor.before);
}

void BelowLabelsAnchorInPositron() {
  const auto& positron = style_fixtures::kPositronLayers;
  Anchor anchor = ComputeAnchor(positron, kBelowLabels);
  CHECK(!anchor.missing);
  CHECK(IndexOf(positron, anchor.before) ==
        IndexOf(positron, "boundary_disputed") + 1);
  CHECK(anchor.before == "waterway_line_label");
  CheckBelowLabelsAnchor(positron, anchor.before);
}

void BelowLabelsWithOnlySymbolLayersIsBelowAll() {
  std::vector<StyleLayer> layers = {{"a", "symbol"}, {"b", "symbol"}};
  CHECK((ComputeAnchor(layers, kBelowLabels) == Anchor{"a", false}));
}

void BelowLabelsWithoutSymbolLayersIsTop() {
  std::vector<StyleLayer> layers = {{"a", "background"}, {"b", "line"}};
  CHECK((ComputeAnchor(layers, kBelowLabels) == Anchor{"", false}));
  CHECK((ComputeAnchor({}, kBelowLabels) == Anchor{"", false}));
}

void OverlayLayersAreIgnoredByPlacement() {
  // Overlay layers after the last style layer that isn't a symbol, and a line
  // overlay among the labels, change nothing.
  std::vector<StyleLayer> layers = {
      {"water", "fill"},           {"mapigrade-overlay-1-0", "line"},
      {"road", "line"},            {"mapigrade-overlay-2-0", "line"},
      {"mapigrade-overlay-2-1", "line"}, {"label", "symbol"},
      {"mapigrade-overlay-3-0", "line"}, {"poi", "symbol"}};
  CHECK((ComputeAnchor(layers, kBelowLabels) == Anchor{"label", false}));
  std::vector<StyleLayer> symbols_only = {{"mapigrade-overlay-1-0", "line"},
                                          {"label", "symbol"}};
  CHECK((ComputeAnchor(symbols_only, kBelowLabels) == Anchor{"label", false}));
  std::vector<StyleLayer> lines_then_overlay = {
      {"road", "line"}, {"mapigrade-overlay-1-0", "line"}};
  CHECK((ComputeAnchor(lines_then_overlay, kBelowLabels) == Anchor{"", false}));
  // An overlay layer can't be a belowLayer anchor.
  CHECK((ComputeAnchor(layers, BelowLayer("mapigrade-overlay-1-0")) ==
         Anchor{"", true}));
}

void OverlaySourceIndexParsesOnlyTheOverlaysSourceIds() {
  using map_texture::OverlaySourceIndex;
  CHECK(map_texture::OverlaySourceId(7, 0) == "mapigrade-overlay-7-source-0");
  CHECK(map_texture::OverlayLayerId(7, 0) == "mapigrade-overlay-7-0");
  CHECK(OverlaySourceIndex(7, "mapigrade-overlay-7-source-0") == 0);
  CHECK(OverlaySourceIndex(7, "mapigrade-overlay-7-source-12") == 12);
  CHECK(!OverlaySourceIndex(7, "mapigrade-overlay-7-0"));
  CHECK(!OverlaySourceIndex(7, "mapigrade-overlay-17-source-0"));
  CHECK(!OverlaySourceIndex(7, "mapigrade-overlay-7-source-"));
  CHECK(!OverlaySourceIndex(7, "mapigrade-overlay-7-source-01"));
  CHECK(!OverlaySourceIndex(7, "mapigrade-overlay-7-source-1x"));
  CHECK(!OverlaySourceIndex(7, "mapigrade-overlay-7-source-1234567890"));
  CHECK(!OverlaySourceIndex(7, ""));
}

void BelowLayerAnchorsOnThatLayer() {
  const auto& liberty = style_fixtures::kLibertyLayers;
  CHECK((ComputeAnchor(liberty, BelowLayer("water")) == Anchor{"water", false}));
  CHECK((ComputeAnchor(liberty, BelowLayer("background")) ==
         Anchor{"background", false}));
}

void MissingBelowLayerIsTopAndMissing() {
  const auto& liberty = style_fixtures::kLibertyLayers;
  CHECK((ComputeAnchor(liberty, BelowLayer("road-label")) == Anchor{"", true}));
  CHECK((ComputeAnchor({}, BelowLayer("water")) == Anchor{"", true}));
}

void TopIsEmptyAnchor() {
  CHECK((ComputeAnchor(style_fixtures::kLibertyLayers, kTop) ==
         Anchor{"", false}));
  CHECK((ComputeAnchor({}, kTop) == Anchor{"", false}));
}

// Layer plans (design D199): the resulting order after the plan's commands.

std::vector<std::string> OverlayLayerIds(int64_t id, size_t count) {
  std::vector<std::string> ids;
  for (size_t i = 0; i < count; ++i) ids.push_back(map_texture::OverlayLayerId(id, i));
  return ids;
}

OverlayLayout Layout(int64_t id, int64_t order, size_t layers = 2,
                     Placement placement = kBelowLabels) {
  return {id, {order, id}, placement, OverlayLayerIds(id, layers), false};
}

// Applies `plan` to `current` as the map thread's commands would, and returns
// the layer list that results.
std::vector<StyleLayer> Apply(const std::vector<StyleLayer>& current,
                              const LayerPlan& plan,
                              const std::vector<OverlayLayout>& overlays) {
  std::vector<StyleLayer> layers = current;
  auto remove = [&](const std::string& id) {
    std::erase_if(layers, [&](const StyleLayer& l) { return l.id == id; });
  };
  auto insert_before = [&](const std::string& id, const std::string& before) {
    auto at = before.empty()
                  ? layers.end()
                  : std::find_if(layers.begin(), layers.end(),
                                 [&](const StyleLayer& l) { return l.id == before; });
    CHECK(before.empty() || at != layers.end());
    layers.insert(at, {id, "line"});
  };
  for (const std::string& id : plan.remove_stale) remove(id);
  for (const auto& step : plan.steps) {
    auto overlay = std::find_if(overlays.begin(), overlays.end(),
                                [&](const OverlayLayout& o) { return o.id == step.id; });
    CHECK(overlay != overlays.end());
    for (const std::string& id : step.remove_first) remove(id);
    for (const std::string& id : overlay->layer_ids) {
      if (step.action == OverlayAction::kMove) remove(id);
      insert_before(id, step.before);
    }
  }
  return layers;
}

std::vector<std::string> Ids(const std::vector<StyleLayer>& layers) {
  std::vector<std::string> ids;
  for (const auto& layer : layers) ids.push_back(layer.id);
  return ids;
}

const std::vector<StyleLayer> kStyle = {
    {"background", "background"}, {"water", "fill"}, {"road", "line"},
    {"road_label", "symbol"}, {"poi", "symbol"}};

void SingleOverlayIsInstalledBeforeAnchor() {
  std::vector<OverlayLayout> overlays = {Layout(1, 0)};
  LayerPlan plan = PlanLayers(kStyle, overlays);
  CHECK(plan.remove_stale.empty());
  CHECK(plan.missing_layer_ids.empty());
  CHECK(plan.steps.size() == 1);
  CHECK(!plan.steps.empty() && plan.steps[0].action == OverlayAction::kInstall);
  CHECK(!plan.steps.empty() && plan.steps[0].before == "road_label");
  auto after = Apply(kStyle, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-1-1", "road_label", "poi"}));
  // Planned again against the result, nothing is left to do.
  CHECK(PlanLayers(after, overlays).steps.empty());
}

void OverlaysAtSameAnchorFollowOrderKey() {
  // Registered in the order 3, 1, 2; drawn in the order of their keys.
  std::vector<OverlayLayout> overlays = {Layout(3, 30, 1), Layout(1, 10, 1),
                                         Layout(2, 20, 1)};
  LayerPlan plan = PlanLayers(kStyle, overlays);
  auto after = Apply(kStyle, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-2-0", "mapigrade-overlay-3-0",
                           "road_label", "poi"}));
  CHECK(PlanLayers(after, overlays).steps.empty());
  // The same child index: the registration sequence number sets the order.
  std::vector<OverlayLayout> same_child = {Layout(2, 5, 1), Layout(1, 5, 1)};
  after = Apply(kStyle, PlanLayers(kStyle, same_child), same_child);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-2-0", "road_label", "poi"}));
}

void OverlayAddedLaterGoesBetweenExistingOnes() {
  std::vector<OverlayLayout> installed = {Layout(1, 10), Layout(3, 30)};
  auto current = Apply(kStyle, PlanLayers(kStyle, installed), installed);
  std::vector<OverlayLayout> overlays = installed;
  overlays.push_back(Layout(2, 20));
  LayerPlan plan = PlanLayers(current, overlays);
  // The installed overlays aren't added again.
  for (const auto& step : plan.steps) {
    CHECK((step.action == OverlayAction::kInstall) == (step.id == 2));
  }
  auto after = Apply(current, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-1-1", "mapigrade-overlay-2-0",
                           "mapigrade-overlay-2-1", "mapigrade-overlay-3-0",
                           "mapigrade-overlay-3-1", "road_label", "poi"}));
  CHECK(PlanLayers(after, overlays).steps.empty());
}

void OrderKeyChangeMovesLayers() {
  std::vector<OverlayLayout> overlays = {Layout(1, 10), Layout(2, 20)};
  auto current = Apply(kStyle, PlanLayers(kStyle, overlays), overlays);
  overlays[0].order = {30, 1};
  LayerPlan plan = PlanLayers(current, overlays);
  CHECK(!plan.steps.empty());
  for (const auto& step : plan.steps) {
    CHECK(step.action == OverlayAction::kMove);
    CHECK(step.remove_first.empty());
  }
  auto after = Apply(current, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-2-0",
                           "mapigrade-overlay-2-1", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-1-1", "road_label", "poi"}));
  CHECK(PlanLayers(after, overlays).steps.empty());
}

void OverlaysAtDifferentAnchorsAreIndependent() {
  std::vector<OverlayLayout> overlays = {
      Layout(1, 10, 1), Layout(2, 20, 1, BelowLayer("water")),
      Layout(3, 5, 1, kTop)};
  auto after = Apply(kStyle, PlanLayers(kStyle, overlays), overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "mapigrade-overlay-2-0", "water", "road",
                           "mapigrade-overlay-1-0", "road_label", "poi",
                           "mapigrade-overlay-3-0"}));
  // A change at one anchor doesn't change the others.
  overlays.push_back(Layout(4, 1, 1, kTop));
  LayerPlan plan = PlanLayers(after, overlays);
  for (const auto& step : plan.steps) CHECK(step.id == 3 || step.id == 4);
  after = Apply(after, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "mapigrade-overlay-2-0", "water", "road",
                           "mapigrade-overlay-1-0", "road_label", "poi",
                           "mapigrade-overlay-4-0", "mapigrade-overlay-3-0"}));
}

void ChangedLayersAreAddedAgain() {
  std::vector<OverlayLayout> overlays = {Layout(1, 10, 3)};
  auto current = Apply(kStyle, PlanLayers(kStyle, overlays), overlays);
  // Two layers instead of three: the third is stale, the two are replaced.
  overlays[0].layer_ids = OverlayLayerIds(1, 2);
  overlays[0].replace = true;
  LayerPlan plan = PlanLayers(current, overlays);
  CHECK((plan.remove_stale == std::vector<std::string>{"mapigrade-overlay-1-2"}));
  CHECK(plan.steps.size() == 1);
  CHECK(!plan.steps.empty() &&
        plan.steps[0].action == OverlayAction::kReplaceLayers);
  CHECK(!plan.steps.empty() &&
        (plan.steps[0].remove_first ==
         std::vector<std::string>{"mapigrade-overlay-1-0",
                                  "mapigrade-overlay-1-1"}));
  auto after = Apply(current, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-1-1", "road_label", "poi"}));
}

void PartiallyPresentOverlayIsCompleted() {
  // A failed add left one of two layers.
  std::vector<StyleLayer> current = kStyle;
  current.insert(current.begin() + 3, {"mapigrade-overlay-1-0", "line"});
  std::vector<OverlayLayout> overlays = {Layout(1, 10)};
  LayerPlan plan = PlanLayers(current, overlays);
  CHECK(plan.steps.size() == 1);
  CHECK(!plan.steps.empty() &&
        plan.steps[0].action == OverlayAction::kReplaceLayers);
  auto after = Apply(current, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-1-1", "road_label", "poi"}));
}

void RemovedOverlayLayersAreStale() {
  std::vector<OverlayLayout> overlays = {Layout(1, 10), Layout(2, 20)};
  auto current = Apply(kStyle, PlanLayers(kStyle, overlays), overlays);
  overlays.erase(overlays.begin());
  LayerPlan plan = PlanLayers(current, overlays);
  CHECK((plan.remove_stale == std::vector<std::string>{
                                  "mapigrade-overlay-1-0", "mapigrade-overlay-1-1"}));
  CHECK(plan.steps.empty());
  CHECK((Ids(Apply(current, plan, overlays)) ==
         std::vector<std::string>{"background", "water", "road",
                                  "mapigrade-overlay-2-0", "mapigrade-overlay-2-1",
                                  "road_label", "poi"}));
  CHECK(PlanLayers(current, {}).remove_stale.size() == 4);
}

void MissingBelowLayerIsPlacedOnTopAndReported() {
  std::vector<OverlayLayout> overlays = {
      Layout(1, 10, 1, BelowLayer("road-label")),
      Layout(2, 20, 1, BelowLayer("road-label")), Layout(3, 5, 1, kTop)};
  LayerPlan plan = PlanLayers(kStyle, overlays);
  CHECK((plan.missing_layer_ids == std::vector<std::string>{"road-label"}));
  auto after = Apply(kStyle, plan, overlays);
  CHECK((Ids(after) == std::vector<std::string>{
                           "background", "water", "road", "road_label", "poi",
                           "mapigrade-overlay-3-0", "mapigrade-overlay-1-0",
                           "mapigrade-overlay-2-0"}));
}

void OverlayWithoutLayersGetsNoStep() {
  std::vector<OverlayLayout> overlays = {Layout(1, 10, 0)};
  CHECK(PlanLayers(kStyle, overlays).steps.empty());
}

// The layer JSON array of map_texture_overlay_set_layers().

void JsonObjectArrayIsSplitIntoObjects() {
  using map_texture::SplitJsonObjectArray;
  auto empty = SplitJsonObjectArray(" [ ] ");
  CHECK(empty && empty->empty());
  auto two = SplitJsonObjectArray(
      R"( [{"id": "a", "filter": ["==", ["get", "r"], 0], "paint": {"line-color": "}]\""}} ,
      {"id":"b","layout":{}}] )");
  CHECK(two && two->size() == 2);
  if (two && two->size() == 2) {
    CHECK((*two)[0].front() == '{' && (*two)[0].back() == '}');
    CHECK((*two)[0].find("line-color") != std::string::npos);
    CHECK((*two)[1] == R"({"id":"b","layout":{}})");
  }
  CHECK(!SplitJsonObjectArray("{}"));
  CHECK(!SplitJsonObjectArray("[1]"));
  CHECK(!SplitJsonObjectArray(R"([{"id": "a"})"));
  CHECK(!SplitJsonObjectArray(R"([{"id": "a"},])"));
  CHECK(!SplitJsonObjectArray(R"([{"id": "a"}] x)"));
  CHECK(!SplitJsonObjectArray(""));
}

void JsonStringMemberIsFound() {
  using map_texture::JsonStringMember;
  std::string_view layer =
      R"({"type": "line", "source": {"nested": {"id": "wrong"}}, "ids": ["id"],
          "id": "mapigrade-overlay-7-1", "paint": {"line-width": 2}})";
  auto id = JsonStringMember(layer, "id");
  CHECK(id && *id == "mapigrade-overlay-7-1");
  auto type = JsonStringMember(layer, "type");
  CHECK(type && *type == "line");
  CHECK(!JsonStringMember(layer, "missing"));
  CHECK(!JsonStringMember(R"({"id": 7})", "id"));
  CHECK(!JsonStringMember(R"({"id": "a\"b"})", "id"));
  CHECK(!JsonStringMember(R"({"id" "a"})", "id"));
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
      {"BelowLabelsAnchorInLiberty", BelowLabelsAnchorInLiberty},
      {"BelowLabelsAnchorsOnTheFirstExtrusionBeforeTheLabels",
       BelowLabelsAnchorsOnTheFirstExtrusionBeforeTheLabels},
      {"BelowLabelsAnchorInBright", BelowLabelsAnchorInBright},
      {"BelowLabelsAnchorInPositron", BelowLabelsAnchorInPositron},
      {"BelowLabelsWithOnlySymbolLayersIsBelowAll",
       BelowLabelsWithOnlySymbolLayersIsBelowAll},
      {"BelowLabelsWithoutSymbolLayersIsTop", BelowLabelsWithoutSymbolLayersIsTop},
      {"OverlayLayersAreIgnoredByPlacement", OverlayLayersAreIgnoredByPlacement},
      {"OverlaySourceIndexParsesOnlyTheOverlaysSourceIds",
       OverlaySourceIndexParsesOnlyTheOverlaysSourceIds},
      {"BelowLayerAnchorsOnThatLayer", BelowLayerAnchorsOnThatLayer},
      {"MissingBelowLayerIsTopAndMissing", MissingBelowLayerIsTopAndMissing},
      {"TopIsEmptyAnchor", TopIsEmptyAnchor},
      {"SingleOverlayIsInstalledBeforeAnchor", SingleOverlayIsInstalledBeforeAnchor},
      {"OverlaysAtSameAnchorFollowOrderKey", OverlaysAtSameAnchorFollowOrderKey},
      {"OverlayAddedLaterGoesBetweenExistingOnes",
       OverlayAddedLaterGoesBetweenExistingOnes},
      {"OrderKeyChangeMovesLayers", OrderKeyChangeMovesLayers},
      {"OverlaysAtDifferentAnchorsAreIndependent",
       OverlaysAtDifferentAnchorsAreIndependent},
      {"ChangedLayersAreAddedAgain", ChangedLayersAreAddedAgain},
      {"PartiallyPresentOverlayIsCompleted", PartiallyPresentOverlayIsCompleted},
      {"RemovedOverlayLayersAreStale", RemovedOverlayLayersAreStale},
      {"MissingBelowLayerIsPlacedOnTopAndReported",
       MissingBelowLayerIsPlacedOnTopAndReported},
      {"OverlayWithoutLayersGetsNoStep", OverlayWithoutLayersGetsNoStep},
      {"JsonObjectArrayIsSplitIntoObjects", JsonObjectArrayIsSplitIntoObjects},
      {"JsonStringMemberIsFound", JsonStringMemberIsFound},
  };
  for (const auto& [name, test] : tests) {
    int before = failures;
    test();
    std::printf("%s %s\n", failures == before ? "PASS" : "FAIL", name);
  }
  std::printf("%d failure(s)\n", failures);
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
