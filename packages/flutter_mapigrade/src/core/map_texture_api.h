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
  // map_texture_select_newest(): no finished frame that Dart hasn't chosen,
  // and no choice was recorded.
  MAP_TEXTURE_NOT_SELECTED = 1,
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
  // A frame has finished rendering into a display slot, and Dart may choose
  // it with map_texture_select_newest() (designs D123 and D140).
  MAP_TEXTURE_EVENT_FRAME_READY = 5,
};

// An event for Dart. The receiver frees it with map_texture_event_free().
typedef struct map_texture_event {
  int64_t handle;
  int32_t type;
  // Set for MAP_TEXTURE_EVENT_FRAME_DISPLAYED and MAP_TEXTURE_EVENT_FRAME_READY:
  // the frame and the camera and size it was rendered with.
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
  // Flutter's FrameTiming. On Android, the event is sent when Dart first
  // chooses the frame (design D132), and this is -1 (no display time).
  int64_t display_time_us;
  // Set for MAP_TEXTURE_EVENT_FRAME_DISPLAYED and MAP_TEXTURE_EVENT_FRAME_READY:
  // the display slot that holds the frame, and the
  // sequence number of the camera update the frame was rendered with (the
  // `seq` of map_texture_set_camera(), or 0 before the first).
  int32_t slot;
  int64_t seq;
  // Set for MAP_TEXTURE_EVENT_LOADING_FAILED and MAP_TEXTURE_EVENT_RENDER_ERROR;
  // otherwise null. UTF-8, null-terminated.
  char* message;
} map_texture_event;

typedef void (*map_texture_event_callback)(map_texture_event* event);

// A frame that map_texture_select_newest() chose: the frame, the display slot
// that holds it, the camera and size it was rendered with, and the sequence
// number of the camera update it was rendered with (design D140).
typedef struct map_texture_frame {
  int64_t frame_id;
  int32_t slot;
  int64_t seq;
  double latitude;
  double longitude;
  double zoom;
  double bearing;
  int32_t physical_width;
  int32_t physical_height;
  double scale_factor;
} map_texture_frame;

typedef struct map_texture_stats {
  int64_t rendered_frames;
  // Renders deferred because no display slot was free.
  int64_t skipped_renders;
  // Renders deferred because Dart hadn't chosen the latest finished frame yet
  // (macOS and iOS).
  int64_t waits_for_display;
  int64_t render_update_count;
  int64_t render_update_total_ns;
  int64_t render_update_max_ns;
  // GPU copies of the render texture into a buffer, including the wait for
  // completion. Always 0 for a copy-free map.
  int64_t copy_count;
  int64_t copy_total_ns;
  int64_t copy_max_ns;
  // Frames given to Flutter for display. On macOS and iOS: frames that
  // Flutter took for display. On Android: frames that Dart chose.
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
  // Time from publishing a frame until Flutter takes it (Present), or on
  // Android until Dart chooses it.
  int64_t pickup_wait_count;
  int64_t pickup_wait_total_ns;
  // Time from Dart choosing the latest frame until the next render_update
  // starts, counted when that render waited for Dart to choose it.
  int64_t present_to_render_count;
  int64_t present_to_render_total_ns;
  // Renders started before Dart had chosen the latest frame (design D19).
  int64_t render_ahead_frames;
  // Renders deferred until one display refresh interval after the start of
  // the previous render (Android, designs D53 and D134).
  int64_t interval_waits;
  // The most display slots in use (rendering, queued, ready or held) at
  // once.
  int64_t max_slots_in_use;
  // Time from map_texture_set_camera() until the frame-ready event of the
  // first frame rendered with that camera, counted once per camera. A camera
  // that a later one replaced before the map thread applied it isn't counted.
  int64_t camera_latency_count;
  int64_t camera_latency_total_ns;
  int64_t camera_latency_max_ns;
} map_texture_stats;

// Creates a map that renders at `pixel_ratio` and starts its map thread. The
// map registers its Flutter textures with the engine of the token `engine`,
// which the plugin gave to Dart over the channel `flutter_mapigrade` (designs
// D153 to D156 of the multiple-flutter-engines change).
// With `copy_free` non-zero (what the Dart API passes by default), MapLibre
// renders each frame directly into a free display buffer; otherwise it renders
// into one render texture, and each frame is copied on the GPU into a free
// display buffer (design D20). On Android every map renders directly into the
// display buffers, and `copy_free` has no effect. Events are
// delivered through `callback`, from any thread.
//
// `header_strings` holds, for each of `rule_count` HTTP header rules, its URL
// glob and `header_counts[i]` name and value pairs (design D81).
//
// Returns a handle (> 0) or a negative MAP_TEXTURE_ERROR_* value. On failure
// `*out_error`, if non-null, is a message to free with
// map_texture_string_free().
MAP_TEXTURE_EXPORT int64_t map_texture_create(
    int64_t engine, double pixel_ratio, int32_t copy_free, map_texture_event_callback callback,
    const char* const* header_strings, const int32_t* header_counts,
    int32_t rule_count, char** out_error);

// Frees a string returned by map_texture_create().
MAP_TEXTURE_EXPORT void map_texture_string_free(char* string);

// Sets the maximum size in bytes of the tile cache for maps created after the
// call. Maps that already exist keep their maximum size. Without a call, maps
// use MapLibre's default of 50 MiB. Returns 0, or
// MAP_TEXTURE_ERROR_INVALID_ARGUMENT for a negative size.
MAP_TEXTURE_EXPORT int32_t map_texture_set_maximum_cache_size(int64_t bytes);

// Writes the Flutter texture id of each display slot, at most `capacity`, to
// `out_ids` and returns the number of slots (4 on macOS and iOS; 6 on
// Android, which share one texture id), or a negative error.
MAP_TEXTURE_EXPORT int32_t map_texture_texture_ids(int64_t handle,
                                                   int64_t* out_ids,
                                                   int32_t capacity);

// Platform thread. Dart chooses, for the Flutter frame it builds, the newest
// finished frame that it hasn't chosen (designs D139 and D140). Marks the
// frame's texture available, or on Android gives the frame's image to the
// texture, before the Flutter frame is rasterized (designs D123 and D132),
// writes the frame to `out` and returns MAP_TEXTURE_OK; Dart then displays
// the slot's texture. Returns MAP_TEXTURE_NOT_SELECTED and records nothing if
// no such frame is finished; Dart then keeps displaying the frame it chose
// before.
MAP_TEXTURE_EXPORT int32_t map_texture_select_newest(int64_t handle,
                                                     map_texture_frame* out);

MAP_TEXTURE_EXPORT int32_t map_texture_load_style_url(int64_t handle,
                                                      const char* url);
MAP_TEXTURE_EXPORT int32_t map_texture_load_style_json(int64_t handle,
                                                       const char* json);
// Sets the camera. `seq` identifies the update; frames rendered with it
// report it (design D125).
MAP_TEXTURE_EXPORT int32_t map_texture_set_camera(int64_t handle,
                                                  double latitude,
                                                  double longitude,
                                                  double zoom, double bearing,
                                                  int64_t seq);
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
// For tests, on Android: with `restore` zero, releases the image readers the
// maps render into, as the plugin does when the activity stops; with `restore`
// non-zero, creates them again, as it does when the activity starts (design
// D137). Call on the platform thread. Does nothing on macOS and iOS.
MAP_TEXTURE_EXPORT void map_texture_trim_surfaces_for_testing(int32_t restore);

#ifdef __cplusplus
}
#endif

#endif  // MAP_TEXTURE_API_H
