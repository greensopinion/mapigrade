#include "map_texture_api.h"

#include <cmath>
#include <cstdlib>
#include <cstring>
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
}

}  // namespace map_texture

extern "C" {

int64_t map_texture_create(int64_t engine, double pixel_ratio,
                           int32_t copy_free,
                           map_texture_event_callback callback,
                           const char* const* header_strings,
                           const int32_t* header_counts, int32_t rule_count,
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
  int64_t handle;
  std::optional<uint64_t> cache_size;
  {
    std::lock_guard lock(registry_mutex);
    handle = next_handle++;
    if (maximum_cache_size >= 0) cache_size = maximum_cache_size;
  }
  auto texture = MapTexture::Create(handle, engine, pixel_ratio, copy_free != 0,
                                    cache_size, std::move(rules), callback,
                                    &error);
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
  out->pitch = info.camera.pitch;
  out->physical_width = static_cast<int32_t>(info.physical_width);
  out->physical_height = static_cast<int32_t>(info.physical_height);
  out->scale_factor = info.scale_factor;
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
                               double pitch, int64_t seq) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->SetCamera({latitude, longitude, zoom, bearing, pitch}, seq);
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
