// Unit tests for CommandQueue, BufferState and RenderGate.
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <thread>
#include <vector>

#include "buffer_state.h"
#include "command_queue.h"
#include "render_gate.h"

using map_texture::BufferState;
using map_texture::Camera;
using map_texture::Command;
using map_texture::CommandQueue;
using map_texture::FrameInfo;
using map_texture::RenderGate;
using Slot = map_texture::BufferState::Slot;
using map_texture::Viewport;

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
  CHECK(state.Select(0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
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
  CHECK(state.Select(0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
  // Neither has been presented, so a raster of either may still run.
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(state.slot(1) == Slot::kHeld);
}

void PresentedSlotStaysHeldUntilAnotherSlotIsPresented() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.Select(0, 1));
  CHECK(PresentIndex(state, 0) == 0);
  // Presenting it again, or a slot Dart didn't choose, frees nothing.
  CHECK(PresentIndex(state, 0) == 0);
  CHECK(PresentIndex(state, 2) == -1);
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PresentIndex(state, 1) == 1);
  CHECK(state.slot(0) == Slot::kFree);
}

void SlotChosenAgainStaysHeld() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.Select(0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
  // Dart chooses slot 0 again after slot 1; presenting 1 doesn't free 0.
  CHECK(state.Select(0, 1));
  CHECK(PresentIndex(state, 1) == 1);
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PresentIndex(state, 0) == 0);
  CHECK(state.slot(1) == Slot::kFree);
}

void RepeatedChoiceCountsOnce() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.Select(0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
  CHECK(state.Select(1, 2));
  CHECK(state.Select(1, 2));
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
  // The replaced frame can't be chosen any more.
  CHECK(!state.Select(0, 1));
  CHECK(state.slot(0) == Slot::kFree);
}

void SelectingSlotThatIsNotReadyChangesNothing() {
  BufferState state;
  CHECK(!state.Select(0, 1));
  CHECK(state.slot(0) == Slot::kFree);
  int index = state.AcquireFree(-1);
  CHECK(!state.Select(index, 0));
  CHECK(state.slot(index) == Slot::kRendering);
  state.Publish(index, Frame(5));
  // A different frame id, as after a resize, changes nothing.
  CHECK(!state.Select(index, 4));
  CHECK(state.slot(index) == Slot::kReady);
  CHECK(!state.Select(-1, 5));
  CHECK(!state.Select(map_texture::kMaxBufferCount, 5));
  CHECK(state.LatestReadyChosen() == false);
}

void PresentReportsNewFramesOnce() {
  BufferState state;
  CHECK(PublishAt(state, 1, 7));
  CHECK(state.Select(1, 7));
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
  CHECK(state.Select(2, 3));
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
    CHECK(state.Select(index, id));
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
      CHECK(state.Select(ready, ready_frame));
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
    CHECK(state.Select(index, frame));
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
    CHECK(state.Select(slot, slot + 1));
    CHECK(state.slot(0) == (slot < 3 ? Slot::kHeld : Slot::kFree));
  }
  CHECK(state.slot(1) == Slot::kHeld);
  CHECK(state.slot(2) == Slot::kHeld);
  CHECK(state.slot(3) == Slot::kHeld);
}

void RepeatedChoiceDoesNotCountWithLaterChoices() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.Select(0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
  CHECK(PublishAt(state, 2, 3));
  for (int i = 0; i < 5; ++i) CHECK(state.Select(2, 3));
  CHECK(state.slot(0) == Slot::kHeld);
  CHECK(PublishAt(state, 3, 4));
  CHECK(state.Select(3, 4));
  CHECK(state.slot(0) == Slot::kFree);
  CHECK(state.slot(1) == Slot::kHeld);
}

void PresentFreesNothingWithLaterChoices() {
  BufferState state(map_texture::kChoiceReleasedBufferCount,
                    BufferState::ReleaseRule::kLaterChoices);
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.Select(0, 1));
  CHECK(PublishAt(state, 1, 2));
  CHECK(state.Select(1, 2));
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
        CHECK(state.Select(i, queued_frame - 1));
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
  CHECK(state.Select(1, 2));
  for (int slot = 2; slot < 5; ++slot) {
    CHECK(PublishAt(state, slot, slot + 1));
    CHECK(state.Select(slot, slot + 1));
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
  CHECK(state.Select(0, 1));
  CHECK(state.LatestReadyChosen());
  CHECK(PublishAt(state, 1, 2));
  CHECK(!state.LatestReadyChosen());
}

void ResetFreesAllSlots() {
  BufferState state;
  CHECK(PublishAt(state, 0, 1));
  CHECK(state.Select(0, 1));
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
  CHECK(!state.Select(1, 2));
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
      {"SlotChosenAgainStaysHeld", SlotChosenAgainStaysHeld},
      {"RepeatedChoiceCountsOnce", RepeatedChoiceCountsOnce},
      {"ReplacedReadyFrameFreesItsSlot", ReplacedReadyFrameFreesItsSlot},
      {"SelectingSlotThatIsNotReadyChangesNothing", SelectingSlotThatIsNotReadyChangesNothing},
      {"PresentReportsNewFramesOnce", PresentReportsNewFramesOnce},
      {"PresentRunsCallbackWithResult", PresentRunsCallbackWithResult},
      {"NewFramesHaveIncreasingDisplayTime", NewFramesHaveIncreasingDisplayTime},
      {"FourSlotsAlwaysHaveAFreeSlot", FourSlotsAlwaysHaveAFreeSlot},
      {"NoFreeSlotWithoutPresent", NoFreeSlotWithoutPresent},
      {"HeldUntilThreeLaterChoices", HeldUntilThreeLaterChoices},
      {"RepeatedChoiceDoesNotCountWithLaterChoices", RepeatedChoiceDoesNotCountWithLaterChoices},
      {"PresentFreesNothingWithLaterChoices", PresentFreesNothingWithLaterChoices},
      {"SixSlotsAlwaysHaveAFreeSlotWithLaterChoices", SixSlotsAlwaysHaveAFreeSlotWithLaterChoices},
      {"FreedSlotsAreReported", FreedSlotsAreReported},
      {"LatestReadyChosenPacesRendering", LatestReadyChosenPacesRendering},
      {"ResetFreesAllSlots", ResetFreesAllSlots},
      {"ReduceMemoryUseKeepsOrder", ReduceMemoryUseKeepsOrder},
      {"GateAllowsRendersUntilPaused", GateAllowsRendersUntilPaused},
      {"PauseWaitsForRenderInProgress", PauseWaitsForRenderInProgress},
      {"PauseWithoutRenderReturnsAtOnce", PauseWithoutRenderReturnsAtOnce},
  };
  for (const auto& [name, test] : tests) {
    int before = failures;
    test();
    std::printf("%s %s\n", failures == before ? "PASS" : "FAIL", name);
  }
  std::printf("%d failure(s)\n", failures);
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
