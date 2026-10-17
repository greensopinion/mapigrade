// Commands from Dart to the map thread (design D5).
//
// Style loads, resizes, memory reduction, target tasks and dispose go into an
// ordered queue and are never dropped or reordered. Consecutive resizes are coalesced so that a window drag
// doesn't allocate a buffer set per intermediate size (D7). Camera updates go
// into a single slot where the latest update wins, with its sequence number
// (D125).
//
// All methods are safe to call from any thread.
#pragma once

#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <utility>

namespace map_texture {

struct Camera {
  double latitude = 0;
  double longitude = 0;
  double zoom = 0;
  double bearing = 0;

  bool operator==(const Camera&) const = default;
};

// A camera from Dart and the sequence number Dart assigned to it (design
// D125).
struct CameraUpdate {
  Camera camera;
  int64_t seq = 0;
};

struct Viewport {
  // Logical size in Flutter logical pixels.
  double logical_width = 0;
  double logical_height = 0;
  double pixel_ratio = 1;

  bool operator==(const Viewport&) const = default;
};

struct Command {
  enum class Kind {
    kStyleUrl,
    kStyleJson,
    kResize,
    kReduceMemoryUse,
    // Work of the platform render target on the map thread.
    kTargetTask,
    kDispose,
  };

  Kind kind;
  // The URL for kStyleUrl, the JSON document for kStyleJson.
  std::string text;
  // Set for kResize.
  Viewport viewport;
  // Set for kTargetTask.
  std::function<void()> task;

  static Command StyleUrl(std::string url) {
    return {Kind::kStyleUrl, std::move(url), {}, {}};
  }
  static Command StyleJson(std::string json) {
    return {Kind::kStyleJson, std::move(json), {}, {}};
  }
  static Command Resize(Viewport viewport) {
    return {Kind::kResize, {}, viewport, {}};
  }
  static Command ReduceMemoryUse() {
    return {Kind::kReduceMemoryUse, {}, {}, {}};
  }
  static Command TargetTask(std::function<void()> task) {
    return {Kind::kTargetTask, {}, {}, std::move(task)};
  }
  static Command Dispose() { return {Kind::kDispose, {}, {}, {}}; }
};

class CommandQueue {
 public:
  void Push(Command command) {
    std::lock_guard lock(mutex_);
    if (command.kind == Command::Kind::kResize && !commands_.empty() &&
        commands_.back().kind == Command::Kind::kResize) {
      commands_.back() = std::move(command);
      return;
    }
    commands_.push_back(std::move(command));
  }

  // Removes and returns all queued commands in the order they were pushed.
  std::deque<Command> TakeAll() {
    std::lock_guard lock(mutex_);
    return std::exchange(commands_, {});
  }

  void SetCamera(const Camera& camera, int64_t seq) {
    std::lock_guard lock(mutex_);
    camera_ = CameraUpdate{camera, seq};
  }

  // Returns the camera set since the last call, or nothing if no camera was
  // set since then.
  std::optional<CameraUpdate> TakeCamera() {
    std::lock_guard lock(mutex_);
    return std::exchange(camera_, std::nullopt);
  }

 private:
  std::mutex mutex_;
  std::deque<Command> commands_;
  std::optional<CameraUpdate> camera_;
};

}  // namespace map_texture
