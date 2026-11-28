import 'dart:typed_data';
import 'dart:ui';

import 'map_texture_controller_ffi.dart'
    if (dart.library.js_interop) 'map_texture_controller_web.dart'
    as platform;
import 'native_library.dart';

/// A map camera: center, zoom and bearing in degrees.
class MapCamera {
  /// A camera at [latitude], [longitude] and [zoom], turned by [bearing].
  const MapCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    this.bearing = 0,
  });

  /// The latitude of the center, in degrees.
  final double latitude;

  /// The longitude of the center, in degrees.
  final double longitude;

  /// The MapLibre zoom level.
  final double zoom;

  /// The bearing in degrees.
  final double bearing;

  @override
  String toString() =>
      'MapCamera(lat: $latitude, lon: $longitude, zoom: $zoom, bearing: $bearing)';
}

/// What moved the camera last before a frame; `MAP_TEXTURE_CAMERA_SOURCE_*`.
enum NativeCameraSource {
  /// A camera command, or the map itself.
  command,

  /// A gesture of the gesture recognizer.
  gesture,

  /// The glide or snap after a gesture.
  momentum,
}

/// The camera fields of a frame beyond its center, zoom and bearing, the
/// matrix it drew the map with, and what moved its camera; see
/// `map_texture_frame_view` in `map_texture_api.h`.
class FrameView {
  /// A frame view with the given values.
  const FrameView({
    required this.pitch,
    required this.centerAltitude,
    required this.paddingTop,
    required this.paddingLeft,
    required this.paddingBottom,
    required this.paddingRight,
    required this.roll,
    required this.fieldOfView,
    required this.matrix,
    required this.clipDepthRange,
    required this.cameraSource,
    required this.mapUpdateGeneration,
  });

  /// The pitch in degrees.
  final double pitch;

  /// The altitude of the center in meters.
  final double centerAltitude;

  /// The top padding in logical pixels.
  final double paddingTop;

  /// The left padding in logical pixels.
  final double paddingLeft;

  /// The bottom padding in logical pixels.
  final double paddingBottom;

  /// The right padding in logical pixels.
  final double paddingRight;

  /// The roll in degrees.
  final double roll;

  /// The vertical field of view in degrees.
  final double fieldOfView;

  /// The frame's clip matrix, column-major: Web Mercator x and y in [0, 1)
  /// and z in meters to clip space.
  final Float64List matrix;

  /// `mln_clip_depth_range`: 1 for clip z from 0 to w, 2 for -w to w.
  final int clipDepthRange;

  /// What moved the camera last before the frame.
  final NativeCameraSource cameraSource;

  /// The map update that the frame shows.
  final int mapUpdateGeneration;
}

/// The camera and viewport size a frame was rendered with, and where it is.
class FrameCamera {
  /// The camera and viewport size of the frame [frameId].
  const FrameCamera({
    required this.frameId,
    required this.camera,
    required this.physicalSize,
    required this.scaleFactor,
    required this.displayTime,
    this.slot = 0,
    this.seq = 0,
    this.view,
  });

  /// The rest of the frame's camera and its matrix, for a map that reports
  /// them. Fakes in tests may leave it null.
  final FrameView? view;

  /// Increases by one for each frame the map renders.
  final int frameId;

  /// The camera the frame was rendered with.
  final MapCamera camera;

  /// The display slot that holds the frame: an index into
  /// [MapTextureController.textureIds].
  final int slot;

  /// The sequence number that [MapTextureController.setCamera] returned for
  /// the camera the frame was rendered with, or 0 if the frame was rendered
  /// before the first call.
  final int seq;

  /// The size of the frame in physical pixels.
  final Size physicalSize;

  /// Physical pixels per logical pixel of the frame.
  final double scaleFactor;

  /// On macOS and iOS, the time at which Flutter took the frame for display,
  /// in microseconds on the clock of [FrameTiming.timestampInMicroseconds], so
  /// that the frame can be matched to the Flutter frame whose rasterization
  /// displayed it.
  ///
  /// Null on Android, where Flutter reports no time at which it takes a frame.
  /// There the frame is reported when Dart chooses it for display. Also
  /// null for the frames of [MapTextureController.readyFrames], which haven't
  /// been displayed.
  final int? displayTime;

  @override
  String toString() =>
      'FrameCamera(#$frameId, $camera, ${physicalSize.width.toInt()}x${physicalSize.height.toInt()} @$scaleFactor, slot $slot, seq $seq)';
}

/// An event reported by the map.
sealed class MapEvent {
  const MapEvent();
}

/// The style has loaded.
class StyleLoaded extends MapEvent {
  /// A style-loaded event.
  const StyleLoaded();
}

/// Loading the style (or a resource it needs) failed.
class LoadingFailed extends MapEvent {
  /// A loading failure with [message].
  const LoadingFailed(this.message);

  /// Describes the cause of the failure.
  final String message;
}

/// Rendering failed.
class RenderError extends MapEvent {
  /// A render error with [message].
  const RenderError(this.message);

  /// Describes the cause of the error.
  final String message;
}

/// The map has loaded all resources for the current camera and stopped
/// rendering.
class MapIdle extends MapEvent {
  /// An idle event.
  const MapIdle();
}

/// A camera command of a map that owns its camera ended.
class CameraTransitionEnded extends MapEvent {
  /// The end of the command [requestId] with the `MAP_TEXTURE_OUTCOME_*`
  /// [outcome].
  const CameraTransitionEnded(this.requestId, this.outcome);

  /// The request id that the command was given.
  final int requestId;

  /// 0 completed, 1 cancelled, 2 closed, 3 replaced.
  final int outcome;
}

/// Nothing moves the camera of a map that owns its camera any more. Frames
/// whose [FrameView.mapUpdateGeneration] is at least [mapUpdateGeneration]
/// show the camera at rest.
class CameraSettled extends MapEvent {
  /// A settled event.
  const CameraSettled(this.mapUpdateGeneration);

  /// The first map update that shows the camera at rest.
  final int mapUpdateGeneration;
}

/// A camera for the native map: the fields that [fields] sets, as the bits
/// `MAP_TEXTURE_CAMERA_*` of `map_texture_api.h`.
class NativeCamera {
  /// A native camera with the given values.
  const NativeCamera({
    required this.fields,
    this.latitude = 0,
    this.longitude = 0,
    this.centerAltitude = 0,
    this.paddingTop = 0,
    this.paddingLeft = 0,
    this.paddingBottom = 0,
    this.paddingRight = 0,
    this.zoom = 0,
    this.bearing = 0,
    this.pitch = 0,
    this.roll = 0,
    this.fieldOfView = 0,
  });

  /// The bits of the fields that are set.
  final int fields;

  /// The center's latitude in degrees.
  final double latitude;

  /// The center's longitude in degrees.
  final double longitude;

  /// The center's altitude in meters.
  final double centerAltitude;

  /// The top padding in logical pixels.
  final double paddingTop;

  /// The left padding in logical pixels.
  final double paddingLeft;

  /// The bottom padding in logical pixels.
  final double paddingBottom;

  /// The right padding in logical pixels.
  final double paddingRight;

  /// The zoom.
  final double zoom;

  /// The bearing in degrees.
  final double bearing;

  /// The pitch in degrees.
  final double pitch;

  /// The roll in degrees.
  final double roll;

  /// The vertical field of view in degrees.
  final double fieldOfView;
}

/// The camera limits of the native map; `map_texture_limits`.
class NativeLimits {
  /// Limits with the given values, and with [south], [west], [north] and
  /// [east] when [hasBounds].
  const NativeLimits({
    required this.minZoom,
    required this.maxZoom,
    required this.minPitch,
    required this.maxPitch,
    this.hasBounds = false,
    this.south = 0,
    this.west = 0,
    this.north = 0,
    this.east = 0,
  });

  /// The minimum zoom.
  final double minZoom;

  /// The maximum zoom.
  final double maxZoom;

  /// The minimum pitch in degrees.
  final double minPitch;

  /// The maximum pitch in degrees.
  final double maxPitch;

  /// Whether the center is limited to the bounds.
  final bool hasBounds;

  /// The southern edge of the bounds in degrees.
  final double south;

  /// The western edge of the bounds in degrees.
  final double west;

  /// The northern edge of the bounds in degrees.
  final double north;

  /// The eastern edge of the bounds in degrees.
  final double east;
}

/// The area and options of a fit; `map_texture_fit`.
class NativeFit {
  /// A fit of the area from [south], [west] to [north], [east].
  const NativeFit({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    this.fields = 0,
    this.paddingTop = 0,
    this.paddingLeft = 0,
    this.paddingBottom = 0,
    this.paddingRight = 0,
    this.bearing = 0,
    this.pitch = 0,
  });

  /// The southern edge in degrees.
  final double south;

  /// The western edge in degrees.
  final double west;

  /// The northern edge in degrees.
  final double north;

  /// The eastern edge in degrees.
  final double east;

  /// 1 for the padding, 2 for the bearing, 4 for the pitch.
  final int fields;

  /// The top padding in logical pixels.
  final double paddingTop;

  /// The left padding in logical pixels.
  final double paddingLeft;

  /// The bottom padding in logical pixels.
  final double paddingBottom;

  /// The right padding in logical pixels.
  final double paddingRight;

  /// The bearing in degrees.
  final double bearing;

  /// The pitch in degrees.
  final double pitch;
}

/// The options of the gesture recognizer; `map_texture_gesture_options`.
class NativeGestureOptions {
  /// Options with the given values.
  const NativeGestureOptions({
    required this.pan,
    required this.zoom,
    required this.rotate,
    required this.pitch,
    required this.glides,
    required this.snapToNorth,
    required this.doubleTapZoom,
    required this.twoFingerTapZoom,
    required this.momentumModel,
    required this.halfLifeMs,
  });

  /// Whether drags pan.
  final bool pan;

  /// Whether gestures zoom.
  final bool zoom;

  /// Whether gestures turn the bearing.
  final bool rotate;

  /// Whether gestures change the pitch.
  final bool pitch;

  /// Whether releases glide.
  final bool glides;

  /// Whether the bearing snaps to north.
  final bool snapToNorth;

  /// Zoom levels of a double tap; 0 leaves double taps to Dart.
  final double doubleTapZoom;

  /// Zoom levels of a two-finger tap; 0 leaves them to Dart.
  final double twoFingerTapZoom;

  /// `mln_momentum_decay_model`: 0 friction, 1 curve.
  final int momentumModel;

  /// The half-life of friction.
  final double halfLifeMs;

  @override
  bool operator ==(Object other) =>
      other is NativeGestureOptions &&
      other.pan == pan &&
      other.zoom == zoom &&
      other.rotate == rotate &&
      other.pitch == pitch &&
      other.glides == glides &&
      other.snapToNorth == snapToNorth &&
      other.doubleTapZoom == doubleTapZoom &&
      other.twoFingerTapZoom == twoFingerTapZoom &&
      other.momentumModel == momentumModel &&
      other.halfLifeMs == halfLifeMs;

  @override
  int get hashCode => Object.hash(
    pan,
    zoom,
    rotate,
    pitch,
    glides,
    snapToNorth,
    doubleTapZoom,
    twoFingerTapZoom,
    momentumModel,
    halfLifeMs,
  );

  @override
  String toString() =>
      'NativeGestureOptions(pan: $pan, zoom: $zoom, rotate: $rotate, '
      'pitch: $pitch, glides: $glides, snapToNorth: $snapToNorth, '
      'doubleTapZoom: $doubleTapZoom, twoFingerTapZoom: $twoFingerTapZoom, '
      'momentumModel: $momentumModel, halfLifeMs: $halfLifeMs)';
}

/// The kinds of [GestureInput]; `mln_gesture_input_type`.
abstract final class GestureInputType {
  /// A pointer went down.
  static const pointerDown = 1;

  /// A pointer moved.
  static const pointerMove = 2;

  /// A pointer went up.
  static const pointerUp = 3;

  /// The platform took a pointer away.
  static const pointerCancel = 4;

  /// The modes that held keys select.
  static const modes = 5;

  /// Camera movement from a wheel, a trackpad scroll or keys.
  static const delta = 6;

  /// A pinch that the platform recognized.
  static const pinch = 7;
}

/// One input of the gesture recognizer; `map_texture_gesture_input`.
class GestureInput {
  /// An input of [type] with the fields that it uses.
  const GestureInput({
    required this.type,
    this.pointerId = 0,
    this.pointerKind = 0,
    this.modes = 0,
    this.position = Offset.zero,
    this.discrete = false,
    this.pan = Offset.zero,
    this.zoom = 0,
    this.bearing = 0,
    this.pitch = 0,
    this.scale = 1,
    this.rotation = 0,
    this.phase = 0,
  });

  /// A [GestureInputType].
  final int type;

  /// The pointer, for pointer inputs.
  final int pointerId;

  /// `mln_pointer_kind`: 0 mouse, 1 touch, 2 pen.
  final int pointerKind;

  /// `mln_gesture_mode` bits.
  final int modes;

  /// The pointer's position, a delta's position or a pinch's center.
  final Offset position;

  /// For a delta: whether it eases.
  final bool discrete;

  /// For a delta: how far the content moves, in logical pixels.
  final Offset pan;

  /// For a delta: zoom levels to add.
  final double zoom;

  /// For a delta: degrees to turn clockwise.
  final double bearing;

  /// For a delta: degrees to tilt.
  final double pitch;

  /// For a pinch: the scale since the last update.
  final double scale;

  /// For a pinch: degrees turned clockwise since the last update.
  final double rotation;

  /// For a pinch: the `mln_pinch_phase`.
  final int phase;

  @override
  String toString() =>
      'GestureInput(type: $type, id: $pointerId, kind: $pointerKind, '
      'modes: $modes, position: $position, discrete: $discrete, pan: $pan, '
      'zoom: $zoom, bearing: $bearing, pitch: $pitch, scale: $scale, '
      'rotation: $rotation, phase: $phase)';
}

/// The kinds of [GestureEvent]; `mln_gesture_event_type`.
abstract final class GestureEventType {
  /// A tap.
  static const tap = 1;

  /// The second tap of a double tap.
  static const doubleTap = 2;

  /// Two fingers tapped together.
  static const twoFingerTap = 3;

  /// A part reached a notch.
  static const notch = 4;

  /// A pointer stayed pressed and still for 500 ms.
  static const longPress = 5;
}

/// An event of the gesture recognizer; `map_texture_gesture_event`.
class GestureEvent {
  /// An event of [type].
  const GestureEvent({
    required this.type,
    this.pointerId = 0,
    this.position = Offset.zero,
    this.axis = 0,
    this.kind = 0,
    this.value = 0,
  });

  /// A [GestureEventType].
  final int type;

  /// For taps and long presses: the pointer.
  final int pointerId;

  /// For taps and long presses: the position in logical pixels.
  final Offset position;

  /// For notches: the `mln_gesture_axis`.
  final int axis;

  /// For notches: the notch's kind.
  final int kind;

  /// For notches: the value in the part's unit.
  final double value;
}

/// When the recognizer next needs a tick; `mln_gesture_next_tick`.
enum GestureNextTick {
  /// Not until the next input.
  none,

  /// Every display frame.
  frame,

  /// At [GestureResult.nextTickMs].
  at,
}

/// What an input or a tick did; `map_texture_gesture_result`.
class GestureResult {
  /// A result with the given values.
  const GestureResult({
    this.handled = false,
    this.nextTick = GestureNextTick.none,
    this.nextTickMs = 0,
    this.boxZoom,
    this.events = const [],
  });

  /// Whether the recognizer used the input.
  final bool handled;

  /// When the recognizer next needs a tick.
  final GestureNextTick nextTick;

  /// For [GestureNextTick.at].
  final double nextTickMs;

  /// The box of a box zoom that is being drawn, in logical pixels.
  final Rect? boxZoom;

  /// The events, in order.
  final List<GestureEvent> events;
}

/// Counters from the native map thread.
class MapTextureStats {
  /// Counters with the given values. The controller reads them from the map
  /// thread; tests that have no native map give them directly.
  const MapTextureStats({
    this.renderedFrames = 0,
    this.skippedRenders = 0,
    this.waitsForDisplay = 0,
    this.renderUpdateCount = 0,
    this.renderUpdateTotal = Duration.zero,
    this.renderUpdateMax = Duration.zero,
    this.copyCount = 0,
    this.copyTotal = Duration.zero,
    this.copyMax = Duration.zero,
    this.presentedFrames = 0,
    this.renderUpdateAvailableEvents = 0,
    this.needsRepaintFrames = 0,
    this.pausedRenders = 0,
    this.memoryReductions = 0,
    this.frameCycleCount = 0,
    this.frameCycleTotal = Duration.zero,
    this.pickupWaitCount = 0,
    this.pickupWaitTotal = Duration.zero,
    this.presentToRenderCount = 0,
    this.presentToRenderTotal = Duration.zero,
    this.renderAheadFrames = 0,
    this.intervalWaits = 0,
    this.maxSlotsInUse = 0,
    this.cameraLatencyCount = 0,
    this.cameraLatencyTotal = Duration.zero,
    this.cameraLatencyMax = Duration.zero,
  });

  /// Frames the map rendered.
  final int renderedFrames;

  /// Renders deferred because no display slot was free.
  final int skippedRenders;

  /// Renders deferred because Dart hadn't chosen the latest finished frame
  /// yet, on macOS and iOS.
  final int waitsForDisplay;

  /// Calls of `mln_render_session_render_update`.
  final int renderUpdateCount;

  /// The total time of the calls counted by [renderUpdateCount].
  final Duration renderUpdateTotal;

  /// The longest of the calls counted by [renderUpdateCount].
  final Duration renderUpdateMax;

  /// GPU copies of the rendered frame into a display buffer, including the
  /// wait for completion. Always 0 for a copy-free map.
  final int copyCount;

  /// The total time of the copies counted by [copyCount].
  final Duration copyTotal;

  /// The longest of the copies counted by [copyCount].
  final Duration copyMax;

  /// Frames given to Flutter for display. On macOS and iOS, a frame counts
  /// when Flutter takes it for display. On Android, a frame counts when Dart
  /// chooses it with [MapTextureController.selectNewest].
  final int presentedFrames;

  /// `MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE` events received.
  final int renderUpdateAvailableEvents;

  /// Rendered frames after which the renderer reported `needs_repaint`.
  final int needsRepaintFrames;

  /// Renders deferred because rendering was paused, for example while an iOS
  /// app is in the background.
  final int pausedRenders;

  /// Times the renderer was asked to release cached resources, for example
  /// after an iOS memory warning.
  final int memoryReductions;

  /// Time from one render to the start of the next, while rendering
  /// continuously.
  final int frameCycleCount;

  /// The total of the times counted by [frameCycleCount].
  final Duration frameCycleTotal;

  /// Time from publishing a frame until Flutter takes it.
  final int pickupWaitCount;

  /// The total of the times counted by [pickupWaitCount].
  final Duration pickupWaitTotal;

  /// Time from Dart choosing the latest frame until the next render starts,
  /// for renders that waited for Dart to choose it.
  final int presentToRenderCount;

  /// The total of the times counted by [presentToRenderCount].
  final Duration presentToRenderTotal;

  /// Renders started before Dart had chosen the latest frame, because a frame
  /// took longer than a display refresh interval.
  final int renderAheadFrames;

  /// Renders deferred until one display refresh interval after the start of
  /// the previous render. Only Android paces renders this way.
  final int intervalWaits;

  /// The most display slots in use (rendering, queued, ready or chosen) at
  /// once.
  final int maxSlotsInUse;

  /// Cameras that a frame was rendered with, counted once each when the
  /// first such frame finished. A camera that a later one replaced before
  /// the map applied it isn't counted.
  final int cameraLatencyCount;

  /// The total, over the cameras counted by [cameraLatencyCount], of the time
  /// from [MapTextureController.setCamera] until the first frame rendered
  /// with the camera finished.
  final Duration cameraLatencyTotal;

  /// The longest of the times counted by [cameraLatencyCount].
  final Duration cameraLatencyMax;

  @override
  String toString() =>
      'MapTextureStats(rendered: $renderedFrames, presented: $presentedFrames, '
      'skipped: $skippedRenders, waits_for_display: $waitsForDisplay, '
      'render_update: $renderUpdateCount '
      'avg ${_avg(renderUpdateTotal, renderUpdateCount)} max $renderUpdateMax, '
      'copy: $copyCount avg ${_avg(copyTotal, copyCount)} max $copyMax, '
      'update_available: '
      '$renderUpdateAvailableEvents, needs_repaint: $needsRepaintFrames, '
      'paused: $pausedRenders, memory_reductions: $memoryReductions, '
      'interval_waits: $intervalWaits, max_slots_in_use: $maxSlotsInUse)';

  static String _avg(Duration total, int count) => count == 0
      ? '-'
      : '${(total.inMicroseconds / count).toStringAsFixed(1)}us';
}

/// Thrown by calls on a disposed [MapTextureController].
class MapTextureDisposedException implements Exception {
  /// The exception for a call on a disposed controller.
  const MapTextureDisposedException();
  @override
  String toString() => 'MapTextureDisposedException: the map was disposed';
}

/// Thrown when a native call fails.
class MapTextureException implements Exception {
  /// A failure with [message].
  const MapTextureException(this.message);

  /// Describes the failure.
  final String message;
  @override
  String toString() => 'MapTextureException: $message';
}

/// Header names and values for requests whose URL matches the glob [url].
typedef HeaderRule = ({String url, Map<String, String> headers});

/// Controls one MapLibre map that renders into a Flutter texture.
///
/// Commands return immediately; the map renders on its own native thread.
/// Calls after [dispose] throw [MapTextureDisposedException].
abstract interface class MapTextureController {
  /// Creates a map that renders at [pixelRatio] device pixels per logical
  /// pixel. The ratio fixes the density of the style's sprites and glyphs for
  /// the map's lifetime; later [resize] calls may change the render ratio.
  ///
  /// With [copyFree] (the default), MapLibre renders each frame directly into
  /// the buffer that Flutter displays. With `copyFree: false`, it renders into
  /// a separate texture, and each frame is copied into that buffer on the GPU.
  /// `docs/benchmarks.md` compares the two.
  ///
  /// On Android every map renders directly into the buffers that Flutter
  /// displays, and [copyFree] has no effect.
  ///
  /// The map registers its textures with the Flutter engine of the calling
  /// isolate. The first creation in an isolate asks the plugin for the
  /// engine's token over a platform channel; later creations wait only for a
  /// microtask.
  ///
  /// Throws [MapTextureException] without calling native code when the native
  /// library isn't available in this process, which is always the case on
  /// web, and when the plugin doesn't give the engine's token.
  ///
  /// With [initialCamera], which needs [limits], the map owns its camera
  /// (design D235): it starts at [initialCamera], and only the camera commands
  /// and the gesture recognizer of this controller move it. [setCamera] then
  /// throws a [MapTextureException].
  static Future<MapTextureController> create({
    required double pixelRatio,
    bool copyFree = true,
    List<HeaderRule> httpHeaders = const [],
    NativeCamera? initialCamera,
    NativeLimits? limits,
  }) async {
    if (!nativeLibraryAvailable) {
      throw const MapTextureException(
        'the native library of mapigrade is not available in this '
        'process',
      );
    }
    return platform.createMapTextureController(
      pixelRatio: pixelRatio,
      copyFree: copyFree,
      httpHeaders: httpHeaders,
      initialCamera: initialCamera,
      limits: limits,
    );
  }

  /// Sets the maximum size in [bytes] of the tile cache for maps created after
  /// the call, in the whole process. Maps that already exist keep their
  /// maximum size.
  ///
  /// Throws [ArgumentError] for a negative [bytes] without calling native
  /// code, and [MapTextureException] if the native call fails. Does nothing
  /// when the native library isn't available in this process.
  static void setMaximumCacheSize(int bytes) {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be negative');
    }
    if (!nativeLibraryAvailable) return;
    platform.setMaximumCacheSize(bytes);
  }

  /// The ids for `Texture` widgets, one per display slot. Dart chooses the
  /// frame to display with [selectNewest]. There are four slots on macOS and
  /// iOS, each with its own texture, and six on Android, which share one
  /// texture, so that all six ids are equal there.
  List<int> get textureIds;

  /// Whether the map was created to render directly into the displayed
  /// buffers; see [MapTextureController.create]. On Android every map does.
  bool get copyFree;

  /// Style, loading, render and idle events.
  Stream<MapEvent> get events;

  /// The camera of each frame when Flutter takes it for display, or on
  /// Android when Dart chooses it for display.
  Stream<FrameCamera> get frames;

  /// The camera of the frame displayed last, if any.
  FrameCamera? get displayedFrame;

  /// Each frame when it has finished rendering into a display slot, before
  /// Flutter displays it. Each one asks for a build, in which Dart chooses the
  /// newest finished frame with [selectNewest]. That frame can be newer than
  /// the frame added here last.
  Stream<FrameCamera> get readyFrames;

  /// The frame added to [readyFrames] last, if any.
  FrameCamera? get readyFrame;

  /// The frame that [selectNewest] chose last, if any.
  FrameCamera? get selectedFrame;

  /// Whether [dispose] has been called.
  bool get isDisposed;

  /// Loads the style at [url], replacing the current style.
  void loadStyleUrl(String url);

  /// Loads the style [json], replacing the current style.
  void loadStyleJson(String json);

  /// Sets the camera and returns its sequence number, which the frames
  /// rendered with it report as [FrameCamera.seq]. Numbers start at 1 and
  /// increase by one per call. When this is called faster than the map
  /// renders, the map renders the latest camera only.
  int setCamera(MapCamera camera);

  /// Chooses, for the Flutter frame being built, the newest frame that has
  /// finished rendering and that Dart hasn't chosen, on the platform thread,
  /// and returns it. Display `textureIds[frame.slot]` in the same build; the
  /// map doesn't render into the slot while a Flutter frame may still display
  /// it.
  ///
  /// Returns null and changes nothing if no such frame has finished. Then keep
  /// displaying [selectedFrame], the frame chosen before.
  FrameCamera? selectNewest();

  /// Queries the features that the map renders in the quadrilateral with the
  /// four [worldCorners], in normalized Web Mercator coordinates: the world is
  /// [0, 1) in both directions, with y increasing southwards. The map converts
  /// the corners with the camera of the last frame it rendered. With
  /// [layerIds], only those style layers are queried; [filterJson] is a
  /// style-spec filter expression as JSON.
  ///
  /// Completes with one entry per feature: `feature` (a GeoJSON Feature),
  /// `source`, `sourceLayer` and `state`, in the order MapLibre returns them,
  /// and with an empty list before the map has rendered a frame. Queries
  /// complete in the order of the calls. Completes with a
  /// [MapTextureException] when the query fails, and with a [StateError] when
  /// the controller is disposed before the result arrives.
  Future<List<Map<String, Object?>>> queryRenderedFeatures(
    List<Offset> worldCorners, {
    List<String>? layerIds,
    String? filterJson,
  });

  /// Sets the keys of the JSON object [stateJson] in the feature state of the
  /// feature [featureId] of the source [sourceId] and, for a source with
  /// layers, its source layer [sourceLayerId]. A numeric feature id is given
  /// as its decimal text. The map reports a failure as a [RenderError].
  void setFeatureState({
    required String sourceId,
    String? sourceLayerId,
    required String featureId,
    required String stateJson,
  });

  /// Removes feature state of the source [sourceId] and, for a source with
  /// layers, its source layer [sourceLayerId]: the key [key] of the feature
  /// [featureId], every key of that feature without [key], or the state of
  /// every feature without either.
  void removeFeatureState({
    required String sourceId,
    String? sourceLayerId,
    String? featureId,
    String? key,
  });

  /// Gives the source [sourceIndex] of the overlay [overlayId] the UTF-8
  /// GeoJSON [geoJson], with line metrics when [lineMetrics]. The map
  /// prepares the data on the calling thread. Throws [MapTextureException]
  /// with the map's message for GeoJSON it can't use.
  void setOverlaySource(
    int overlayId,
    int sourceIndex,
    Uint8List geoJson, {
    required bool lineMetrics,
  });

  /// Like [setOverlaySource] with the bytes that [encode] returns, but runs
  /// [encode] and the call on a background isolate, so that neither blocks
  /// the calling isolate. [encode] must be sendable to another isolate: it
  /// must not capture the widget tree or anything else that is bound to the
  /// calling isolate. Completes with a [MapTextureException] on failure.
  Future<void> setOverlaySourceInBackground(
    int overlayId,
    int sourceIndex,
    Uint8List Function() encode, {
    required bool lineMetrics,
  });

  /// Removes the source [sourceIndex] of the overlay [overlayId] from the
  /// map. Nothing happens when the overlay has no such source.
  void removeOverlaySource(int overlayId, int sourceIndex);

  /// Sets the style layers, placement and order key of the overlay
  /// [overlayId]; see `map_texture_overlay_set_layers` in
  /// `map_texture_api.h`. Each style layer's `source` names a source of the
  /// overlay. [placementKind] is 0
  /// for below the labels, 1 for below the style layer [belowLayerId], 2 for
  /// the top.
  void setOverlayLayers(
    int overlayId, {
    required String layersJson,
    required int placementKind,
    String? belowLayerId,
    required int orderChild,
    required int orderSeq,
  });

  /// Removes the overlay [overlayId], its style layers and sources, from the
  /// map.
  void removeOverlay(int overlayId);

  /// Sets the viewport's logical size and device pixel ratio. Repeated calls
  /// with the same values do nothing.
  void resize(Size logicalSize, double pixelRatio);

  /// Sets the refresh rate in Hz of the display that shows the map.
  /// [MapTextureView] calls this.
  void setDisplayRefreshRate(double hz);

  /// The counters of the map thread at the time of the call.
  MapTextureStats stats();

  /// For a map that owns its camera: moves the camera to [camera], `mode` 0
  /// jumping, 1 easing and 2 flying, over [durationMs] or MapLibre's duration
  /// when it is negative. The end arrives as a [CameraTransitionEnded] with
  /// [requestId].
  void cameraCommand(
    int requestId,
    int mode,
    NativeCamera camera, {
    double durationMs = -1,
  });

  /// For a map that owns its camera: fits the camera to [fit], as
  /// [cameraCommand] does.
  void fitBounds(
    int requestId,
    int mode,
    NativeFit fit, {
    double durationMs = -1,
  });

  /// For a map that owns its camera: cancels the running transitions.
  void cancelTransitions();

  /// For a map that owns its camera: replaces the camera limits.
  void setLimits(NativeLimits limits);

  /// For a map that owns its camera: creates its gesture recognizer.
  void createGestureRecognizer(NativeGestureOptions options);

  /// Changes the gesture recognizer's options from the next input on.
  void setGestureOptions(NativeGestureOptions options);

  /// Passes [input] at [timeMs], on a clock that only goes forward, to the
  /// gesture recognizer.
  GestureResult handleGesture(GestureInput input, double timeMs);

  /// Ticks the gesture recognizer at [timeMs].
  GestureResult tickGesture(double timeMs);

  /// For tests: the logical position at which MapLibre's projection of the
  /// last frame the map rendered places the coordinate, or null before the
  /// first frame.
  Offset? projectForTesting(double latitude, double longitude);

  /// Stops the map thread and releases the map, its GPU resources and the
  /// texture. Waits for a frame that is rendering to finish.
  void dispose();
}
