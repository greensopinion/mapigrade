// MapTextureController.create and MapTextureController.setMaximumCacheSize
// check that the native library is available before they call these
// functions.
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'engine_token.dart';
import 'map_texture_controller.dart';
import 'pending_queries.dart';

// kMaxBufferCount in src/core/buffer_state.h.
const _maxSlots = 6;

/// Creates the native map of [MapTextureController.create].
Future<MapTextureController> createMapTextureController({
  required double pixelRatio,
  required bool copyFree,
  required double maxPitch,
  required List<HeaderRule> httpHeaders,
}) async {
  final engine = await engineToken();
  late final _FfiMapTextureController controller;
  final callable = NativeCallable<MapTextureEventCallback>.listener(
    (Pointer<MapTextureEventStruct> event) => controller._onEvent(event),
  );
  final (handle, error) = using((arena) {
    // Each rule's URL, then its names and values.
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
      maxPitch,
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
  controller = _FfiMapTextureController(handle, textureIds, copyFree, callable);
  return controller;
}

/// The native call of [MapTextureController.setMaximumCacheSize].
void setMaximumCacheSize(int bytes) {
  final status = mapTextureSetMaximumCacheSize(bytes);
  if (status != mapTextureOk) {
    throw MapTextureException(
      'map_texture_set_maximum_cache_size failed with $status',
    );
  }
}

MapTextureStats _statsOf(MapTextureStatsStruct s) => MapTextureStats(
  renderedFrames: s.renderedFrames,
  skippedRenders: s.skippedRenders,
  waitsForDisplay: s.waitsForDisplay,
  renderUpdateCount: s.renderUpdateCount,
  renderUpdateTotal: Duration(microseconds: s.renderUpdateTotalNs ~/ 1000),
  renderUpdateMax: Duration(microseconds: s.renderUpdateMaxNs ~/ 1000),
  copyCount: s.copyCount,
  copyTotal: Duration(microseconds: s.copyTotalNs ~/ 1000),
  copyMax: Duration(microseconds: s.copyMaxNs ~/ 1000),
  presentedFrames: s.presentedFrames,
  renderUpdateAvailableEvents: s.renderUpdateAvailableEvents,
  needsRepaintFrames: s.needsRepaintFrames,
  pausedRenders: s.pausedRenders,
  memoryReductions: s.memoryReductions,
  frameCycleCount: s.frameCycleCount,
  frameCycleTotal: Duration(microseconds: s.frameCycleTotalNs ~/ 1000),
  pickupWaitCount: s.pickupWaitCount,
  pickupWaitTotal: Duration(microseconds: s.pickupWaitTotalNs ~/ 1000),
  presentToRenderCount: s.presentToRenderCount,
  presentToRenderTotal: Duration(
    microseconds: s.presentToRenderTotalNs ~/ 1000,
  ),
  renderAheadFrames: s.renderAheadFrames,
  intervalWaits: s.intervalWaits,
  maxSlotsInUse: s.maxSlotsInUse,
  cameraLatencyCount: s.cameraLatencyCount,
  cameraLatencyTotal: Duration(microseconds: s.cameraLatencyTotalNs ~/ 1000),
  cameraLatencyMax: Duration(microseconds: s.cameraLatencyMaxNs ~/ 1000),
);

class _FfiMapTextureController implements MapTextureController {
  _FfiMapTextureController(
    this._handle,
    this.textureIds,
    this.copyFree,
    this._callable,
  );

  final int _handle;
  final NativeCallable<MapTextureEventCallback> _callable;
  final Pointer<MapTextureFrameStruct> _chosen =
      calloc<MapTextureFrameStruct>();

  @override
  final List<int> textureIds;

  @override
  final bool copyFree;

  final _events = StreamController<MapEvent>.broadcast();
  final _frames = StreamController<FrameCamera>.broadcast();
  final _readyFrames = StreamController<FrameCamera>.broadcast();
  bool _disposed = false;
  double? _width, _height, _pixelRatio, _refreshRate;
  int _seq = 0;
  final _queries = PendingQueries();

  @override
  Stream<MapEvent> get events => _events.stream;

  @override
  Stream<FrameCamera> get frames => _frames.stream;

  @override
  FrameCamera? get displayedFrame => _displayedFrame;
  FrameCamera? _displayedFrame;

  @override
  Stream<FrameCamera> get readyFrames => _readyFrames.stream;

  @override
  FrameCamera? get readyFrame => _readyFrame;
  FrameCamera? _readyFrame;

  @override
  FrameCamera? get selectedFrame => _selectedFrame;
  FrameCamera? _selectedFrame;

  @override
  bool get isDisposed => _disposed;

  @override
  void loadStyleUrl(String url) =>
      _withString(url, (p) => mapTextureLoadStyleUrl(_handle, p));

  @override
  void loadStyleJson(String json) =>
      _withString(json, (p) => mapTextureLoadStyleJson(_handle, p));

  @override
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
        camera.pitch,
        seq,
      ),
    );
    _seq = seq;
    return seq;
  }

  @override
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
        pitch: f.pitch,
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

  @override
  Future<List<Map<String, Object?>>> queryRenderedFeatures(
    List<Offset> worldCorners, {
    List<String>? layerIds,
    String? filterJson,
  }) {
    if (_disposed) return Future.error(const MapTextureDisposedException());
    if (worldCorners.length != 4) {
      throw ArgumentError.value(worldCorners, 'worldCorners', 'needs 4 points');
    }
    final (id, result) = _queries.add();
    // The native side reads an empty array of layer ids as no array.
    if (layerIds != null && layerIds.isEmpty) {
      _queries.complete(id, 0, '[]');
      return result;
    }
    final status = using((arena) {
      final corners = arena<Double>(8);
      for (var i = 0; i < 4; ++i) {
        corners[2 * i] = worldCorners[i].dx;
        corners[2 * i + 1] = worldCorners[i].dy;
      }
      Pointer<Pointer<Utf8>> ids = nullptr;
      if (layerIds != null) {
        ids = arena<Pointer<Utf8>>(layerIds.length);
        for (var i = 0; i < layerIds.length; ++i) {
          ids[i] = layerIds[i].toNativeUtf8(allocator: arena);
        }
      }
      return mapTextureQueryRenderedFeatures(
        _handle,
        id,
        corners,
        ids,
        layerIds?.length ?? 0,
        filterJson?.toNativeUtf8(allocator: arena) ?? nullptr,
      );
    });
    if (status != mapTextureOk) {
      _queries.complete(id, status, 'native call failed with status $status');
    }
    return result;
  }

  @override
  void setFeatureState({
    required String sourceId,
    String? sourceLayerId,
    required String featureId,
    required String stateJson,
  }) {
    if (_disposed) throw const MapTextureDisposedException();
    using((arena) {
      _check(
        mapTextureSetFeatureState(
          _handle,
          sourceId.toNativeUtf8(allocator: arena),
          sourceLayerId?.toNativeUtf8(allocator: arena) ?? nullptr,
          featureId.toNativeUtf8(allocator: arena),
          stateJson.toNativeUtf8(allocator: arena),
        ),
      );
    });
  }

  @override
  void removeFeatureState({
    required String sourceId,
    String? sourceLayerId,
    String? featureId,
    String? key,
  }) {
    if (_disposed) throw const MapTextureDisposedException();
    using((arena) {
      _check(
        mapTextureRemoveFeatureState(
          _handle,
          sourceId.toNativeUtf8(allocator: arena),
          sourceLayerId?.toNativeUtf8(allocator: arena) ?? nullptr,
          featureId?.toNativeUtf8(allocator: arena) ?? nullptr,
          key?.toNativeUtf8(allocator: arena) ?? nullptr,
        ),
      );
    });
  }

  @override
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

  @override
  void setDisplayRefreshRate(double hz) {
    if (_disposed) throw const MapTextureDisposedException();
    if (hz == _refreshRate) return;
    _check(mapTextureSetDisplayRefreshRate(_handle, hz));
    _refreshRate = hz;
  }

  @override
  MapTextureStats stats() {
    final out = calloc<MapTextureStatsStruct>();
    try {
      _check(mapTextureGetStats(_handle, out));
      return _statsOf(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    mapTextureDispose(_handle);
    _queries.failAll(StateError('the map was disposed'));
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
    final requestId = e.requestId;
    final status = e.status;
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
          pitch: e.pitch,
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
      case mapTextureEventQueryResult:
        _queries.complete(requestId, status, message);
    }
  }
}
