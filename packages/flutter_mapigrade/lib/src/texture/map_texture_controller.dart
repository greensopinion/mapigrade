import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'bindings.dart';
import 'engine_token.dart';
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
  });

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

/// Counters from the native map thread.
class MapTextureStats {
  MapTextureStats._(MapTextureStatsStruct s)
    : renderedFrames = s.renderedFrames,
      skippedRenders = s.skippedRenders,
      waitsForDisplay = s.waitsForDisplay,
      renderUpdateCount = s.renderUpdateCount,
      renderUpdateTotal = Duration(microseconds: s.renderUpdateTotalNs ~/ 1000),
      renderUpdateMax = Duration(microseconds: s.renderUpdateMaxNs ~/ 1000),
      copyCount = s.copyCount,
      copyTotal = Duration(microseconds: s.copyTotalNs ~/ 1000),
      copyMax = Duration(microseconds: s.copyMaxNs ~/ 1000),
      presentedFrames = s.presentedFrames,
      renderUpdateAvailableEvents = s.renderUpdateAvailableEvents,
      needsRepaintFrames = s.needsRepaintFrames,
      pausedRenders = s.pausedRenders,
      memoryReductions = s.memoryReductions,
      frameCycleCount = s.frameCycleCount,
      frameCycleTotal = Duration(microseconds: s.frameCycleTotalNs ~/ 1000),
      pickupWaitCount = s.pickupWaitCount,
      pickupWaitTotal = Duration(microseconds: s.pickupWaitTotalNs ~/ 1000),
      presentToRenderCount = s.presentToRenderCount,
      presentToRenderTotal = Duration(
        microseconds: s.presentToRenderTotalNs ~/ 1000,
      ),
      renderAheadFrames = s.renderAheadFrames,
      intervalWaits = s.intervalWaits,
      maxSlotsInUse = s.maxSlotsInUse;

  /// Counters with the given values, for tests that have no native map
  /// (design D113).
  @visibleForTesting
  const MapTextureStats.forTesting({
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
class MapTextureController {
  MapTextureController._(
    this._handle,
    this.textureIds,
    this.copyFree,
    this._callable,
  );

  /// Creates a map that renders at [pixelRatio] device pixels per logical
  /// pixel. The ratio fixes the density of the style's sprites and glyphs for
  /// the map's lifetime; later [resize] calls may change the render ratio.
  ///
  /// With [copyFree] (the default), MapLibre renders each frame directly into
  /// the buffer that Flutter displays. With `copyFree: false`, it renders into
  /// a separate texture, and each frame is copied into that buffer on the GPU.
  /// On an iPhone 15 Pro Max copy-free rendering saved the 1.5 ms copy per
  /// frame and raised the slowest seconds of a continuous pan from 83–88 to
  /// 98–104 frames per second. A copy-free frame costs about one display
  /// refresh interval there, so the map more often renders a frame that Flutter
  /// replaces before displaying it (6.9–8.5% of rendered frames, against
  /// 3.0–5.4% with the copy). On an M2 Max Mac at 3200x2000 physical pixels it
  /// gave no consistent gain, because rendering took longer by more than the
  /// copy it saved.
  ///
  /// On Android every map renders directly into the buffers that Flutter
  /// displays, and [copyFree] has no effect.
  ///
  /// The map registers its textures with the Flutter engine of the calling
  /// isolate. The first creation in an isolate asks the plugin for the
  /// engine's token over a platform channel; later creations wait only for a
  /// microtask (designs D154 and D155 of the multiple-flutter-engines change).
  ///
  /// Throws [MapTextureException] without calling native code when the native
  /// library isn't available in this process (design D86 of the
  /// unsupported-architectures change), and when the plugin doesn't give the
  /// engine's token.
  static Future<MapTextureController> create({
    required double pixelRatio,
    bool copyFree = true,
    List<HeaderRule> httpHeaders = const [],
  }) async {
    if (!nativeLibraryAvailable) {
      throw const MapTextureException(
        'the native library of flutter_mapigrade is not available in this '
        'process',
      );
    }
    final engine = await engineToken();
    late final MapTextureController controller;
    final callable = NativeCallable<MapTextureEventCallback>.listener(
      (Pointer<MapTextureEventStruct> event) => controller._onEvent(event),
    );
    final (handle, error) = using((arena) {
      // Each rule's URL, then its names and values (design D81).
      final strings = [
        for (final rule in httpHeaders) ...[
          rule.url,
          for (final MapEntry(:key, :value) in rule.headers.entries) ...[
            key,
            value,
          ],
        ],
      ];
      final headerStrings = arena<Pointer<Utf8>>(strings.length);
      for (var i = 0; i < strings.length; ++i) {
        headerStrings[i] = strings[i].toNativeUtf8(allocator: arena);
      }
      final headerCounts = arena<Int32>(httpHeaders.length);
      for (var i = 0; i < httpHeaders.length; ++i) {
        headerCounts[i] = httpHeaders[i].headers.length;
      }
      final outError = arena<Pointer<Utf8>>();
      final handle = mapTextureCreate(
        engine,
        pixelRatio,
        copyFree ? 1 : 0,
        callable.nativeFunction,
        headerStrings,
        headerCounts,
        httpHeaders.length,
        outError,
      );
      String? error;
      if (outError.value != nullptr) {
        error = outError.value.toDartString();
        mapTextureStringFree(outError.value);
      }
      return (handle, error);
    });
    if (handle <= 0) {
      callable.close();
      throw MapTextureException(
        error ?? 'map_texture_create failed with $handle',
      );
    }
    final textureIds = using((arena) {
      final ids = arena<Int64>(_maxSlots);
      final count = mapTextureTextureIds(handle, ids, _maxSlots);
      return [for (var i = 0; i < count && i < _maxSlots; ++i) ids[i]];
    });
    controller = MapTextureController._(handle, textureIds, copyFree, callable);
    return controller;
  }

  /// Sets the maximum size in [bytes] of the tile cache for maps created after
  /// the call, in the whole process (design D61 of the
  /// tile-cache-maximum-size change). Maps that already exist keep their
  /// maximum size.
  ///
  /// Throws [ArgumentError] for a negative [bytes] without calling native
  /// code, and [MapTextureException] if the native call fails. Does nothing
  /// when the native library isn't available in this process (design D86 of
  /// the unsupported-architectures change).
  static void setMaximumCacheSize(int bytes) {
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be negative');
    }
    if (!nativeLibraryAvailable) return;
    final status = mapTextureSetMaximumCacheSize(bytes);
    if (status != mapTextureOk) {
      throw MapTextureException(
        'map_texture_set_maximum_cache_size failed with $status',
      );
    }
  }

  // kMaxBufferCount in src/core/buffer_state.h.
  static const _maxSlots = 6;

  final int _handle;
  final NativeCallable<MapTextureEventCallback> _callable;
  // The frame that selectNewest() receives; freed in dispose().
  final Pointer<MapTextureFrameStruct> _chosen =
      calloc<MapTextureFrameStruct>();

  /// The ids for `Texture` widgets, one per display slot (design D122 of the
  /// layer-children-alignment change). Dart chooses the frame to display with
  /// [selectNewest]. There are four slots on macOS and iOS, each with its own
  /// texture, and six on Android, which share one texture, so that all six
  /// ids are equal there (design D135 of the android-layer-children-alignment
  /// change).
  final List<int> textureIds;

  /// Whether the map was created to render directly into the displayed
  /// buffers; see [MapTextureController.create]. On Android every map does.
  final bool copyFree;

  final _events = StreamController<MapEvent>.broadcast();
  final _frames = StreamController<FrameCamera>.broadcast();
  final _readyFrames = StreamController<FrameCamera>.broadcast();
  bool _disposed = false;
  double? _width, _height, _pixelRatio, _refreshRate;
  int _seq = 0;

  /// Style, loading, render and idle events.
  Stream<MapEvent> get events => _events.stream;

  /// The camera of each frame when Flutter takes it for display, or on
  /// Android when Dart chooses it for display.
  Stream<FrameCamera> get frames => _frames.stream;

  /// The camera of the frame displayed last, if any.
  FrameCamera? get displayedFrame => _displayedFrame;
  FrameCamera? _displayedFrame;

  /// Each frame when it has finished rendering into a display slot, before
  /// Flutter displays it. Each one asks for a build, in which Dart chooses
  /// the newest finished frame with [selectNewest] (design D141). That frame
  /// can be newer than the frame added here last.
  Stream<FrameCamera> get readyFrames => _readyFrames.stream;

  /// The frame added to [readyFrames] last, if any.
  FrameCamera? get readyFrame => _readyFrame;
  FrameCamera? _readyFrame;

  /// The frame that [selectNewest] chose last, if any.
  FrameCamera? get selectedFrame => _selectedFrame;
  FrameCamera? _selectedFrame;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Loads the style at [url], replacing the current style.
  void loadStyleUrl(String url) =>
      _withString(url, (p) => mapTextureLoadStyleUrl(_handle, p));

  /// Loads the style [json], replacing the current style.
  void loadStyleJson(String json) =>
      _withString(json, (p) => mapTextureLoadStyleJson(_handle, p));

  /// Sets the camera and returns its sequence number, which the frames
  /// rendered with it report as [FrameCamera.seq]. Numbers start at 1 and
  /// increase by one per call. When this is called faster than the map
  /// renders, the map renders the latest camera only.
  int setCamera(MapCamera camera) {
    if (_disposed) throw const MapTextureDisposedException();
    final seq = _seq + 1;
    _check(
      mapTextureSetCamera(
        _handle,
        camera.latitude,
        camera.longitude,
        camera.zoom,
        camera.bearing,
        seq,
      ),
    );
    _seq = seq;
    return seq;
  }

  /// Chooses, for the Flutter frame being built, the newest frame that has
  /// finished rendering and that Dart hasn't chosen, on the platform thread,
  /// and returns it (designs D139 and D141 of the synchronous-frame-choice
  /// change). Display `textureIds[frame.slot]` in the same build; the map
  /// doesn't render into the slot while a Flutter frame may still display it.
  ///
  /// Returns null and changes nothing if no such frame has finished. Then keep
  /// displaying [selectedFrame], the frame chosen before.
  FrameCamera? selectNewest() {
    if (_disposed) throw const MapTextureDisposedException();
    final status = mapTextureSelectNewest(_handle, _chosen);
    if (status == mapTextureNotSelected) return null;
    _check(status);
    final f = _chosen.ref;
    final frame = FrameCamera(
      frameId: f.frameId,
      camera: MapCamera(
        latitude: f.latitude,
        longitude: f.longitude,
        zoom: f.zoom,
        bearing: f.bearing,
      ),
      physicalSize: Size(
        f.physicalWidth.toDouble(),
        f.physicalHeight.toDouble(),
      ),
      scaleFactor: f.scaleFactor,
      displayTime: null,
      slot: f.slot,
      seq: f.seq,
    );
    _selectedFrame = frame;
    return frame;
  }

  /// Sets the viewport's logical size and device pixel ratio. Repeated calls
  /// with the same values do nothing.
  void resize(Size logicalSize, double pixelRatio) {
    if (_disposed) throw const MapTextureDisposedException();
    if (logicalSize.width == _width &&
        logicalSize.height == _height &&
        pixelRatio == _pixelRatio) {
      return;
    }
    _check(
      mapTextureResize(
        _handle,
        logicalSize.width,
        logicalSize.height,
        pixelRatio,
      ),
    );
    _width = logicalSize.width;
    _height = logicalSize.height;
    _pixelRatio = pixelRatio;
  }

  /// Sets the refresh rate in Hz of the display that shows the map.
  /// [MapTextureView] calls this.
  void setDisplayRefreshRate(double hz) {
    if (_disposed) throw const MapTextureDisposedException();
    if (hz == _refreshRate) return;
    _check(mapTextureSetDisplayRefreshRate(_handle, hz));
    _refreshRate = hz;
  }

  /// The counters of the map thread at the time of the call.
  MapTextureStats stats() {
    final out = calloc<MapTextureStatsStruct>();
    try {
      _check(mapTextureGetStats(_handle, out));
      return MapTextureStats._(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  /// Stops the map thread and releases the map, its GPU resources and the
  /// texture. Waits for a frame that is rendering to finish.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    mapTextureDispose(_handle);
    // No event is sent after dispose returns, so the callable can close.
    _callable.close();
    calloc.free(_chosen);
    _events.close();
    _frames.close();
    _readyFrames.close();
  }

  void _withString(String value, int Function(Pointer<Utf8>) call) {
    if (_disposed) throw const MapTextureDisposedException();
    final pointer = value.toNativeUtf8();
    try {
      _check(call(pointer));
    } finally {
      malloc.free(pointer);
    }
  }

  void _check(int status) {
    if (status == mapTextureOk) return;
    if (status == mapTextureErrorDisposed) {
      throw const MapTextureDisposedException();
    }
    throw MapTextureException('native call failed with status $status');
  }

  void _onEvent(Pointer<MapTextureEventStruct> pointer) {
    final e = pointer.ref;
    final type = e.type;
    final message = e.message == nullptr ? '' : e.message.toDartString();
    FrameCamera? frame;
    if (type == mapTextureEventFrameDisplayed ||
        type == mapTextureEventFrameReady) {
      frame = FrameCamera(
        frameId: e.frameId,
        camera: MapCamera(
          latitude: e.latitude,
          longitude: e.longitude,
          zoom: e.zoom,
          bearing: e.bearing,
        ),
        physicalSize: Size(
          e.physicalWidth.toDouble(),
          e.physicalHeight.toDouble(),
        ),
        scaleFactor: e.scaleFactor,
        displayTime: type == mapTextureEventFrameReady || e.displayTimeUs < 0
            ? null
            : e.displayTimeUs,
        slot: e.slot,
        seq: e.seq,
      );
    }
    mapTextureEventFree(pointer);
    if (_disposed) return;

    switch (type) {
      case mapTextureEventStyleLoaded:
        _events.add(const StyleLoaded());
      case mapTextureEventLoadingFailed:
        _events.add(LoadingFailed(message));
      case mapTextureEventRenderError:
        _events.add(RenderError(message));
      case mapTextureEventIdle:
        _events.add(const MapIdle());
      case mapTextureEventFrameDisplayed:
        _displayedFrame = frame;
        _frames.add(frame!);
      case mapTextureEventFrameReady:
        _readyFrame = frame;
        _readyFrames.add(frame!);
    }
  }
}
