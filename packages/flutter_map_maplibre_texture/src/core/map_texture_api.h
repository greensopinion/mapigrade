// The C ABI that Dart binds with @Native (design D5).
//
// Every function takes the handle returned by map_texture_create(). Commands
// only queue work for the map thread and return without waiting for a frame.
// Calls with a disposed or unknown handle return MAP_TEXTURE_ERROR_DISPOSED.
#ifndef MAP_TEXTURE_API_H
#define MAP_TEXTURE_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MAP_TEXTURE_EXPORT __attribute__((visibility("default"), used))

enum {
  MAP_TEXTURE_OK = 0,
  MAP_TEXTURE_ERROR_DISPOSED = -1,
  MAP_TEXTURE_ERROR_INVALID_ARGUMENT = -2,
  MAP_TEXTURE_ERROR_CREATE_FAILED = -3,
};

enum {
  MAP_TEXTURE_EVENT_STYLE_LOADED = 0,
  MAP_TEXTURE_EVENT_LOADING_FAILED = 1,
  MAP_TEXTURE_EVENT_RENDER_ERROR = 2,
  MAP_TEXTURE_EVENT_IDLE = 3,
  MAP_TEXTURE_EVENT_FRAME_DISPLAYED = 4,
};

// An event for Dart. The receiver frees it with map_texture_event_free().
typedef struct map_texture_event {
  int64_t handle;
  int32_t type;
  // Set for MAP_TEXTURE_EVENT_FRAME_DISPLAYED: the frame and the camera and
  // size it was rendered with.
  int64_t frame_id;
  double latitude;
  double longitude;
  double zoom;
  double bearing;
  int32_t physical_width;
  int32_t physical_height;
  double scale_factor;
  // Set for MAP_TEXTURE_EVENT_LOADING_FAILED and MAP_TEXTURE_EVENT_RENDER_ERROR;
  // otherwise null. UTF-8, null-terminated.
  char* message;
} map_texture_event;

typedef void (*map_texture_event_callback)(map_texture_event* event);

typedef struct map_texture_stats {
  int64_t rendered_frames;
  // Renders deferred because no buffer was free.
  int64_t skipped_renders;
  // Renders deferred because Flutter hadn't taken the latest frame yet.
  int64_t waits_for_display;
  int64_t render_update_count;
  int64_t render_update_total_ns;
  int64_t render_update_max_ns;
  // GPU copies of the render texture into a buffer, including the wait for
  // completion.
  int64_t copy_count;
  int64_t copy_total_ns;
  int64_t copy_max_ns;
  int64_t presented_frames;
  // MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE events received.
  int64_t render_update_available_events;
  // Rendered frames after which the renderer reported needs_repaint.
  int64_t needs_repaint_frames;
  // Renders deferred because rendering was paused, for example while an iOS
  // app is in the background.
  int64_t paused_renders;
  // Calls to mln_render_session_reduce_memory_use() that succeeded.
  int64_t memory_reductions;
} map_texture_stats;

// Creates a map that renders at `pixel_ratio` and starts its map thread.
// Events are delivered through `callback`, from any thread. Returns a handle
// (> 0) or a negative MAP_TEXTURE_ERROR_* value.
MAP_TEXTURE_EXPORT int64_t map_texture_create(
    double pixel_ratio, map_texture_event_callback callback);

// Returns the Flutter texture id, or a negative error.
MAP_TEXTURE_EXPORT int64_t map_texture_texture_id(int64_t handle);

MAP_TEXTURE_EXPORT int32_t map_texture_load_style_url(int64_t handle,
                                                      const char* url);
MAP_TEXTURE_EXPORT int32_t map_texture_load_style_json(int64_t handle,
                                                       const char* json);
MAP_TEXTURE_EXPORT int32_t map_texture_set_camera(int64_t handle,
                                                  double latitude,
                                                  double longitude,
                                                  double zoom, double bearing);
// Sets the widget's logical size and device pixel ratio.
MAP_TEXTURE_EXPORT int32_t map_texture_resize(int64_t handle,
                                              double logical_width,
                                              double logical_height,
                                              double pixel_ratio);
MAP_TEXTURE_EXPORT int32_t map_texture_get_stats(int64_t handle,
                                                 map_texture_stats* out_stats);
// Stops the map thread, releases the map and its resources, and unregisters
// the texture. No events are delivered after this returns.
MAP_TEXTURE_EXPORT int32_t map_texture_dispose(int64_t handle);

MAP_TEXTURE_EXPORT void map_texture_event_free(map_texture_event* event);

// The number of threads in this process, for the lifecycle test.
MAP_TEXTURE_EXPORT int32_t map_texture_process_thread_count(void);

// For tests: pause (non-zero) or resume (zero) rendering of every map, as the
// platform does when the application enters the background or foreground.
MAP_TEXTURE_EXPORT void map_texture_set_paused_for_testing(int32_t paused);
// For tests: ask every map to release cached renderer resources, as the
// platform does after a memory warning.
MAP_TEXTURE_EXPORT void map_texture_reduce_memory_use_for_testing(void);

#ifdef __cplusplus
}
#endif

#endif  // MAP_TEXTURE_API_H
