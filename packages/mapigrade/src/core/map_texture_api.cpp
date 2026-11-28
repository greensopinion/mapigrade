#include "map_texture_api.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "map_texture.h"

namespace {

std::optional<std::string> Optional(const char* text) {
  if (text == nullptr) return std::nullopt;
  return std::string(text);
}

using map_texture::MapTexture;

// Live maps by handle. A disposed handle is removed, so later calls with it
// find nothing and return MAP_TEXTURE_ERROR_DISPOSED.
std::mutex registry_mutex;
std::unordered_map<int64_t, std::shared_ptr<MapTexture>>& Registry() {
  static auto* registry =
      new std::unordered_map<int64_t, std::shared_ptr<MapTexture>>();
  return *registry;
}
int64_t next_handle = 1;
// Guarded by registry_mutex.
bool all_paused = false;
// The maximum size in bytes of the tile cache for maps created next, or -1 if
// Dart hasn't set one; guarded by registry_mutex.
int64_t maximum_cache_size = -1;

// Copies and validates the rules of map_texture_create(). On failure, `error`
// names the header without its value.
bool ReadHeaderRules(const char* const* strings, const int32_t* counts,
                     int32_t rule_count,
                     std::vector<map_texture::HttpHeaderRule>* rules,
                     std::string* error) {
  if (rule_count < 0) {
    *error = "rule_count is negative";
    return false;
  }
  if (rule_count > 0 && (strings == nullptr || counts == nullptr)) {
    *error = "header rules are null";
    return false;
  }
  size_t next = 0;
  for (int32_t i = 0; i < rule_count; ++i) {
    if (counts[i] < 0) {
      *error = "a header count is negative";
      return false;
    }
    map_texture::HttpHeaderRule rule;
    const char* url = strings[next++];
    if (url == nullptr) {
      *error = "a rule URL is null";
      return false;
    }
    rule.url = url;
    for (int32_t j = 0; j < counts[i]; ++j) {
      const char* name = strings[next++];
      const char* value = strings[next++];
      if (name == nullptr || value == nullptr) {
        *error = "a header name or value is null";
        return false;
      }
      // The runtime validates the headers when the map thread registers the
      // rules, and map creation fails with its diagnostic.
      rule.headers.push_back({name, value});
    }
    rules->push_back(std::move(rule));
  }
  return true;
}

bool Finite(std::initializer_list<double> values) {
  for (double value : values) {
    if (!std::isfinite(value)) return false;
  }
  return true;
}

// The camera of `camera`, or nothing for a value that isn't finite or a field
// that isn't a MAP_TEXTURE_CAMERA_* bit.
std::optional<map_texture::Camera> CameraOf(const map_texture_camera& camera) {
  constexpr int32_t kFields =
      MAP_TEXTURE_CAMERA_CENTER | MAP_TEXTURE_CAMERA_ZOOM |
      MAP_TEXTURE_CAMERA_BEARING | MAP_TEXTURE_CAMERA_PITCH |
      MAP_TEXTURE_CAMERA_CENTER_ALTITUDE | MAP_TEXTURE_CAMERA_PADDING |
      MAP_TEXTURE_CAMERA_ROLL | MAP_TEXTURE_CAMERA_FIELD_OF_VIEW;
  if ((camera.fields & ~kFields) != 0 ||
      !Finite({camera.latitude, camera.longitude, camera.center_altitude,
               camera.padding_top, camera.padding_left, camera.padding_bottom,
               camera.padding_right, camera.zoom, camera.bearing, camera.pitch,
               camera.roll, camera.field_of_view})) {
    return std::nullopt;
  }
  return map_texture::Camera{camera.latitude,
                             camera.longitude,
                             camera.zoom,
                             camera.bearing,
                             camera.pitch,
                             camera.center_altitude,
                             {camera.padding_top, camera.padding_left,
                              camera.padding_bottom, camera.padding_right},
                             camera.roll,
                             camera.field_of_view};
}

// The limits of `limits`, or nothing for values that aren't finite or ranges
// whose minimum is above their maximum.
std::optional<map_texture::CameraLimits> LimitsOf(
    const map_texture_limits& limits) {
  if (!Finite({limits.min_zoom, limits.max_zoom, limits.min_pitch,
               limits.max_pitch, limits.south, limits.west, limits.north,
               limits.east}) ||
      limits.min_zoom > limits.max_zoom || limits.min_pitch > limits.max_pitch ||
      (limits.has_bounds != 0 && limits.south > limits.north)) {
    return std::nullopt;
  }
  return map_texture::CameraLimits{limits.min_zoom,  limits.max_zoom,
                                   limits.min_pitch, limits.max_pitch,
                                   limits.has_bounds != 0, limits.south,
                                   limits.west,      limits.north,
                                   limits.east};
}

mln_momentum_decay Decay(const map_texture_gesture_options& options) {
  mln_momentum_decay decay{};
  decay.fields = MLN_MOMENTUM_DECAY_MODEL;
  decay.model = static_cast<mln_momentum_decay_model>(options.momentum_model);
  if (decay.model == MLN_MOMENTUM_DECAY_MODEL_FRICTION) {
    decay.fields |= MLN_MOMENTUM_DECAY_HALF_LIFE_MS;
    decay.half_life_ms = options.half_life_ms;
  }
  return decay;
}

mln_gesture_axis_options Axis(bool enabled,
                              const map_texture_gesture_options& options) {
  mln_gesture_axis_options axis{};
  axis.fields = MLN_GESTURE_AXIS_OPTION_ENABLED |
                MLN_GESTURE_AXIS_OPTION_GLIDES |
                MLN_GESTURE_AXIS_OPTION_MOMENTUM;
  axis.enabled = enabled;
  axis.glides = options.glides != 0;
  axis.momentum = Decay(options);
  return axis;
}

// The FFI's options for `options` (design D240).
mln_gesture_options GestureOptionsOf(
    const map_texture_gesture_options& options) {
  mln_gesture_options out{};
  out.size = sizeof(out);
  out.fields =
      MLN_GESTURE_OPTION_DOUBLE_TAP_ZOOM | MLN_GESTURE_OPTION_TWO_FINGER_TAP_ZOOM;
  out.double_tap_zoom = options.double_tap_zoom;
  out.two_finger_tap_zoom = options.two_finger_tap_zoom;
  out.pan.fields = MLN_GESTURE_PAN_OPTION_ENABLED |
                   MLN_GESTURE_PAN_OPTION_GLIDES |
                   MLN_GESTURE_PAN_OPTION_MOMENTUM;
  out.pan.enabled = options.pan != 0;
  out.pan.glides = options.glides != 0;
  out.pan.momentum = Decay(options);
  out.zoom = Axis(options.zoom != 0, options);
  out.bearing = Axis(options.rotate != 0, options);
  out.bearing.fields |= MLN_GESTURE_AXIS_OPTION_SNAPS;
  out.bearing.snaps = options.snap_to_north != 0;
  out.pitch = Axis(options.pitch != 0, options);
  return out;
}

mln_gesture_input GestureInputOf(const map_texture_gesture_input& input) {
  mln_gesture_input out{};
  out.size = sizeof(out);
  out.type = static_cast<mln_gesture_input_type>(input.type);
  mln_screen_point position{input.x, input.y};
  uint32_t id = static_cast<uint32_t>(input.pointer_id);
  switch (out.type) {
    case MLN_GESTURE_INPUT_POINTER_DOWN:
      out.data.pointer_down = {id, static_cast<mln_pointer_kind>(input.pointer_kind),
                               position,
                               static_cast<mln_gesture_modes>(input.modes)};
      break;
    case MLN_GESTURE_INPUT_POINTER_MOVE:
      out.data.pointer_move = {id, position};
      break;
    case MLN_GESTURE_INPUT_POINTER_UP:
      out.data.pointer_up = {id, position};
      break;
    case MLN_GESTURE_INPUT_POINTER_CANCEL:
      out.data.pointer_cancel = {id, position};
      break;
    case MLN_GESTURE_INPUT_MODES:
      out.data.modes = static_cast<mln_gesture_modes>(input.modes);
      break;
    case MLN_GESTURE_INPUT_DELTA:
      out.data.delta = {position,     input.discrete != 0,
                        {input.pan_x, input.pan_y},
                        input.zoom,   input.bearing,
                        input.pitch};
      break;
    case MLN_GESTURE_INPUT_PINCH:
      out.data.pinch = {position, input.scale, input.rotation,
                        static_cast<mln_pinch_phase>(input.phase)};
      break;
  }
  return out;
}

void GestureResultOf(const mln_gesture_result& result,
                     map_texture_gesture_result* out) {
  *out = {};
  out->handled = result.handled ? 1 : 0;
  out->next_tick = static_cast<int32_t>(result.next_tick);
  out->next_tick_ms = result.next_tick_ms;
  out->box_zoom_active = result.box_zoom_active ? 1 : 0;
  out->box_min_x = result.box_zoom.min.x;
  out->box_min_y = result.box_zoom.min.y;
  out->box_max_x = result.box_zoom.max.x;
  out->box_max_y = result.box_zoom.max.y;
  size_t count = std::min<size_t>(result.event_count, 4);
  out->event_count = static_cast<int32_t>(count);
  for (size_t i = 0; i < count; ++i) {
    const mln_gesture_event& event = result.events[i];
    map_texture_gesture_event& flat = out->events[i];
    flat.type = static_cast<int32_t>(event.type);
    if (event.type == MLN_GESTURE_EVENT_NOTCH) {
      flat.axis = static_cast<int32_t>(event.data.notch.axis);
      flat.kind = static_cast<int32_t>(event.data.notch.kind);
      flat.value = event.data.notch.value;
    } else {
      // Every other event is a tap of some kind.
      flat.pointer_id = static_cast<int32_t>(event.data.tap.id);
      flat.x = event.data.tap.position.x;
      flat.y = event.data.tap.position.y;
    }
  }
}

int32_t StatusCode(mln_status status) {
  if (status == MLN_STATUS_OK) return MAP_TEXTURE_OK;
  return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
}

std::shared_ptr<MapTexture> Find(int64_t handle) {
  std::lock_guard lock(registry_mutex);
  auto it = Registry().find(handle);
  return it == Registry().end() ? nullptr : it->second;
}

}  // namespace

namespace map_texture {

void SetAllPaused(bool paused) {
  std::lock_guard lock(registry_mutex);
  all_paused = paused;
  for (auto& [handle, texture] : Registry()) texture->SetPaused(paused);
}

void ReduceAllMemoryUse() {
  std::lock_guard lock(registry_mutex);
  for (auto& [handle, texture] : Registry()) texture->ReduceMemoryUse();
}

void DisposeEngineMaps(int64_t engine) {
  std::vector<std::shared_ptr<MapTexture>> textures;
  {
    std::lock_guard lock(registry_mutex);
    for (auto it = Registry().begin(); it != Registry().end();) {
      if (it->second->engine() == engine) {
        textures.push_back(std::move(it->second));
        it = Registry().erase(it);
      } else {
        ++it;
      }
    }
  }
  // Outside the lock, as in map_texture_dispose().
  for (auto& texture : textures) texture->Dispose();
  // The textures are unregistered while the engine is attached, including
  // those of maps that Dart disposed before.
  FinishReleases(
      [engine](const MapTexture& texture) { return texture.engine() == engine; });
}

}  // namespace map_texture

extern "C" {

int64_t map_texture_create(int64_t engine, double pixel_ratio,
                           int32_t copy_free,
                           map_texture_event_callback callback,
                           const char* const* header_strings,
                           const int32_t* header_counts, int32_t rule_count,
                           const map_texture_camera* initial_camera,
                           const map_texture_limits* limits,
                           char** out_error) {
  if (out_error != nullptr) *out_error = nullptr;
  auto fail = [out_error](int64_t error, const std::string& message) {
    if (out_error != nullptr) *out_error = strdup(message.c_str());
    return error;
  };
  if (callback == nullptr) {
    return fail(MAP_TEXTURE_ERROR_INVALID_ARGUMENT, "callback is null");
  }
  std::vector<map_texture::HttpHeaderRule> rules;
  std::string error;
  if (!ReadHeaderRules(header_strings, header_counts, rule_count, &rules,
                       &error)) {
    return fail(MAP_TEXTURE_ERROR_INVALID_ARGUMENT, error);
  }
  std::optional<map_texture::OwnedCamera> owned;
  if (initial_camera != nullptr) {
    auto camera = CameraOf(*initial_camera);
    auto camera_limits =
        limits != nullptr ? LimitsOf(*limits) : std::nullopt;
    if (!camera) {
      return fail(MAP_TEXTURE_ERROR_INVALID_ARGUMENT, "invalid initial camera");
    }
    if (!camera_limits) {
      return fail(MAP_TEXTURE_ERROR_INVALID_ARGUMENT, "invalid camera limits");
    }
    owned = map_texture::OwnedCamera{
        *camera, static_cast<uint32_t>(initial_camera->fields), *camera_limits};
  }
  int64_t handle;
  std::optional<uint64_t> cache_size;
  {
    std::lock_guard lock(registry_mutex);
    handle = next_handle++;
    if (maximum_cache_size >= 0) cache_size = maximum_cache_size;
  }
  auto texture = MapTexture::Create(handle, engine, pixel_ratio, copy_free != 0,
                                    cache_size, std::move(rules), callback,
                                    &error, owned);
  if (!texture) return fail(MAP_TEXTURE_ERROR_CREATE_FAILED, error);
  std::lock_guard lock(registry_mutex);
  // The map can't have rendered yet: its render session is attached by the
  // first resize, which needs the handle returned here.
  if (all_paused) texture->SetPaused(true);
  Registry()[handle] = std::move(texture);
  return handle;
}

void map_texture_string_free(char* string) { std::free(string); }

int32_t map_texture_set_maximum_cache_size(int64_t bytes) {
  if (bytes < 0) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  std::lock_guard lock(registry_mutex);
  maximum_cache_size = bytes;
  return MAP_TEXTURE_OK;
}

int32_t map_texture_texture_ids(int64_t handle, int64_t* out_ids,
                                int32_t capacity) {
  if (capacity < 0 || (capacity > 0 && out_ids == nullptr)) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  int32_t count = texture->slot_count();
  for (int32_t i = 0; i < count && i < capacity; ++i) {
    out_ids[i] = texture->texture_id(i);
  }
  return count;
}

int32_t map_texture_select_newest(int64_t handle, map_texture_frame* out) {
  if (out == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  int slot = -1;
  map_texture::FrameInfo info;
  if (!texture->SelectNewest(&slot, &info)) return MAP_TEXTURE_NOT_SELECTED;
  out->frame_id = static_cast<int64_t>(info.frame_id);
  out->slot = slot;
  out->seq = info.seq;
  out->latitude = info.camera.latitude;
  out->longitude = info.camera.longitude;
  out->zoom = info.camera.zoom;
  out->bearing = info.camera.bearing;
  out->physical_width = static_cast<int32_t>(info.physical_width);
  out->physical_height = static_cast<int32_t>(info.physical_height);
  out->scale_factor = info.scale_factor;
  map_texture::FillFrameView(info, &out->view);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_load_style_url(int64_t handle, const char* url) {
  if (url == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->LoadStyleUrl(url);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_load_style_json(int64_t handle, const char* json) {
  if (json == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->LoadStyleJson(json);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_set_camera(int64_t handle, double latitude,
                               double longitude, double zoom, double bearing,
                               int64_t seq) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  if (texture->owns_camera()) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  texture->SetCamera({latitude, longitude, zoom, bearing}, seq);
  return MAP_TEXTURE_OK;
}

namespace {

// Submits `command` to the map `handle` if it owns its camera.
int32_t SubmitCameraCommand(int64_t handle,
                            const map_texture::CameraCommand& command) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  if (!texture->owns_camera()) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  texture->SubmitCameraCommand(command);
  return MAP_TEXTURE_OK;
}

bool ValidMode(int32_t mode) { return mode >= 0 && mode <= 2; }

bool ValidDuration(double duration_ms) { return std::isfinite(duration_ms); }

}  // namespace

int32_t map_texture_camera_command(int64_t handle, int64_t request_id,
                                   int32_t mode,
                                   const map_texture_camera* camera,
                                   double duration_ms) {
  if (camera == nullptr || !ValidMode(mode) || !ValidDuration(duration_ms)) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto target = CameraOf(*camera);
  if (!target) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  map_texture::CameraCommand command;
  command.type = map_texture::CameraCommand::Type::kUpdate;
  command.request_id = request_id;
  command.mode = static_cast<uint32_t>(mode);
  command.fields = static_cast<uint32_t>(camera->fields);
  command.camera = *target;
  command.duration_ms = duration_ms;
  return SubmitCameraCommand(handle, command);
}

int32_t map_texture_fit_bounds(int64_t handle, int64_t request_id, int32_t mode,
                               const map_texture_fit* fit, double duration_ms) {
  if (fit == nullptr || !ValidMode(mode) || !ValidDuration(duration_ms) ||
      (fit->fields & ~7) != 0 ||
      !Finite({fit->south, fit->west, fit->north, fit->east, fit->padding_top,
               fit->padding_left, fit->padding_bottom, fit->padding_right,
               fit->bearing, fit->pitch}) ||
      fit->south > fit->north) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  map_texture::CameraCommand command;
  command.type = map_texture::CameraCommand::Type::kFit;
  command.request_id = request_id;
  command.mode = static_cast<uint32_t>(mode);
  command.fields = static_cast<uint32_t>(fit->fields);
  command.camera.padding = {fit->padding_top, fit->padding_left,
                            fit->padding_bottom, fit->padding_right};
  command.camera.bearing = fit->bearing;
  command.camera.pitch = fit->pitch;
  command.duration_ms = duration_ms;
  command.south = fit->south;
  command.west = fit->west;
  command.north = fit->north;
  command.east = fit->east;
  return SubmitCameraCommand(handle, command);
}

int32_t map_texture_cancel_transitions(int64_t handle) {
  map_texture::CameraCommand command;
  command.type = map_texture::CameraCommand::Type::kCancel;
  return SubmitCameraCommand(handle, command);
}

int32_t map_texture_set_limits(int64_t handle,
                               const map_texture_limits* limits) {
  auto camera_limits = limits != nullptr ? LimitsOf(*limits) : std::nullopt;
  if (!camera_limits) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  map_texture::CameraCommand command;
  command.type = map_texture::CameraCommand::Type::kLimits;
  command.limits = *camera_limits;
  return SubmitCameraCommand(handle, command);
}

int32_t map_texture_gesture_create(int64_t handle,
                                   const map_texture_gesture_options* options) {
  if (options == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  mln_gesture_options gesture_options = GestureOptionsOf(*options);
  return StatusCode(texture->GestureCreate(gesture_options, nullptr));
}

int32_t map_texture_gesture_set_options(
    int64_t handle, const map_texture_gesture_options* options) {
  if (options == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  mln_gesture_options gesture_options = GestureOptionsOf(*options);
  return StatusCode(texture->GestureSetOptions(gesture_options));
}

int32_t map_texture_gesture_handle(int64_t handle,
                                   const map_texture_gesture_input* input,
                                   double time_ms,
                                   map_texture_gesture_result* out_result) {
  if (input == nullptr || out_result == nullptr) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  mln_gesture_result result{};
  result.size = sizeof(result);
  mln_status status =
      texture->GestureHandle(GestureInputOf(*input), time_ms, &result);
  if (status != MLN_STATUS_OK) return StatusCode(status);
  GestureResultOf(result, out_result);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_gesture_tick(int64_t handle, double time_ms,
                                 map_texture_gesture_result* out_result) {
  if (out_result == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  mln_gesture_result result{};
  result.size = sizeof(result);
  mln_status status = texture->GestureTick(time_ms, &result);
  if (status != MLN_STATUS_OK) return StatusCode(status);
  GestureResultOf(result, out_result);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_query_rendered_features(int64_t handle,
                                            int64_t request_id,
                                            const double* world_corners,
                                            const char* const* layer_ids,
                                            int32_t layer_id_count,
                                            const char* filter_json) {
  if (world_corners == nullptr || layer_id_count < 0 ||
      (layer_ids == nullptr && layer_id_count > 0)) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  map_texture::RenderedQuery query;
  query.request_id = request_id;
  for (int i = 0; i < 4; ++i) {
    double x = world_corners[2 * i];
    double y = world_corners[2 * i + 1];
    if (!std::isfinite(x) || !std::isfinite(y)) {
      return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
    }
    query.corners[i] = {x, y};
  }
  if (layer_ids != nullptr) {
    std::vector<std::string> ids;
    for (int32_t i = 0; i < layer_id_count; ++i) {
      if (layer_ids[i] == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
      ids.emplace_back(layer_ids[i]);
    }
    query.layer_ids = std::move(ids);
  }
  if (filter_json != nullptr) query.filter = filter_json;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->QueryRenderedFeatures(std::move(query));
  return MAP_TEXTURE_OK;
}

int32_t map_texture_set_feature_state(int64_t handle, const char* source_id,
                                      const char* source_layer_id,
                                      const char* feature_id,
                                      const char* state_json) {
  if (source_id == nullptr || source_id[0] == '\0' || feature_id == nullptr ||
      state_json == nullptr) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->SetFeatureState(
      {source_id, Optional(source_layer_id), feature_id, std::nullopt},
      state_json);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_remove_feature_state(int64_t handle, const char* source_id,
                                         const char* source_layer_id,
                                         const char* feature_id,
                                         const char* key) {
  if (source_id == nullptr || source_id[0] == '\0' ||
      (key != nullptr && feature_id == nullptr)) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->RemoveFeatureState({source_id, Optional(source_layer_id),
                               Optional(feature_id), Optional(key)});
  return MAP_TEXTURE_OK;
}

int32_t map_texture_overlay_set_source(int64_t handle, int64_t overlay_id,
                                       int32_t source_index,
                                       int32_t source_options,
                                       const uint8_t* geojson, int64_t length,
                                       char** out_error) {
  if (out_error != nullptr) *out_error = nullptr;
  const char* invalid = nullptr;
  if (source_index < 0) {
    invalid = "the source index is negative";
  } else if ((source_options & ~map_texture::kSourceOptionsMask) != 0) {
    invalid = "unknown source options";
  } else if (geojson == nullptr || length <= 0) {
    invalid = "the GeoJSON is empty";
  }
  if (invalid != nullptr) {
    if (out_error != nullptr) *out_error = strdup(invalid);
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->OverlaySetSource(
      overlay_id, source_index, source_options,
      std::make_shared<const std::string>(reinterpret_cast<const char*>(geojson),
                                          static_cast<size_t>(length)));
  return MAP_TEXTURE_OK;
}

int32_t map_texture_overlay_remove_source(int64_t handle, int64_t overlay_id,
                                          int32_t source_index) {
  if (source_index < 0) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->OverlayRemoveSource(overlay_id, source_index);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_overlay_set_layers(int64_t handle, int64_t overlay_id,
                                       const char* layers_json,
                                       int32_t placement_kind,
                                       const char* below_layer_id,
                                       int64_t order_child, int64_t order_seq) {
  using map_texture::PlacementKind;
  if (layers_json == nullptr || placement_kind < 0 || placement_kind > 2) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  map_texture::Placement placement;
  placement.kind = static_cast<PlacementKind>(placement_kind);
  if (placement.kind == PlacementKind::kBelowLayer) {
    if (below_layer_id == nullptr || below_layer_id[0] == '\0') {
      return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
    }
    placement.below_layer_id = below_layer_id;
  }
  auto layers = map_texture::SplitJsonObjectArray(layers_json);
  if (!layers) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  std::vector<int32_t> sources;
  for (size_t i = 0; i < layers->size(); ++i) {
    auto id = map_texture::JsonStringMember((*layers)[i], "id");
    if (!id || *id != map_texture::OverlayLayerId(overlay_id, i)) {
      return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
    }
    auto source = map_texture::JsonStringMember((*layers)[i], "source");
    auto index = source ? map_texture::OverlaySourceIndex(overlay_id, *source)
                        : std::nullopt;
    if (!index) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
    if (std::find(sources.begin(), sources.end(), *index) == sources.end()) {
      sources.push_back(*index);
    }
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->OverlaySetLayers(overlay_id, std::move(*layers), std::move(sources),
                            std::move(placement), {order_child, order_seq});
  return MAP_TEXTURE_OK;
}

int32_t map_texture_overlay_remove(int64_t handle, int64_t overlay_id) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->OverlayRemove(overlay_id);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_resize(int64_t handle, double logical_width,
                           double logical_height, double pixel_ratio) {
  if (!(logical_width > 0) || !(logical_height > 0) || !(pixel_ratio > 0)) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->Resize({logical_width, logical_height, pixel_ratio});
  return MAP_TEXTURE_OK;
}

int32_t map_texture_set_display_refresh_rate(int64_t handle, double hz) {
  if (!(hz >= 0)) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->SetDisplayRefreshRate(hz);
  return MAP_TEXTURE_OK;
}

int32_t map_texture_get_stats(int64_t handle, map_texture_stats* out_stats) {
  if (out_stats == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  *out_stats = texture->stats();
  return MAP_TEXTURE_OK;
}

int32_t map_texture_project_for_testing(int64_t handle, double latitude,
                                        double longitude, double* out_x,
                                        double* out_y) {
  if (out_x == nullptr || out_y == nullptr) {
    return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  }
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  auto point = texture->ProjectForTesting(latitude, longitude);
  if (!point) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  *out_x = point->x;
  *out_y = point->y;
  return MAP_TEXTURE_OK;
}

int32_t map_texture_at_rest_for_testing(int64_t handle) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  return texture->AtRestForTesting() ? 1 : 0;
}

int32_t map_texture_dispose(int64_t handle) {
  std::shared_ptr<MapTexture> texture;
  {
    std::lock_guard lock(registry_mutex);
    auto it = Registry().find(handle);
    if (it == Registry().end()) return MAP_TEXTURE_ERROR_DISPOSED;
    texture = std::move(it->second);
    Registry().erase(it);
  }
  texture->Dispose();
  return MAP_TEXTURE_OK;
}

int32_t map_texture_wait_for_releases_for_testing(int64_t timeout_ms) {
  return map_texture::FinishAllReleasesForTesting(timeout_ms) ? 1 : 0;
}

void map_texture_set_paused_for_testing(int32_t paused) {
  map_texture::SetAllPaused(paused != 0);
}

void map_texture_set_render_ahead_for_testing(int32_t mode) {
  using map_texture::RenderAheadMode;
  map_texture::SetRenderAheadModeForTesting(
      mode < 0 ? RenderAheadMode::kNever
               : mode > 0 ? RenderAheadMode::kAlways : RenderAheadMode::kAuto);
}

void map_texture_reduce_memory_use_for_testing(void) {
  map_texture::ReduceAllMemoryUse();
}

void map_texture_event_free(map_texture_event* event) {
  if (event == nullptr) return;
  std::free(event->message);
  std::free(event);
}

}  // extern "C"
