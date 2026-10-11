import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// A map camera: center, zoom and bearing in degrees.
class MapCamera {
  const MapCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    this.bearing = 0,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double bearing;

  @override
  String toString() =>
      'MapCamera(lat: $latitude, lon: $longitude, zoom: $zoom, bearing: $bearing)';
}

/// The camera and viewport size a displayed frame was rendered with.
class FrameCamera {
  const FrameCamera({
    required this.frameId,
    required this.camera,
    required this.physicalSize,
    required this.scaleFactor,
    required this.displayTime,
  });

  /// Increases by one for each frame the map renders.
  final int frameId;
  final MapCamera camera;
  final Size physicalSize;
  final double scaleFactor;

  /// The time at which Flutter took the frame for display, in microseconds on
  /// the clock of [FrameTiming.timestampInMicroseconds], so that the frame can
  /// be matched to the Flutter frame whose rasterization displayed it.
  final int displayTime;

  @override
  String toString() =>
      'FrameCamera(#$frameId, $camera, ${physicalSize.width.toInt()}x${physicalSize.height.toInt()} @$scaleFactor)';
}

/// An event reported by the map.
sealed class MapEvent {
  const MapEvent();
}

class StyleLoaded extends MapEvent {
  const StyleLoaded();
}

/// Loading the style (or a resource it needs) failed.
class LoadingFailed extends MapEvent {
  const LoadingFailed(this.message);
  final String message;
}

class RenderError extends MapEvent {
  const RenderError(this.message);
  final String message;
}

/// The map has loaded all resources for the current camera and stopped
/// rendering.
class MapIdle extends MapEvent {
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
        presentToRenderTotal =
            Duration(microseconds: s.presentToRenderTotalNs ~/ 1000),
        renderAheadFrames = s.renderAheadFrames;

  final int renderedFrames;

  /// Renders deferred because no buffer was free.
  final int skippedRenders;

  /// Renders deferred because Flutter hadn't taken the latest frame yet.
  final int waitsForDisplay;
  final int renderUpdateCount;
  final Duration renderUpdateTotal;
  final Duration renderUpdateMax;

  /// GPU copies of the rendered frame into a display buffer, including the
  /// wait for completion. Always 0 for a copy-free map.
  final int copyCount;
  final Duration copyTotal;
  final Duration copyMax;

  /// Frames Flutter took for display.
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
  final Duration frameCycleTotal;

  /// Time from publishing a frame until Flutter takes it.
  final int pickupWaitCount;
  final Duration pickupWaitTotal;

  /// Time from Flutter taking a frame until the next render starts, for
  /// renders that waited for Flutter to take the latest frame.
  final int presentToRenderCount;
  final Duration presentToRenderTotal;

  /// Renders started before Flutter had taken the latest frame, because a
  /// frame took longer than a display refresh interval.
  final int renderAheadFrames;

  @override
  String toString() =>
      'MapTextureStats(rendered: $renderedFrames, presented: $presentedFrames, '
      'skipped: $skippedRenders, waits_for_display: $waitsForDisplay, '
      'render_update: $renderUpdateCount '
      'avg ${_avg(renderUpdateTotal, renderUpdateCount)} max $renderUpdateMax, '
      'copy: $copyCount avg ${_avg(copyTotal, copyCount)} max $copyMax, '
      'update_available: '
      '$renderUpdateAvailableEvents, needs_repaint: $needsRepaintFrames, '
      'paused: $pausedRenders, memory_reductions: $memoryReductions)';

  static String _avg(Duration total, int count) => count == 0
      ? '-'
      : '${(total.inMicroseconds / count).toStringAsFixed(1)}us';
}

/// Thrown by calls on a disposed [MapTextureController].
class MapTextureDisposedException implements Exception {
  const MapTextureDisposedException();
  @override
  String toString() => 'MapTextureDisposedException: the map was disposed';
}

/// Thrown when a native call fails.
class MapTextureException implements Exception {
  const MapTextureException(this.message);
  final String message;
  @override
  String toString() => 'MapTextureException: $message';
}

/// Controls one MapLibre map that renders into a Flutter texture.
///
/// Commands return immediately; the map renders on its own native thread.
/// Calls after [dispose] throw [MapTextureDisposedException].
class MapTextureController {
  MapTextureController._(
      this._handle, this.textureId, this.copyFree, this._callable);

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
  factory MapTextureController.create(
      {required double pixelRatio, bool copyFree = true}) {
    late final MapTextureController controller;
    final callable = NativeCallable<MapTextureEventCallback>.listener(
        (Pointer<MapTextureEventStruct> event) => controller._onEvent(event));
    final handle =
        mapTextureCreate(pixelRatio, copyFree ? 1 : 0, callable.nativeFunction);
    if (handle <= 0) {
      callable.close();
      throw MapTextureException('map_texture_create failed with $handle');
    }
    final textureId = mapTextureTextureId(handle);
    controller = MapTextureController._(handle, textureId, copyFree, callable);
    return controller;
  }

  final int _handle;
  final NativeCallable<MapTextureEventCallback> _callable;

  /// The id for a `Texture` widget.
  final int textureId;

  /// Whether the map renders directly into the displayed buffers; see
  /// [MapTextureController.create].
  final bool copyFree;

  final _events = StreamController<MapEvent>.broadcast();
  final _frames = StreamController<FrameCamera>.broadcast();
  bool _disposed = false;
  double? _width, _height, _pixelRatio, _refreshRate;

  /// Style, loading, render and idle events.
  Stream<MapEvent> get events => _events.stream;

  /// The camera of each frame when Flutter takes it for display.
  Stream<FrameCamera> get frames => _frames.stream;

  /// The camera of the frame displayed last, if any.
  FrameCamera? get displayedFrame => _displayedFrame;
  FrameCamera? _displayedFrame;

  bool get isDisposed => _disposed;

  void loadStyleUrl(String url) =>
      _withString(url, (p) => mapTextureLoadStyleUrl(_handle, p));

  void loadStyleJson(String json) =>
      _withString(json, (p) => mapTextureLoadStyleJson(_handle, p));

  /// Sets the camera. When this is called faster than the map renders, the
  /// map renders the latest camera only.
  void setCamera(MapCamera camera) {
    _check(mapTextureSetCamera(_handle, camera.latitude, camera.longitude,
        camera.zoom, camera.bearing));
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
    _check(mapTextureResize(
        _handle, logicalSize.width, logicalSize.height, pixelRatio));
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
    _events.close();
    _frames.close();
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
    if (type == mapTextureEventFrameDisplayed) {
      frame = FrameCamera(
        frameId: e.frameId,
        camera: MapCamera(
          latitude: e.latitude,
          longitude: e.longitude,
          zoom: e.zoom,
          bearing: e.bearing,
        ),
        physicalSize:
            Size(e.physicalWidth.toDouble(), e.physicalHeight.toDouble()),
        scaleFactor: e.scaleFactor,
        displayTime: e.displayTimeUs,
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
    }
  }
}

/// The number of threads in this process, for lifecycle tests.
int processThreadCount() => mapTextureProcessThreadCount();
