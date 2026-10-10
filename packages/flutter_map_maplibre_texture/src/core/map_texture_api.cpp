#include "map_texture_api.h"

#include <cstdlib>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include "map_texture.h"

namespace {

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
// Whether rendering is paused for the whole process; guarded by
// registry_mutex.
bool all_paused = false;

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

int64_t TotalRenderedFrames() {
  std::lock_guard lock(registry_mutex);
  int64_t total = 0;
  for (auto& [handle, texture] : Registry()) {
    total += texture->stats().rendered_frames;
  }
  return total;
}

}  // namespace map_texture

extern "C" {

int64_t map_texture_create(double pixel_ratio,
                           map_texture_event_callback callback) {
  if (callback == nullptr) return MAP_TEXTURE_ERROR_INVALID_ARGUMENT;
  int64_t handle;
  {
    std::lock_guard lock(registry_mutex);
    handle = next_handle++;
  }
  auto texture = MapTexture::Create(handle, pixel_ratio, callback);
  if (!texture) return MAP_TEXTURE_ERROR_CREATE_FAILED;
  std::lock_guard lock(registry_mutex);
  // The map can't have rendered yet: its render session is attached by the
  // first resize, which needs the handle returned here.
  if (all_paused) texture->SetPaused(true);
  Registry()[handle] = std::move(texture);
  return handle;
}

int64_t map_texture_texture_id(int64_t handle) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  return texture->texture_id();
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
                               double longitude, double zoom, double bearing) {
  auto texture = Find(handle);
  if (!texture) return MAP_TEXTURE_ERROR_DISPOSED;
  texture->SetCamera({latitude, longitude, zoom, bearing});
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

void map_texture_reduce_memory_use_for_testing(void) {
  map_texture::ReduceAllMemoryUse();
}

void map_texture_event_free(map_texture_event* event) {
  if (event == nullptr) return;
  std::free(event->message);
  std::free(event);
}

}  // extern "C"
