// The C ABI that Dart binds with @Native.
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
  // it with map_texture_select_newest().
  MAP_TEXTURE_EVENT_FRAME_READY = 5,
  // The result of map_texture_query_rendered_features().
  MAP_TEXTURE_EVENT_QUERY_RESULT = 6,
  // A camera command of map_texture_camera_command() or
  // map_texture_fit_bounds() ended: `request_id` is the command's, and
  // `status` its MAP_TEXTURE_OUTCOME_*.
  MAP_TEXTURE_EVENT_CAMERA_TRANSITION_ENDED = 7,
  // A map that owns its camera: no gesture, glide, snap or camera transition
  // moves the camera any more. A frame shows the camera at rest once its
  // `map_update_generation` is at least the event's.
  MAP_TEXTURE_EVENT_CAMERA_SETTLED = 8,
};

// How a camera command ended; mln_camera_transition_outcome.
enum {
  MAP_TEXTURE_OUTCOME_COMPLETED = 0,
  MAP_TEXTURE_OUTCOME_CANCELLED = 1,
  MAP_TEXTURE_OUTCOME_CLOSED = 2,
  MAP_TEXTURE_OUTCOME_REPLACED = 3,
};

// What moved the camera last before a frame; mln_camera_change_source.
enum {
  MAP_TEXTURE_CAMERA_SOURCE_COMMAND = 0,
  MAP_TEXTURE_CAMERA_SOURCE_GESTURE = 1,
  MAP_TEXTURE_CAMERA_SOURCE_MOMENTUM = 2,
};

// The fields of a map_texture_camera that a command sets; the bits of
// mln_camera_option_field.
#define MAP_TEXTURE_CAMERA_CENTER 1
#define MAP_TEXTURE_CAMERA_ZOOM 2
#define MAP_TEXTURE_CAMERA_BEARING 4
#define MAP_TEXTURE_CAMERA_PITCH 8
#define MAP_TEXTURE_CAMERA_CENTER_ALTITUDE 16
#define MAP_TEXTURE_CAMERA_PADDING 32
#define MAP_TEXTURE_CAMERA_ROLL 128
#define MAP_TEXTURE_CAMERA_FIELD_OF_VIEW 256

// A camera with the fields of mln_camera, in its conventions. The padding is
// in logical pixels.
typedef struct map_texture_camera {
  int32_t fields;
  double latitude;
  double longitude;
  double center_altitude;
  double padding_top;
  double padding_left;
  double padding_bottom;
  double padding_right;
  double zoom;
  double bearing;
  double pitch;
  double roll;
  double field_of_view;
} map_texture_camera;

// The limits of a map that owns its camera; mln_bound_options. With
// `has_bounds` zero the center isn't limited.
typedef struct map_texture_limits {
  double min_zoom;
  double max_zoom;
  double min_pitch;
  double max_pitch;
  int32_t has_bounds;
  double south;
  double west;
  double north;
  double east;
} map_texture_limits;

// The area and options of map_texture_fit_bounds(). `fields` has bit 1 for
// the padding, 2 for the bearing and 4 for the pitch, as
// mln_camera_fit_option_field.
typedef struct map_texture_fit {
  double south;
  double west;
  double north;
  double east;
  int32_t fields;
  double padding_top;
  double padding_left;
  double padding_bottom;
  double padding_right;
  double bearing;
  double pitch;
} map_texture_fit;

// The camera fields that a frame was rendered with besides the center, zoom
// and bearing, the matrix it drew the map with, and what moved its camera.
typedef struct map_texture_frame_view {
  double pitch;
  double center_altitude;
  double padding_top;
  double padding_left;
  double padding_bottom;
  double padding_right;
  double roll;
  double field_of_view;
  // mln_frame_projection.matrix, column-major: the 16 doubles of columns x, y,
  // z and w in order. All zero for a frame that rendered nothing.
  double matrix[16];
  // An mln_clip_depth_range.
  int32_t clip_depth_range;
  // A MAP_TEXTURE_CAMERA_SOURCE_*: the source of the last camera change that
  // the runtime reported before the frame finished.
  int32_t camera_source;
  // mln_render_frame_result.map_update_generation.
  int64_t map_update_generation;
} map_texture_frame_view;

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
  // chooses the frame, and this is -1 (no display time).
  int64_t display_time_us;
  // Set for MAP_TEXTURE_EVENT_FRAME_DISPLAYED and MAP_TEXTURE_EVENT_FRAME_READY:
  // the display slot that holds the frame, and the sequence number of the
  // camera update the frame was rendered with (the `seq` of
  // map_texture_set_camera(), or 0 before the first).
  int32_t slot;
  int64_t seq;
  // Set for MAP_TEXTURE_EVENT_LOADING_FAILED, MAP_TEXTURE_EVENT_RENDER_ERROR
  // and MAP_TEXTURE_EVENT_QUERY_RESULT; otherwise null. UTF-8,
  // null-terminated.
  char* message;
  // Set for MAP_TEXTURE_EVENT_QUERY_RESULT: the query's `request_id`, and its
  // status. With status 0, `message` is a JSON array with one object per
  // feature: {"feature": <GeoJSON Feature>, "source": <source ID>,
  // "sourceLayer": <source-layer ID or null>, "state": <feature state>}.
  // Otherwise status is the failing mln_status, and `message` describes the
  // failure.
  int64_t request_id;
  int32_t status;
  // Set for MAP_TEXTURE_EVENT_FRAME_DISPLAYED and MAP_TEXTURE_EVENT_FRAME_READY.
  // For MAP_TEXTURE_EVENT_CAMERA_SETTLED, only `view.map_update_generation`.
  map_texture_frame_view view;
} map_texture_event;

typedef void (*map_texture_event_callback)(map_texture_event* event);

// A frame that map_texture_select_newest() chose: the frame, the display slot
// that holds it, the camera and size it was rendered with, and the sequence
// number of the camera update it was rendered with.
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
  map_texture_frame_view view;
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
  // Renders started before Dart had chosen the latest frame.
  int64_t render_ahead_frames;
  // Renders deferred until one display refresh interval after the start of
  // the previous render (Android).
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
// which the plugin gave to Dart over the channel `mapigrade`.
// With `copy_free` non-zero (what the Dart API passes by default), MapLibre
// renders each frame directly into a free display buffer; otherwise it renders
// into one render texture, and each frame is copied on the GPU into a free
// display buffer. On Android every map renders directly into the display
// buffers, and `copy_free` has no effect. Events are delivered through
// `callback`, from any thread.
//
// `header_strings` holds, for each of `rule_count` HTTP header rules, its URL
// glob and `header_counts[i]` name and value pairs.
//
// With `initial_camera` null, Dart owns the camera and sets it with
// map_texture_set_camera(). Otherwise the map owns its camera (design D235):
// it starts at the fields of `initial_camera` that its `fields` sets, within
// `limits` (which must then be non-null), and only camera commands and the
// gesture recognizer move it; map_texture_set_camera() is then refused.
//
// Returns a handle (> 0) or a negative MAP_TEXTURE_ERROR_* value. On failure
// `*out_error`, if non-null, is a message to free with
// map_texture_string_free().
MAP_TEXTURE_EXPORT int64_t map_texture_create(
    int64_t engine, double pixel_ratio, int32_t copy_free, map_texture_event_callback callback,
    const char* const* header_strings, const int32_t* header_counts,
    int32_t rule_count, const map_texture_camera* initial_camera,
    const map_texture_limits* limits, char** out_error);

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
// finished frame that it hasn't chosen. Marks the frame's texture available,
// or on Android gives the frame's image to the texture, before the Flutter
// frame is rasterized, writes the frame to `out` and returns MAP_TEXTURE_OK;
// Dart then displays the slot's texture. Returns MAP_TEXTURE_NOT_SELECTED and
// records nothing if no such frame is finished; Dart then keeps displaying the
// frame it chose before.
MAP_TEXTURE_EXPORT int32_t map_texture_select_newest(int64_t handle,
                                                     map_texture_frame* out);

MAP_TEXTURE_EXPORT int32_t map_texture_load_style_url(int64_t handle,
                                                      const char* url);
MAP_TEXTURE_EXPORT int32_t map_texture_load_style_json(int64_t handle,
                                                       const char* json);
// Sets the camera of a map whose camera Dart owns. `seq` identifies the
// update; frames rendered with it report it. Returns
// MAP_TEXTURE_ERROR_INVALID_ARGUMENT for a map that owns its camera.
MAP_TEXTURE_EXPORT int32_t map_texture_set_camera(int64_t handle,
                                                  double latitude,
                                                  double longitude,
                                                  double zoom, double bearing,
                                                  int64_t seq);

// Camera commands of a map that owns its camera (design D236), ordered with
// the other commands. Each returns MAP_TEXTURE_ERROR_INVALID_ARGUMENT for a
// map whose camera Dart owns, or for invalid arguments.
//
// Moves the camera to the fields of `camera` that its `fields` sets: `mode`
// 0 jumps, 1 eases and 2 flies, over `duration_ms`, or MapLibre's duration
// when it is negative. The command's end is reported as one
// MAP_TEXTURE_EVENT_CAMERA_TRANSITION_ENDED with `request_id`.
MAP_TEXTURE_EXPORT int32_t map_texture_camera_command(
    int64_t handle, int64_t request_id, int32_t mode,
    const map_texture_camera* camera, double duration_ms);
// Moves the camera to fit `fit`'s area, as map_texture_camera_command() does.
// Padding that leaves no room for the area ends the command as cancelled.
MAP_TEXTURE_EXPORT int32_t map_texture_fit_bounds(int64_t handle,
                                                  int64_t request_id,
                                                  int32_t mode,
                                                  const map_texture_fit* fit,
                                                  double duration_ms);
// Stops every running camera transition; each ends as cancelled.
MAP_TEXTURE_EXPORT int32_t map_texture_cancel_transitions(int64_t handle);
// Replaces the camera limits; a camera outside them moves inside.
MAP_TEXTURE_EXPORT int32_t map_texture_set_limits(
    int64_t handle, const map_texture_limits* limits);

// The gesture recognizer of a map that owns its camera (designs D237 and
// D240), which moves the camera with camera commands of its own. Any thread
// may call these, and none waits for the map thread. A map has at most one
// recognizer, from map_texture_gesture_create() until the map is disposed.

// The options of the recognizer. A part that isn't enabled doesn't move the
// camera. `momentum_model` is an mln_momentum_decay_model: with
// MLN_MOMENTUM_DECAY_MODEL_FRICTION every part glides with a half-life of
// `half_life_ms`, and with MLN_MOMENTUM_DECAY_MODEL_CURVE with Android's
// fling defaults. A zoom of 0 for `double_tap_zoom` or `two_finger_tap_zoom`
// leaves those taps to Dart.
typedef struct map_texture_gesture_options {
  int32_t pan;
  int32_t zoom;
  int32_t rotate;
  int32_t pitch;
  int32_t glides;
  int32_t snap_to_north;
  double double_tap_zoom;
  double two_finger_tap_zoom;
  int32_t momentum_model;
  double half_life_ms;
} map_texture_gesture_options;

// One mln_gesture_input, flattened. `type` is an mln_gesture_input_type.
// POINTER_DOWN uses `pointer_id`, `pointer_kind`, `x`, `y` and `modes`;
// POINTER_MOVE, POINTER_UP and POINTER_CANCEL `pointer_id`, `x` and `y`; MODES
// `modes`; DELTA `x`, `y` (its position), `discrete`, `pan_x`, `pan_y`,
// `zoom`, `bearing` and `pitch`; PINCH `x`, `y` (its center), `scale`,
// `rotation` and `phase`. Positions are logical pixels from the map's
// top-left corner.
typedef struct map_texture_gesture_input {
  int32_t type;
  int32_t pointer_id;
  int32_t pointer_kind;
  int32_t modes;
  double x;
  double y;
  int32_t discrete;
  double pan_x;
  double pan_y;
  double zoom;
  double bearing;
  double pitch;
  double scale;
  double rotation;
  int32_t phase;
} map_texture_gesture_input;

// One mln_gesture_event, flattened. `type` is an mln_gesture_event_type. Taps
// and long presses set `pointer_id`, `x` and `y`; notches `axis`, `kind` and
// `value`.
typedef struct map_texture_gesture_event {
  int32_t type;
  int32_t pointer_id;
  double x;
  double y;
  int32_t axis;
  int32_t kind;
  double value;
} map_texture_gesture_event;

// An mln_gesture_result, flattened.
typedef struct map_texture_gesture_result {
  int32_t handled;
  // An mln_gesture_next_tick.
  int32_t next_tick;
  double next_tick_ms;
  int32_t box_zoom_active;
  double box_min_x;
  double box_min_y;
  double box_max_x;
  double box_max_y;
  int32_t event_count;
  map_texture_gesture_event events[4];
} map_texture_gesture_result;

// Creates the map's recognizer with `options`. Returns
// MAP_TEXTURE_ERROR_INVALID_ARGUMENT for a map whose camera Dart owns, for a
// map that has one already, or for options that the FFI refuses.
MAP_TEXTURE_EXPORT int32_t map_texture_gesture_create(
    int64_t handle, const map_texture_gesture_options* options);
// Changes the recognizer's options from the next input on.
MAP_TEXTURE_EXPORT int32_t map_texture_gesture_set_options(
    int64_t handle, const map_texture_gesture_options* options);
// Passes one input at `time_ms`, on a clock that only goes forward, to the
// recognizer and writes its result.
MAP_TEXTURE_EXPORT int32_t map_texture_gesture_handle(
    int64_t handle, const map_texture_gesture_input* input, double time_ms,
    map_texture_gesture_result* out_result);
// Ticks the recognizer at `time_ms`, when the last result asked for it.
MAP_TEXTURE_EXPORT int32_t map_texture_gesture_tick(
    int64_t handle, double time_ms, map_texture_gesture_result* out_result);
// Sets the widget's logical size and device pixel ratio.
MAP_TEXTURE_EXPORT int32_t map_texture_resize(int64_t handle,
                                              double logical_width,
                                              double logical_height,
                                              double pixel_ratio);
// Sets the refresh rate in Hz of the display that shows the map.
MAP_TEXTURE_EXPORT int32_t map_texture_set_display_refresh_rate(int64_t handle,
                                                                double hz);
// Queries the features that the map renders in the quadrilateral with the
// corners `world_corners`: four points, each an x and a y in normalized Web
// Mercator coordinates (the world is [0, 1) in both directions, y increasing
// southwards). The map thread converts the corners with the camera of the last
// frame it rendered, and queries the smallest screen-aligned box that contains
// them. With `layer_ids` null, the query covers every style layer; otherwise
// only the `layer_id_count` layers it lists. `filter_json`, if non-null, is a
// MapLibre style-spec filter expression. The result is delivered as one
// MAP_TEXTURE_EVENT_QUERY_RESULT event with `request_id`; the results of a
// map's queries arrive in the order of the calls. Before the map has rendered
// a frame, the result is an empty array.
MAP_TEXTURE_EXPORT int32_t map_texture_query_rendered_features(
    int64_t handle, int64_t request_id, const double* world_corners,
    const char* const* layer_ids, int32_t layer_id_count,
    const char* filter_json);
// Sets the keys of the JSON object `state_json` in the feature state of the
// feature `feature_id` of the source `source_id`, and of its source layer
// `source_layer_id` if non-null. A numeric feature ID is given as its decimal
// text. The map reports a failure as MAP_TEXTURE_EVENT_RENDER_ERROR.
MAP_TEXTURE_EXPORT int32_t map_texture_set_feature_state(
    int64_t handle, const char* source_id, const char* source_layer_id,
    const char* feature_id, const char* state_json);
// Removes feature state of the source `source_id`, and of its source layer
// `source_layer_id` if non-null: the key `key` of the feature `feature_id`,
// every key of that feature with `key` null, or the state of every feature
// with both null. A key without a feature ID is invalid.
MAP_TEXTURE_EXPORT int32_t map_texture_remove_feature_state(
    int64_t handle, const char* source_id, const char* source_layer_id,
    const char* feature_id, const char* key);

// Overlays: GeoJSON that the map draws with style layers of its own among the
// style's layers, in the loaded style and in every style loaded later. An
// overlay has GeoJSON sources, each at an index, and style layers. Its
// sources have the IDs `mapigrade-overlay-<overlay_id>-source-<source_index>`,
// and its style layers the IDs `mapigrade-overlay-<overlay_id>-<n>` for the
// n-th layer of the array. An overlay is drawn once it has at least one style
// layer and every source its style layers name.
//
// The options of a source, a bit set; they are fixed when the source is
// added, so an option change on an index removes the source and adds it
// again, with the overlay's layers.
#define MAP_TEXTURE_SOURCE_LINE_METRICS 1
// Copies the UTF-8 GeoJSON `geojson` of `length` bytes and gives it, with the
// options `source_options`, to the overlay's source `source_index`. MapLibre
// prepares it in the background, and reports GeoJSON it can't use as
// MAP_TEXTURE_EVENT_RENDER_ERROR. Returns MAP_TEXTURE_ERROR_INVALID_ARGUMENT
// for empty GeoJSON, a negative index or unknown options; then `*out_error`,
// if non-null, is the message, to free with map_texture_string_free().
MAP_TEXTURE_EXPORT int32_t map_texture_overlay_set_source(
    int64_t handle, int64_t overlay_id, int32_t source_index,
    int32_t source_options, const uint8_t* geojson, int64_t length,
    char** out_error);
// Removes the overlay's source `source_index`. Nothing happens when the
// overlay has no such source.
MAP_TEXTURE_EXPORT int32_t map_texture_overlay_remove_source(
    int64_t handle, int64_t overlay_id, int32_t source_index);
// Sets the overlay's style layers, placement and order key. `layers_json` is
// a JSON array of style layer objects, in draw order, whose `id` members are
// the layer IDs above and whose `source` members are source IDs of the
// overlay; an array with other IDs or sources is rejected. `placement_kind`
// is 0 for below the labels, 1 for below the style layer `below_layer_id`, 2
// for the top. Overlays at the same place are drawn in increasing
// (`order_child`, `order_seq`). A layer that MapLibre rejects, or a missing
// `below_layer_id`, is reported as MAP_TEXTURE_EVENT_RENDER_ERROR or
// MAP_TEXTURE_EVENT_LOADING_FAILED.
MAP_TEXTURE_EXPORT int32_t map_texture_overlay_set_layers(
    int64_t handle, int64_t overlay_id, const char* layers_json,
    int32_t placement_kind, const char* below_layer_id, int64_t order_child,
    int64_t order_seq);
// Removes the overlay's style layers and sources from the map.
MAP_TEXTURE_EXPORT int32_t map_texture_overlay_remove(int64_t handle,
                                                      int64_t overlay_id);
MAP_TEXTURE_EXPORT int32_t map_texture_get_stats(int64_t handle,
                                                 map_texture_stats* out_stats);
// Releases the map and its resources, and unregisters the textures. Returns
// without waiting for the map thread to stop; the release finishes later. No
// events are delivered after this returns.
MAP_TEXTURE_EXPORT int32_t map_texture_dispose(int64_t handle);

MAP_TEXTURE_EXPORT void map_texture_event_free(map_texture_event* event);

// The number of threads in this process, for the lifecycle test.
MAP_TEXTURE_EXPORT int32_t map_texture_process_thread_count(void);
// For tests, on macOS and iOS: the name of each thread of this process, one per
// line, with an empty line for a thread without a name, or null on failure.
// Free the result with map_texture_string_free(). Not defined on Android.
MAP_TEXTURE_EXPORT char* map_texture_process_thread_names_for_testing(void);

// The device's thermal state, for measurements: 0 nominal, 1 fair, 2 serious,
// 3 critical (NSProcessInfoThermalState), or -1 if unknown.
MAP_TEXTURE_EXPORT int32_t map_texture_thermal_state(void);

// The process's memory use in bytes, for measurements, or -1 if unknown: on
// macOS and iOS the physical memory footprint (the value Xcode's memory gauge
// shows), on Android the proportional set size (PSS).
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

// For tests, on the platform thread: waits until the release of every disposed
// map has finished. Returns 1, or 0 if that takes longer than `timeout_ms`.
MAP_TEXTURE_EXPORT int32_t map_texture_wait_for_releases_for_testing(
    int64_t timeout_ms);
// For tests: pauses (non-zero) or resumes (zero) rendering of every map, as
// the platform does when the application enters the background or foreground.
MAP_TEXTURE_EXPORT void map_texture_set_paused_for_testing(int32_t paused);
// For tests: asks every map to release cached renderer resources, as the
// platform does after a memory warning.
MAP_TEXTURE_EXPORT void map_texture_reduce_memory_use_for_testing(void);
// For tests, on Android: with `restore` zero, releases the image readers the
// maps render into, as the plugin does when the activity stops; with `restore`
// non-zero, creates them again, as it does when the activity starts. Call on
// the platform thread. Does nothing on macOS and iOS.
MAP_TEXTURE_EXPORT void map_texture_trim_surfaces_for_testing(int32_t restore);
// For tests: writes to `out_x` and `out_y` the logical position at which
// MapLibre's projection of the view of the last frame the map rendered places
// the coordinate. Returns MAP_TEXTURE_ERROR_INVALID_ARGUMENT before the first
// frame or when the projection fails.
MAP_TEXTURE_EXPORT int32_t map_texture_project_for_testing(int64_t handle,
                                                           double latitude,
                                                           double longitude,
                                                           double* out_x,
                                                           double* out_y);
// For tests: 1 if the map is at rest, so that it renders no other frame
// without new input, as the map thread reports at the end of its next loop
// iteration; 0 if not, and MAP_TEXTURE_ERROR_DISPOSED for a disposed map.
MAP_TEXTURE_EXPORT int32_t map_texture_at_rest_for_testing(int64_t handle);

#ifdef __cplusplus
}
#endif

#endif  // MAP_TEXTURE_API_H
