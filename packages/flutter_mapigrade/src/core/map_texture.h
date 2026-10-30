// One map rendered into a Flutter texture: the map thread that owns the
// MapLibre runtime, map and render session, the command queue from Dart, and
// for a buffer target, the buffer state shared with Flutter's raster thread.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <map>
#include <set>

#include "buffer_state.h"
#include "command_queue.h"
#include "map_texture_api.h"
#include "mln.h"
#include "overlay.h"
#include "projection.h"
#include "render_gate.h"
#include "render_target.h"

namespace map_texture {

// Owns a prepared GeoJSON handle. The map keeps it as long as its overlay
// exists, so the source can be added again after each style load.
struct PreparedGeoJson {
  explicit PreparedGeoJson(mln_geojson_source_data handle) : handle(handle) {}
  PreparedGeoJson(const PreparedGeoJson&) = delete;
  PreparedGeoJson& operator=(const PreparedGeoJson&) = delete;
  ~PreparedGeoJson() { mln_geojson_source_data_release(handle); }

  const mln_geojson_source_data handle;
};

// One entry of mln_map_list_style_layers(), for tests.
struct StyleLayerInfo {
  std::string id;
  std::string type;
  std::string source;
};

// Headers for requests whose URL matches the glob `url`.
struct HttpHeaderRule {
  std::string url;
  // Names and values.
  std::vector<std::pair<std::string, std::string>> headers;
};

// A rendered feature query: the corners of the queried area, and the options.
struct RenderedQuery {
  int64_t request_id = 0;
  WorldPoint corners[4];
  // Nothing for every style layer.
  std::optional<std::vector<std::string>> layer_ids;
  std::optional<std::string> filter;
};

class MapTexture : public std::enable_shared_from_this<MapTexture> {
 public:
  // Creates the platform render target with the textures of the engine of
  // the token `engine`, starts the map thread, and waits until the thread has
  // created the runtime and map. With `copy_free`, the session renders
  // directly into the display buffers. With `maximum_cache_size`, the maximum
  // size in bytes of the runtime's tile cache is that value; otherwise it is
  // MapLibre's default.
  // Returns null on failure and sets `out_error`.
  static std::shared_ptr<MapTexture> Create(
      int64_t handle, int64_t engine, double pixel_ratio, bool copy_free,
      std::optional<uint64_t> maximum_cache_size,
      std::vector<HttpHeaderRule> header_rules,
      map_texture_event_callback callback, std::string* out_error);

  ~MapTexture();

  // The token of the engine whose textures the map registered with.
  int64_t engine() const { return engine_; }

  // The display slots and the Flutter texture id of each.
  int slot_count() const;
  int64_t texture_id(int slot) const;

  // Commands. Any thread; they queue work and wake the map thread.
  void LoadStyleUrl(std::string url);
  void LoadStyleJson(std::string json);
  // `seq` is the camera's sequence number.
  void SetCamera(const Camera& camera, int64_t seq);
  void Resize(const Viewport& viewport);
  // The display's refresh rate in Hz, or 0 if unknown.
  void SetDisplayRefreshRate(double hz);
  // Asks the renderer to release cached resources it can rebuild.
  void ReduceMemoryUse();
  // Queues `query` for the map thread, which reports its result as a
  // MAP_TEXTURE_EVENT_QUERY_RESULT event.
  void QueryRenderedFeatures(RenderedQuery query);
  // `state` is a JSON object whose keys are set on the feature.
  void SetFeatureState(FeatureStateTarget feature, std::string state);
  void RemoveFeatureState(FeatureStateTarget feature);
  // Overlays (design D198): the map keeps each overlay's sources, style
  // layers, placement and order key, and installs it in the loaded style and
  // again in every style loaded later (D201).
  void OverlaySetSource(int64_t id, int32_t source_index, int32_t source_options,
                        std::shared_ptr<PreparedGeoJson> data);
  void OverlayRemoveSource(int64_t id, int32_t source_index);
  // `layers` are JSON objects with the IDs OverlayLayerId(id, n), in order;
  // `layer_sources` are the indexes of the overlay's sources they name.
  void OverlaySetLayers(int64_t id, std::vector<std::string> layers,
                        std::vector<int32_t> layer_sources, Placement placement,
                        OrderKey order);
  void OverlayRemove(int64_t id);

  // Any thread except the map thread. While paused, the map thread submits no
  // GPU work; pausing returns after a render in progress has ended. Resuming
  // renders a pending frame with the latest camera.
  void SetPaused(bool paused);

  // Work of a surface target on the map thread: `session` is the render
  // session (MLN_HANDLE_NULL before the first resize) and `size` the size the
  // map renders at.
  using TargetTask =
      std::function<void(mln_render_session session, const TargetSize& size)>;

  // Any thread except the map thread. Runs `task` on the map thread, ordered
  // with the other commands, and then renders the pending frame with the latest
  // camera once the target can present. With `wait`, returns after the task has
  // run, or after the map thread has stopped if it stops first.
  void RunTargetTask(TargetTask task, bool wait);

  // Any thread. Reports a render error to Dart, for errors of the platform
  // render target.
  void ReportRenderError(const std::string& message);

  // Stops the map thread after it has destroyed the session, map and
  // runtime, then unregisters the texture. After this returns no events are
  // delivered.
  void Dispose();

  // Any thread except the map thread, for a surface target: marks every slot
  // free, so that Dart's choice of a frame from before the call is refused.
  // The target releases the slots' images in SlotFreed.
  void ResetSlots();

  // The platform thread: Dart chooses the newest finished frame for the Flutter
  // frame it builds. If a frame is finished that Dart hasn't chosen, records
  // the choice, marks the slot's texture available, sets `out_slot` and
  // `out_info`, and returns true; otherwise returns false and records nothing.
  // For a surface target, the choice gives the frame's image to Flutter and
  // reports a frame-displayed event without a display time.
  bool SelectNewest(int* out_slot, FrameInfo* out_info);

  // The thread that receives a surface target's images: the image of the
  // frame `frame_id` arrived. If a slot queues the frame, publishes it, runs
  // `on_published(slot)` under the BufferState lock so that the target can
  // keep the image for the slot, reports a frame-ready event and returns
  // true. Otherwise returns false, and the caller releases the image.
  bool OnFrameImage(uint64_t frame_id,
                    const std::function<void(int slot)>& on_published);

  // Flutter's raster thread, for a buffer target. Presents `slot` and returns
  // its buffer, retained, through BufferRenderTarget::CopyBufferLocked, or
  // the fallback if Dart hasn't chosen the slot's frame.
  // Reports a frame-displayed event with the display time when the frame is
  // new.
  void* Present(int slot);

  map_texture_stats stats();

  // For tests: the view of the last frame the session rendered, or nothing
  // before the first.
  std::optional<RenderedView> LastRenderedViewForTesting();
  // For tests, any thread: the style's layers in style order, as
  // mln_map_list_style_layers() reports them after every command accepted so
  // far, or nothing if the query doesn't complete within five seconds.
  std::optional<std::vector<StyleLayerInfo>> ListStyleLayersForTesting();

 private:
  MapTexture(int64_t handle, int64_t engine, double pixel_ratio,
             std::optional<uint64_t> maximum_cache_size,
             std::vector<HttpHeaderRule> header_rules,
             map_texture_event_callback callback);

  bool Start(bool copy_free, std::string* out_error);
  void Run();
  // One iteration of the map thread's loop; returns true to stop.
  bool RunOnce();
  // Whether the map thread should arm a frame demand now rather than park.
  bool RenderWanted();
  // Parks the map thread until Signal() or `timeout_ms` passes.
  void WaitForWake(int64_t timeout_ms);
  // Services the session's driver work until `done` returns true, for the
  // completions of attach, detach and target replacement.
  void ServiceUntil(const std::function<bool()>& done);
  void ApplyReduceMemoryUse();
  // Map thread: submits the set or remove of a kSetFeatureState or
  // kRemoveFeatureState command, and reports a failure as a render error.
  void ApplyFeatureState(const Command& command);
  // Map thread: updates the overlay state from a kOverlay* command.
  void ApplyOverlayCommand(Command& command);
  // Map thread: notes a style load, reconciles the overlays with a layer list
  // that has arrived, and queries the list when the overlays changed
  // (designs D199 and D201).
  void SyncOverlays();
  void RequestLayerList();
  // Map thread: submits the commands that install the overlays in the style,
  // whose layers are `layers`.
  void ReconcileOverlays(const std::vector<StyleLayer>& layers);
  // A completion for an overlay command on `target` (a source or layer ID)
  // that reports a failure as a render error naming `what` (design D203).
  // With `ignore_not_found`, MLN_STATUS_NOT_FOUND isn't reported: removing
  // what a style load removed already, or updating a source it removed, is
  // no failure.
  mln_completion OverlayCompletion(const char* what, const std::string& target,
                                   bool ignore_not_found);
  void RemoveOverlayLayer(const std::string& id);
  void RemoveOverlaySource(const std::string& id);
  struct Overlay;
  struct OverlaySource;
  // Map thread: adds the source `index` of the overlay `id` from its data,
  // after removing it when it is submitted.
  void AddOverlaySource(int64_t id, int32_t index, OverlaySource& source);
  // Map thread: adds every source of the overlay that isn't submitted, and
  // with `readd_changed_options`, which needs the overlay's layers removed
  // from the style, every source whose options changed since it was submitted.
  void AddOverlaySources(int64_t id, Overlay& overlay,
                         bool readd_changed_options);
  void DestroySession();
  // Map thread: attaches a render session to the map at size_; returns
  // whether the attachment completed.
  bool AttachSession();
  // Map thread: if the session lost its target, replaces it with a new one;
  // returns whether it did.
  bool RecoverLostTarget();
  bool Init();
  void Teardown();
  void Signal();
  // The wake callback of the session's driver-work and frame-result wakes.
  static void OnWake(void* user_data);

  void ApplyCommands(bool* stop);
  void ApplyResize(const Viewport& viewport);
  // Map thread: ends the demands that haven't started with a barrier, and
  // services the session until it completes.
  void EndDemands();
  void ApplyCamera();
  // Map thread: waits until the completion of every submitted camera command
  // has run.
  void WaitForCamera();
  // The runtime's event handler, on the runtime's scheduler thread.
  static void OnEvents(void* user_data, const mln_event_batch_view* events);
  void MaybeRender();
  // The copy path.
  void RenderIntoBuffer(BufferRenderTarget& target);
  // A target that renders into the buffers.
  void RenderIntoRing(BufferRenderTarget& target);
  void RenderIntoSurface(SurfaceRenderTarget& target);
  // Map thread: requests a frame that renders into `slot`, or with -1, into
  // the slot the session chooses. Returns false and releases the slot if the
  // session refuses the demand.
  bool ArmDemand(int slot, bool render_ahead);
  // Map thread: services the session's driver work, which renders the
  // armed demand's frame, and handles the frame results.
  void ServiceDriver();
  // Map thread: drains and handles the session's frame results, for a service
  // call that started at `service_start` and took `service_ns`.
  void DrainFrameResults(int64_t service_start, int64_t service_ns);
  void HandleFrameResult(const mln_render_frame_result& result,
                         int64_t service_start, int64_t service_ns);
  // Map thread: runs the queued queries against the last rendered frame, with
  // no frame demand armed, and reports their results in order.
  void RunQueries();
  void EmitQueryResult(int64_t request_id, int32_t status,
                       const std::string& message);
  // Map thread: acquires and releases the rendered frames, so that their GPU
  // writes have completed.
  void AcquireAndReleaseFrame();
  // Map thread, for a target that renders into the buffers: acquires the
  // newest rendered frame and holds it while its display slot isn't free, and
  // releases older ones. Returns the slot, marked rendering, or -1 if no
  // frame could be held.
  int HoldRenderedFrame(BufferRenderTarget& target);
  // Map thread: releases the held frames of the slots that are free, so that
  // the session may render into them again, or with `all`, every held frame,
  // before a replacement of the ring or a detach.
  void ReleaseHeldFrames(bool all);
  // Map thread, for a target that renders into the buffers: whether a slot is
  // free; otherwise records the skipped render, as AcquireSlot() does.
  bool FreeSlotAvailable();
  // Map thread, for a buffer target: whether the next frame may render now,
  // because Dart has chosen the latest frame or the map renders ahead.
  // Otherwise records the wait. Sets `render_ahead`.
  bool MayRender(bool* render_ahead);
  // Map thread, for a surface target: the time until the next render may
  // start, or 0 if it may start now.
  int64_t IntervalRemainingNs();
  // Map thread: acquires a free slot to render into, or returns -1 and
  // records the skipped render.
  int AcquireSlot();
  // Map thread: records the stats of a render that is about to start.
  void RecordRenderStart(int64_t start, bool render_ahead);
  // Map thread: records the time of a service call that rendered a frame.
  void RecordRender(int64_t start, int64_t elapsed);
  // Map thread: the frame of `result`, with the camera it was rendered with
  // and the sequence number of the newest camera command it includes.
  FrameInfo RenderedFrameInfo(const mln_render_frame_result& result);
  // Before a frame-ready event: counts the camera-to-frame latency of the
  // frame's camera if this is the first frame rendered with it.
  void RecordCameraLatency(const FrameInfo& info);
  // Map thread: whether to render without waiting until Dart has chosen the
  // latest frame.
  bool RenderAhead();
  void MaybeNotifyAfterResize();

  // The process-global MapLibre log callback. MapLibre reports a failed glyph
  // load only as an error record, not as a map event; the record is passed to
  // the map whose thread logged it, as a load failure.
  static uint32_t OnLogRecord(void* user_data, uint32_t severity,
                              uint32_t event, int64_t code,
                              const char* message);

  void Emit(int32_t type, const char* message = nullptr,
            const FrameInfo* frame = nullptr, int64_t display_time_us = 0,
            int slot = 0);
  void ReportStatus(const char* what, mln_status status,
                    const mln_diagnostic* diagnostic = nullptr);
  // ReportStatus() that also sets init_error_.
  void ReportInitStatus(const char* what, mln_status status,
                        const mln_diagnostic* diagnostic = nullptr);
  // A completion that reports a failure of `what` as a render error, and
  // otherwise runs `on_success` with the result, on the completing thread.
  // Then it runs `on_done` either way.
  mln_completion ReportingCompletion(
      const char* what,
      std::function<void(const mln_completion_result&)> on_success = nullptr,
      std::function<void()> on_done = nullptr);

  const int64_t handle_;
  const int64_t engine_;
  const double initial_pixel_ratio_;
  const std::optional<uint64_t> maximum_cache_size_;

  // Fixed after the constructor. The runtime copies them into its native
  // header rules.
  const std::vector<HttpHeaderRule> header_rules_;

  std::unique_ptr<RenderTarget> target_;
  CommandQueue commands_;
  BufferState buffers_;
  RenderGate gate_;

  std::thread thread_;
  std::mutex init_mutex_;
  std::condition_variable init_cv_;
  bool init_done_ = false;
  bool init_ok_ = false;
  // Why Init() failed; map thread until init_done_.
  std::string init_error_;

  // Wakes the map thread: commands, Dart's frame choices, and the session's
  // driver-work and frame-result wakes signal it.
  std::mutex wake_mutex_;
  std::condition_variable wake_cv_;
  bool woken_ = false;

  // Guards target_tasks_stopped_, which the map thread sets when it stops, so
  // that no target task is queued after that.
  std::mutex target_tasks_mutex_;
  bool target_tasks_stopped_ = false;

  // Guards callback_; cleared at dispose so that no event follows it.
  std::mutex callback_mutex_;
  map_texture_event_callback callback_;

  // Map thread state.
  mln_runtime runtime_ = MLN_HANDLE_NULL;
  mln_map map_ = MLN_HANDLE_NULL;
  mln_render_session session_ = MLN_HANDLE_NULL;
  TargetSize size_{};
  Viewport viewport_{};
  uint64_t next_frame_id_ = 1;
  // The view of the last frame the session rendered, published or not: the
  // view that a rendered query reads. Written on the map thread; the mutex is
  // for LastRenderedViewForTesting().
  std::mutex rendered_view_mutex_;
  std::optional<RenderedView> rendered_view_;
  // Map thread: frame results with the disposition RENDERED.
  uint64_t rendered_results_ = 0;
  // Queries that the map thread hasn't run yet, in the order of the calls.
  std::mutex queries_mutex_;
  std::vector<RenderedQuery> queries_;
  // A query returns the feature state of the last rendered frame, so queries
  // wait until a frame includes every feature-state command submitted before
  // them: the commands submitted (map thread) and completed (any thread), the
  // newest render update generation that a completed one is part of, and the
  // map update generation of the last rendered frame (map thread).
  int64_t feature_state_submitted_ = 0;
  std::atomic<int64_t> feature_state_completed_{0};
  std::atomic<uint64_t> feature_state_generation_{0};
  uint64_t rendered_update_generation_ = 0;

  // The overlays (design D198), map thread. Each is what Dart asked for, and
  // what the map thread last submitted for it: the versions count the
  // changes, and a version equal to its submitted value is installed, or
  // being installed. `submitted` is cleared by a style load, which removes
  // every runtime source.
  struct OverlaySource {
    std::shared_ptr<PreparedGeoJson> data;
    int32_t options = 0;
    uint64_t data_version = 0;
    uint64_t data_submitted = 0;
    bool submitted = false;
    int32_t submitted_options = 0;
  };
  struct Overlay {
    std::map<int32_t, OverlaySource> sources;
    // IDs of sources removed from `sources` that may still be in the style.
    std::vector<std::string> sources_to_remove;
    std::vector<std::string> layers;
    std::vector<int32_t> layer_sources;
    uint64_t layers_version = 0;
    uint64_t layers_submitted = 0;
    Placement placement;
    OrderKey order;
  };
  std::map<int64_t, Overlay> overlays_;
  // Sources of removed overlays that may still be in the style.
  std::vector<std::string> overlay_sources_to_remove_;
  // Whether the overlays changed since the layer list was last queried.
  bool overlays_dirty_ = false;
  // Whether a style has loaded; before that, there is nothing to place the
  // overlays in.
  bool style_loaded_ = false;
  // The kBelowLayer IDs reported missing since the last style load.
  std::set<std::string> missing_anchors_reported_;
  // Style loads the runtime reported (OnEvents) and the map thread has seen.
  std::atomic<uint64_t> style_loads_{0};
  uint64_t style_loads_seen_ = 0;
  // Style commands the map thread submitted.
  uint64_t style_commands_ = 0;
  // The pending layer list query: whether there is one, and the style
  // commands and loads at its submission, so that a list from before a style
  // change is dropped.
  bool layer_list_pending_ = false;
  uint64_t layer_list_style_commands_ = 0;
  uint64_t layer_list_style_loads_ = 0;
  struct LayerList {
    int32_t status = 0;
    std::string diagnostic;
    std::vector<StyleLayer> layers;
  };
  // Written by the query's completion, on any thread.
  std::mutex layer_list_mutex_;
  std::optional<LayerList> layer_list_;
  // The sequence number of the newest camera that a rendered frame includes,
  // and when Dart set it.
  int64_t applied_seq_ = 0;
  int64_t applied_set_at_ns_ = 0;
  // The frame demand the map thread armed and hasn't received a result for:
  // its token, the display slot it renders into, whether it renders ahead,
  // and whether a resize reset the slots since it was armed.
  bool demand_outstanding_ = false;
  uint64_t demand_token_ = 0;
  int demand_slot_ = -1;
  bool demand_render_ahead_ = false;
  bool demand_stale_ = false;
  // Whether the last frame asked for another without a map update, as during
  // a paint transition, so the next demand renders unconditionally.
  bool repaint_wanted_ = false;
  // Whether the Metal ring's frames are acquired to wait for the producer's
  // GPU writes; false after acquisition reported UNSUPPORTED.
  bool acquire_frames_ = true;

  // The map snapshot generation that each camera command published, with the
  // camera's sequence number and when Dart set it. Written by the command's
  // completion, on any thread.
  struct CameraGeneration {
    uint64_t generation = 0;
    int64_t seq = 0;
    int64_t set_at_ns = 0;
  };
  std::mutex camera_generations_mutex_;
  std::vector<CameraGeneration> camera_generations_;
  // Camera commands whose completion has run, and camera commands submitted
  // by the map thread.
  std::atomic<int64_t> cameras_completed_{0};
  int64_t cameras_submitted_ = 0;
  // When to tell Flutter once more that a frame is available after the last
  // resize (steady clock, ns), or 0 for not pending.
  int64_t notify_after_resize_at_ns_ = 0;
  // Set when a render was deferred because Dart hadn't chosen the latest
  // frame or no slot was free; SelectNewest() and Present() wake the map
  // thread.
  std::atomic<bool> waiting_for_buffer_{false};
  // Timing stats (steady clock, ns): when the last frame was published, when
  // Flutter last took a frame, and when Dart last chose a frame, written by
  // different threads.
  std::atomic<int64_t> published_at_ns_{0};
  std::atomic<int64_t> presented_at_ns_{0};
  std::atomic<int64_t> selected_at_ns_{0};
  // Map thread: when the last render_update started.
  int64_t last_render_start_ns_ = 0;
  // Map thread: the smoothed time of render_update plus the copy, and whether
  // the map currently renders ahead.
  int64_t frame_cost_avg_ns_ = 0;
  bool rendering_ahead_ = false;
  // The display's refresh interval, or 0 if unknown.
  std::atomic<int64_t> display_interval_ns_{0};
  // Map thread: whether the next render waited for Dart to choose the latest
  // frame.
  bool render_waited_for_display_ = false;
  // Map thread, for a surface target: whether the pending render has been
  // counted in interval_waits.
  bool interval_wait_counted_ = false;
  // Whether a frame id arrived that no slot ever queued, which is reported
  // once.
  std::atomic<bool> unknown_frame_reported_{false};

  std::mutex stats_mutex_;
  map_texture_stats stats_{};
  // Guarded by stats_mutex_: the newest camera whose latency was counted.
  int64_t latency_counted_seq_ = 0;
  // Map thread: the acquired frame that each display slot holds, for a target
  // that renders into the buffers.
  std::array<mln_acquired_frame, kMaxBufferCount> held_frames_{};
};

// Pauses or resumes every live map, and maps created while paused start
// paused. The platform calls this when the application can't use the GPU, for
// example while an iOS app is in the background. Defined in
// map_texture_api.cpp.
void SetAllPaused(bool paused);

// Queues ReduceMemoryUse() for every live map, for example after an iOS
// memory warning. Defined in map_texture_api.cpp.
void ReduceAllMemoryUse();

// Disposes every live map with the engine token `engine`, as
// map_texture_dispose() does; later calls with their handles return
// MAP_TEXTURE_ERROR_DISPOSED. The platform calls this when the engine detaches
// the plugin. Defined in map_texture_api.cpp.
void DisposeEngineMaps(int64_t engine);

// For tests and measurements: when maps render without waiting until Dart has
// chosen the latest frame. kAuto (the default) renders ahead while a frame
// takes longer than a display refresh interval.
enum class RenderAheadMode { kAuto, kNever, kAlways };
void SetRenderAheadModeForTesting(RenderAheadMode mode);

// For tests: the clock the map thread paces renders by and records render
// starts with, in nanoseconds, or null for the steady clock.
void SetClockForTesting(int64_t (*now_ns)());

}  // namespace map_texture
