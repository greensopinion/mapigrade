// Commands from Dart to the map thread.
//
// Style loads, resizes, memory reduction, feature state, overlays, target
// tasks and dispose go into an ordered queue and are never dropped or
// reordered. Consecutive resizes are coalesced so that a window drag doesn't
// allocate a buffer set per intermediate size. Camera updates go into a single
// slot where the latest update wins, with its sequence number.
//
// All methods are safe to call from any thread.
#pragma once

#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "overlay.h"

namespace map_texture {

// GeoJSON that map_texture_overlay_set_source() prepared; defined and
// released in map_texture.h.
struct PreparedGeoJson;

struct Camera {
  double latitude = 0;
  double longitude = 0;
  double zoom = 0;
  double bearing = 0;
  double pitch = 0;

  bool operator==(const Camera&) const = default;
};

struct CameraUpdate {
  Camera camera;
  int64_t seq = 0;
  // When the camera was set (steady clock, ns), or 0 if unknown.
  int64_t set_at_ns = 0;
};

struct Viewport {
  double logical_width = 0;
  double logical_height = 0;
  double pixel_ratio = 1;

  bool operator==(const Viewport&) const = default;
};

// The features whose feature state a command sets or removes.
struct FeatureStateTarget {
  std::string source_id;
  std::optional<std::string> source_layer_id;
  // Required to set state. To remove, nothing removes the state of every
  // feature of the source or source layer.
  std::optional<std::string> feature_id;
  // To remove, the one key to remove; nothing removes every key.
  std::optional<std::string> key;
};

// An overlay command (design D198): the overlay; for kOverlaySetSource and
// kOverlayRemoveSource the source's index, and for the former its options and
// prepared data; for kOverlaySetLayers its style layers as JSON objects, the
// indexes of the sources they name, placement and order key.
struct OverlayCommand {
  int64_t id = 0;
  int32_t source_index = 0;
  int32_t source_options = 0;
  std::shared_ptr<PreparedGeoJson> data;
  std::vector<std::string> layers;
  std::vector<int32_t> layer_sources;
  Placement placement;
  OrderKey order;
};

struct Command {
  enum class Kind {
    kStyleUrl,
    kStyleJson,
    kResize,
    kReduceMemoryUse,
    kSetFeatureState,
    kRemoveFeatureState,
    kOverlaySetSource,
    kOverlayRemoveSource,
    kOverlaySetLayers,
    kOverlayRemove,
    // Work of the platform render target on the map thread.
    kTargetTask,
    kDispose,
  };

  Kind kind;
  // The URL for kStyleUrl, the JSON document for kStyleJson, the state JSON
  // object for kSetFeatureState.
  std::string text;
  // Set for kResize.
  Viewport viewport;
  // Set for kTargetTask.
  std::function<void()> task;
  // Set for kSetFeatureState and kRemoveFeatureState.
  FeatureStateTarget feature;
  // Set for the kOverlay* kinds.
  OverlayCommand overlay;

  static Command StyleUrl(std::string url) {
    return {Kind::kStyleUrl, std::move(url), {}, {}, {}, {}};
  }
  static Command StyleJson(std::string json) {
    return {Kind::kStyleJson, std::move(json), {}, {}, {}, {}};
  }
  static Command Resize(Viewport viewport) {
    return {Kind::kResize, {}, viewport, {}, {}, {}};
  }
  static Command ReduceMemoryUse() {
    return {Kind::kReduceMemoryUse, {}, {}, {}, {}, {}};
  }
  static Command SetFeatureState(FeatureStateTarget feature,
                                 std::string state) {
    return {Kind::kSetFeatureState, std::move(state), {}, {},
            std::move(feature), {}};
  }
  static Command RemoveFeatureState(FeatureStateTarget feature) {
    return {Kind::kRemoveFeatureState, {}, {}, {}, std::move(feature), {}};
  }
  static Command OverlaySetSource(int64_t id, int32_t source_index,
                                  int32_t source_options,
                                  std::shared_ptr<PreparedGeoJson> data) {
    return {Kind::kOverlaySetSource, {}, {}, {}, {},
            {id, source_index, source_options, std::move(data), {}, {}, {}, {}}};
  }
  static Command OverlayRemoveSource(int64_t id, int32_t source_index) {
    return {Kind::kOverlayRemoveSource, {}, {}, {}, {},
            {id, source_index, 0, nullptr, {}, {}, {}, {}}};
  }
  static Command OverlaySetLayers(int64_t id, std::vector<std::string> layers,
                                  std::vector<int32_t> layer_sources,
                                  Placement placement, OrderKey order) {
    return {Kind::kOverlaySetLayers, {}, {}, {}, {},
            {id, 0, 0, nullptr, std::move(layers), std::move(layer_sources),
             std::move(placement), order}};
  }
  static Command OverlayRemove(int64_t id) {
    return {Kind::kOverlayRemove, {}, {}, {}, {}, {id, 0, 0, nullptr, {}, {}, {}, {}}};
  }
  static Command TargetTask(std::function<void()> task) {
    return {Kind::kTargetTask, {}, {}, std::move(task), {}, {}};
  }
  static Command Dispose() { return {Kind::kDispose, {}, {}, {}, {}, {}}; }
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

  std::deque<Command> TakeAll() {
    std::lock_guard lock(mutex_);
    return std::exchange(commands_, {});
  }

  bool DisposeQueued() {
    std::lock_guard lock(mutex_);
    for (const Command& command : commands_) {
      if (command.kind == Command::Kind::kDispose) return true;
    }
    return false;
  }

  void SetCamera(const Camera& camera, int64_t seq, int64_t set_at_ns = 0) {
    std::lock_guard lock(mutex_);
    camera_ = CameraUpdate{camera, seq, set_at_ns};
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
