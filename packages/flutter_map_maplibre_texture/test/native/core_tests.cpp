// Unit tests for CommandQueue and BufferState.
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <thread>
#include <vector>

#include "buffer_state.h"
#include "command_queue.h"

using map_texture::BufferState;
using map_texture::Camera;
using map_texture::Command;
using map_texture::CommandQueue;
using map_texture::FrameInfo;
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

int PresentIndex(BufferState& state) {
  return state.Present([](const BufferState::Presented&) {}).index;
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
  for (int i = 0; i < 100; ++i) queue.SetCamera({0, 0, double(i), 0});
  auto camera = queue.TakeCamera();
  CHECK(camera.has_value());
  CHECK(camera->zoom == 99);
  CHECK(!queue.TakeCamera().has_value());
}

void CameraFromManyThreadsCoalescesToOne() {
  CommandQueue queue;
  std::vector<std::thread> threads;
  for (int t = 0; t < 4; ++t) {
    threads.emplace_back([&queue, t] {
      for (int i = 0; i < 1000; ++i) queue.SetCamera({double(t), 0, 0, 0});
    });
  }
  for (auto& thread : threads) thread.join();
  CHECK(queue.TakeCamera().has_value());
  CHECK(!queue.TakeCamera().has_value());
}

void EmptyStateHasNothingToPresent() {
  BufferState state;
  auto presented = state.Present([](const BufferState::Presented&) {});
  CHECK(presented.index == -1);
  CHECK(!presented.is_new);
  CHECK(state.AcquireFree(-1) == 0);
}

void AcquirePrefersCurrentTarget() {
  BufferState state;
  CHECK(state.AcquireFree(2) == 2);
}

void PublishedBufferIsNotFree() {
  BufferState state;
  state.Publish(0, Frame(1));
  CHECK(state.latest() == 0);
  int next = state.AcquireFree(0);
  CHECK(next != 0);
  CHECK(next >= 0);
}

void PresentedBufferIsNotFree() {
  BufferState state;
  state.Publish(0, Frame(1));
  CHECK(PresentIndex(state) == 0);
  state.Publish(1, Frame(2));
  // 0 is presented, 1 is latest, so only 2 is free.
  CHECK(state.AcquireFree(0) == 2);
  CHECK(state.AcquireFree(1) == 2);
}

void PresentReportsNewFramesOnce() {
  BufferState state;
  state.Publish(1, Frame(7));
  auto first = state.Present([](const BufferState::Presented&) {});
  CHECK(first.index == 1);
  CHECK(first.info.frame_id == 7);
  CHECK(first.is_new);
  auto again = state.Present([](const BufferState::Presented&) {});
  CHECK(again.index == 1);
  CHECK(!again.is_new);
}

void PresentRunsCallbackWithResult() {
  BufferState state;
  state.Publish(2, Frame(3));
  int seen = -1;
  state.Present([&](const BufferState::Presented& p) { seen = p.index; });
  CHECK(seen == 2);
}

void ThreeBuffersAlwaysHaveAFreeBuffer() {
  BufferState state;
  int current = state.AcquireFree(-1);
  for (uint64_t frame = 1; frame <= 50; ++frame) {
    current = state.AcquireFree(current);
    CHECK(current >= 0);
    state.Publish(current, Frame(frame));
    if (frame % 3 == 0) PresentIndex(state);
  }
}

void TwoBuffersSkipWhenNoneIsFree() {
  BufferState state(2);
  state.Publish(0, Frame(1));
  PresentIndex(state);  // 0 is latest and presented.
  CHECK(state.AcquireFree(0) == 1);
  state.Publish(1, Frame(2));  // 0 presented, 1 latest.
  CHECK(state.AcquireFree(1) == -1);
  PresentIndex(state);  // 1 is latest and presented, 0 is free again.
  CHECK(state.AcquireFree(1) == 0);
}

void LatestPresentedPacesRendering() {
  BufferState state;
  CHECK(state.LatestPresented());  // No frame yet.
  state.Publish(0, Frame(1));
  CHECK(!state.LatestPresented());
  PresentIndex(state);
  CHECK(state.LatestPresented());
  state.Publish(1, Frame(2));
  CHECK(!state.LatestPresented());
}

void ResetFreesAllBuffers() {
  BufferState state;
  state.Publish(0, Frame(1));
  PresentIndex(state);
  state.Publish(1, Frame(2));
  int latest_seen = -2;
  state.WithLock([&](int latest) {
    latest_seen = latest;
    state.ResetLocked();
  });
  CHECK(latest_seen == 1);
  CHECK(state.latest() == -1);
  CHECK(PresentIndex(state) == -1);
  CHECK(state.AcquireFree(0) == 0);
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
      {"EmptyStateHasNothingToPresent", EmptyStateHasNothingToPresent},
      {"AcquirePrefersCurrentTarget", AcquirePrefersCurrentTarget},
      {"PublishedBufferIsNotFree", PublishedBufferIsNotFree},
      {"PresentedBufferIsNotFree", PresentedBufferIsNotFree},
      {"PresentReportsNewFramesOnce", PresentReportsNewFramesOnce},
      {"PresentRunsCallbackWithResult", PresentRunsCallbackWithResult},
      {"ThreeBuffersAlwaysHaveAFreeBuffer", ThreeBuffersAlwaysHaveAFreeBuffer},
      {"TwoBuffersSkipWhenNoneIsFree", TwoBuffersSkipWhenNoneIsFree},
      {"LatestPresentedPacesRendering", LatestPresentedPacesRendering},
      {"ResetFreesAllBuffers", ResetFreesAllBuffers},
  };
  for (const auto& [name, test] : tests) {
    int before = failures;
    test();
    std::printf("%s %s\n", failures == before ? "PASS" : "FAIL", name);
  }
  std::printf("%d failure(s)\n", failures);
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
