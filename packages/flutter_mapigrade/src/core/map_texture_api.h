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
  // Set for MAP_TEXTURE_EVENT_FRAME_DISPLAYED. On macOS and iOS: the time at
  // which Flutter took the frame for display, in microseconds on the clock of
  // Flutter's FrameTiming. On Android, the event is sent when the frame has
  // been queued for display, and this is -1 (no display time).
  int64_t display_time_us;
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
  // completion. Always 0 for a copy-free map.
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
  // Time from one render_update start to the next, counted when the two are
  // less than 100 ms apart (continuous rendering).
  int64_t frame_cycle_count;
  int64_t frame_cycle_total_ns;
  // Time from publishing a frame until Flutter takes it (Present).
  int64_t pickup_wait_count;
  int64_t pickup_wait_total_ns;
  // Time from Flutter taking a frame until the next render_update starts,
  // counted when that render waited for Flutter to take the frame.
  int64_t present_to_render_count;
  int64_t present_to_render_total_ns;
  // Renders started before Flutter had taken the latest frame (design D19).
  int64_t render_ahead_frames;
  // Renders deferred until one display refresh interval after the start of
  // the previous render (Android, design D53).
  int64_t interval_waits;
} map_texture_stats;

// Creates a map that renders at `pixel_ratio` and starts its map thread.
// With `copy_free` non-zero (what the Dart API passes by default), MapLibre
// renders each frame directly into a free display buffer; otherwise it renders
// into one render texture, and each frame is copied on the GPU into a free
// display buffer (design D20). On Android every map renders directly into the
// display buffers, and `copy_free` has no effect. Events are
// delivered through `callback`, from any thread. Returns a handle (> 0) or a
// negative MAP_TEXTURE_ERROR_* value.
MAP_TEXTURE_EXPORT int64_t map_texture_create(
    double pixel_ratio, int32_t copy_free,
    map_texture_event_callback callback);

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
// Sets the refresh rate in Hz of the display that shows the map.
MAP_TEXTURE_EXPORT int32_t map_texture_set_display_refresh_rate(int64_t handle,
                                                                double hz);
MAP_TEXTURE_EXPORT int32_t map_texture_get_stats(int64_t handle,
                                                 map_texture_stats* out_stats);
// Stops the map thread, releases the map and its resources, and unregisters
// the texture. No events are delivered after this returns.
MAP_TEXTURE_EXPORT int32_t map_texture_dispose(int64_t handle);

MAP_TEXTURE_EXPORT void map_texture_event_free(map_texture_event* event);

// The number of threads in this process, for the lifecycle test.
MAP_TEXTURE_EXPORT int32_t map_texture_process_thread_count(void);

// The device's thermal state, for measurements: 0 nominal, 1 fair, 2 serious,
// 3 critical (NSProcessInfoThermalState), or -1 if unknown.
MAP_TEXTURE_EXPORT int32_t map_texture_thermal_state(void);

// The process's physical memory footprint in bytes (the value Xcode's memory
// gauge shows), for measurements, or -1 if unknown.
MAP_TEXTURE_EXPORT int64_t map_texture_memory_footprint(void);

// For tests: how many display buffers released since the last reset are still
// alive (kept alive by something other than the plugin), and their size in
// bytes in `out_bytes` (may be null).
MAP_TEXTURE_EXPORT int32_t map_texture_released_buffers_alive_for_testing(
    int64_t* out_bytes);
// For tests: the number of display buffers released since the last reset;
// resets the count when `reset` is non-zero.
MAP_TEXTURE_EXPORT int32_t map_texture_released_buffers_for_testing(
    int32_t reset);
// For tests and measurements: 0 renders ahead while a frame takes longer than
// a display refresh interval (the default), -1 never renders ahead, 1 always
// renders without waiting until Flutter has taken the latest frame.
MAP_TEXTURE_EXPORT void map_texture_set_render_ahead_for_testing(int32_t mode);

// For tests: pause (non-zero) or resume (zero) rendering of every map, as the
// platform does when the application enters the background or foreground.
MAP_TEXTURE_EXPORT void map_texture_set_paused_for_testing(int32_t paused);
// For tests: ask every map to release cached renderer resources, as the
// platform does after a memory warning.
MAP_TEXTURE_EXPORT void map_texture_reduce_memory_use_for_testing(void);
// For tests, on Android: with `restore` zero, makes Flutter remove the
// surfaces the maps render into, as it does when the activity stops (it calls
// onTrimMemory(TRIM_MEMORY_BACKGROUND)); with `restore` non-zero, makes Flutter
// provide them again, as it does when the activity resumes. Call on the
// platform thread. Does nothing on macOS and iOS.
MAP_TEXTURE_EXPORT void map_texture_trim_surfaces_for_testing(int32_t restore);

#ifdef __cplusplus
}
#endif

#endif  // MAP_TEXTURE_API_H
