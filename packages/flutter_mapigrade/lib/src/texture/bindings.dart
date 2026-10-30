// The declarations mirror src/core/map_texture_api.h, which documents them.
//
// On macOS and iOS the plugin's native code is linked into the app, so the
// symbols resolve from the process. On Android they are in
// libflutter_mapigrade.so, which hook/build.dart declares as the code asset
// `package:flutter_mapigrade/native`. The asset id doesn't depend on this
// file's path.
// ignore_for_file: public_member_api_docs
@DefaultAsset('package:flutter_mapigrade/native')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

const int mapTextureNotSelected = 1;
const int mapTextureOk = 0;
const int mapTextureErrorDisposed = -1;
const int mapTextureErrorInvalidArgument = -2;
const int mapTextureErrorCreateFailed = -3;

const int mapTextureEventStyleLoaded = 0;
const int mapTextureEventLoadingFailed = 1;
const int mapTextureEventRenderError = 2;
const int mapTextureEventIdle = 3;
const int mapTextureEventFrameDisplayed = 4;
const int mapTextureEventFrameReady = 5;
const int mapTextureEventQueryResult = 6;

final class MapTextureEventStruct extends Struct {
  @Int64()
  external int handle;
  @Int32()
  external int type;
  @Int64()
  external int frameId;
  @Double()
  external double latitude;
  @Double()
  external double longitude;
  @Double()
  external double zoom;
  @Double()
  external double bearing;
  @Int32()
  external int physicalWidth;
  @Int32()
  external int physicalHeight;
  @Double()
  external double scaleFactor;
  @Int64()
  external int displayTimeUs;
  @Int32()
  external int slot;
  @Int64()
  external int seq;
  external Pointer<Utf8> message;
  @Int64()
  external int requestId;
  @Int32()
  external int status;
}

final class MapTextureFrameStruct extends Struct {
  @Int64()
  external int frameId;
  @Int32()
  external int slot;
  @Int64()
  external int seq;
  @Double()
  external double latitude;
  @Double()
  external double longitude;
  @Double()
  external double zoom;
  @Double()
  external double bearing;
  @Int32()
  external int physicalWidth;
  @Int32()
  external int physicalHeight;
  @Double()
  external double scaleFactor;
}

final class MapTextureStatsStruct extends Struct {
  @Int64()
  external int renderedFrames;
  @Int64()
  external int skippedRenders;
  @Int64()
  external int waitsForDisplay;
  @Int64()
  external int renderUpdateCount;
  @Int64()
  external int renderUpdateTotalNs;
  @Int64()
  external int renderUpdateMaxNs;
  @Int64()
  external int copyCount;
  @Int64()
  external int copyTotalNs;
  @Int64()
  external int copyMaxNs;
  @Int64()
  external int presentedFrames;
  @Int64()
  external int renderUpdateAvailableEvents;
  @Int64()
  external int needsRepaintFrames;
  @Int64()
  external int pausedRenders;
  @Int64()
  external int memoryReductions;
  @Int64()
  external int frameCycleCount;
  @Int64()
  external int frameCycleTotalNs;
  @Int64()
  external int pickupWaitCount;
  @Int64()
  external int pickupWaitTotalNs;
  @Int64()
  external int presentToRenderCount;
  @Int64()
  external int presentToRenderTotalNs;
  @Int64()
  external int renderAheadFrames;
  @Int64()
  external int intervalWaits;
  @Int64()
  external int maxSlotsInUse;
  @Int64()
  external int cameraLatencyCount;
  @Int64()
  external int cameraLatencyTotalNs;
  @Int64()
  external int cameraLatencyMaxNs;
}

typedef MapTextureEventCallback = Void Function(
  Pointer<MapTextureEventStruct> event,
);

@Native<
  Int64 Function(
    Int64,
    Double,
    Int32,
    Pointer<NativeFunction<MapTextureEventCallback>>,
    Pointer<Pointer<Utf8>>,
    Pointer<Int32>,
    Int32,
    Pointer<Pointer<Utf8>>,
  )
>(symbol: 'map_texture_create')
external int mapTextureCreate(
  int engine,
  double pixelRatio,
  int copyFree,
  Pointer<NativeFunction<MapTextureEventCallback>> callback,
  Pointer<Pointer<Utf8>> headerStrings,
  Pointer<Int32> headerCounts,
  int ruleCount,
  Pointer<Pointer<Utf8>> outError,
);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'map_texture_string_free')
external void mapTextureStringFree(Pointer<Utf8> string);

@Native<Int32 Function(Int64)>(symbol: 'map_texture_set_maximum_cache_size')
external int mapTextureSetMaximumCacheSize(int bytes);

@Native<Int32 Function(Int64, Pointer<Int64>, Int32)>(
  symbol: 'map_texture_texture_ids',
)
external int mapTextureTextureIds(
  int handle,
  Pointer<Int64> outIds,
  int capacity,
);

@Native<Int32 Function(Int64, Pointer<MapTextureFrameStruct>)>(
  symbol: 'map_texture_select_newest',
)
external int mapTextureSelectNewest(
  int handle,
  Pointer<MapTextureFrameStruct> out,
);

@Native<Int32 Function(Int64, Pointer<Utf8>)>(
  symbol: 'map_texture_load_style_url',
)
external int mapTextureLoadStyleUrl(int handle, Pointer<Utf8> url);

@Native<Int32 Function(Int64, Pointer<Utf8>)>(
  symbol: 'map_texture_load_style_json',
)
external int mapTextureLoadStyleJson(int handle, Pointer<Utf8> json);

@Native<Int32 Function(Int64, Double, Double, Double, Double, Int64)>(
  symbol: 'map_texture_set_camera',
)
external int mapTextureSetCamera(
  int handle,
  double latitude,
  double longitude,
  double zoom,
  double bearing,
  int seq,
);

@Native<
  Int32 Function(
    Int64,
    Int64,
    Pointer<Double>,
    Pointer<Pointer<Utf8>>,
    Int32,
    Pointer<Utf8>,
  )
>(symbol: 'map_texture_query_rendered_features')
external int mapTextureQueryRenderedFeatures(
  int handle,
  int requestId,
  Pointer<Double> worldCorners,
  Pointer<Pointer<Utf8>> layerIds,
  int layerIdCount,
  Pointer<Utf8> filterJson,
);

@Native<
  Int32 Function(
    Int64,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(symbol: 'map_texture_set_feature_state')
external int mapTextureSetFeatureState(
  int handle,
  Pointer<Utf8> sourceId,
  Pointer<Utf8> sourceLayerId,
  Pointer<Utf8> featureId,
  Pointer<Utf8> stateJson,
);

@Native<
  Int32 Function(
    Int64,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(symbol: 'map_texture_remove_feature_state')
external int mapTextureRemoveFeatureState(
  int handle,
  Pointer<Utf8> sourceId,
  Pointer<Utf8> sourceLayerId,
  Pointer<Utf8> featureId,
  Pointer<Utf8> key,
);

/// `MAP_TEXTURE_SOURCE_LINE_METRICS` of `map_texture_overlay_set_source`.
const mapTextureSourceLineMetrics = 1;

@Native<
  Int32 Function(
    Int64,
    Int64,
    Int32,
    Int32,
    Pointer<Uint8>,
    Int64,
    Pointer<Pointer<Utf8>>,
  )
>(symbol: 'map_texture_overlay_set_source')
external int mapTextureOverlaySetSource(
  int handle,
  int overlayId,
  int sourceIndex,
  int sourceOptions,
  Pointer<Uint8> geojson,
  int length,
  Pointer<Pointer<Utf8>> outError,
);

@Native<Int32 Function(Int64, Int64, Int32)>(
  symbol: 'map_texture_overlay_remove_source',
)
external int mapTextureOverlayRemoveSource(
  int handle,
  int overlayId,
  int sourceIndex,
);

@Native<
  Int32 Function(
    Int64,
    Int64,
    Pointer<Utf8>,
    Int32,
    Pointer<Utf8>,
    Int64,
    Int64,
  )
>(symbol: 'map_texture_overlay_set_layers')
external int mapTextureOverlaySetLayers(
  int handle,
  int overlayId,
  Pointer<Utf8> layersJson,
  int placementKind,
  Pointer<Utf8> belowLayerId,
  int orderChild,
  int orderSeq,
);

@Native<Int32 Function(Int64, Int64)>(symbol: 'map_texture_overlay_remove')
external int mapTextureOverlayRemove(int handle, int overlayId);

@Native<Int32 Function(Int64, Double, Double, Double)>(
  symbol: 'map_texture_resize',
)
external int mapTextureResize(
  int handle,
  double logicalWidth,
  double logicalHeight,
  double pixelRatio,
);

@Native<Int32 Function(Int64, Pointer<MapTextureStatsStruct>)>(
  symbol: 'map_texture_get_stats',
)
external int mapTextureGetStats(int handle, Pointer<MapTextureStatsStruct> out);

@Native<Int32 Function(Int64)>(symbol: 'map_texture_dispose')
external int mapTextureDispose(int handle);

@Native<Void Function(Pointer<MapTextureEventStruct>)>(
  symbol: 'map_texture_event_free',
)
external void mapTextureEventFree(Pointer<MapTextureEventStruct> event);

@Native<Int32 Function()>(symbol: 'map_texture_process_thread_count')
external int mapTextureProcessThreadCount();

@Native<Int32 Function()>(symbol: 'map_texture_thermal_state')
external int mapTextureThermalState();

@Native<Int64 Function()>(symbol: 'map_texture_memory_footprint')
external int mapTextureMemoryFootprint();

@Native<Int32 Function(Pointer<Int64>)>(
  symbol: 'map_texture_released_buffers_alive_for_testing',
)
external int mapTextureReleasedBuffersAliveForTesting(Pointer<Int64> outBytes);

@Native<Void Function(Int32)>(
  symbol: 'map_texture_set_render_ahead_for_testing',
)
external void mapTextureSetRenderAheadForTesting(int mode);

@Native<Int32 Function(Int64, Double)>(
  symbol: 'map_texture_set_display_refresh_rate',
)
external int mapTextureSetDisplayRefreshRate(int handle, double hz);

@Native<Int32 Function(Int32)>(
  symbol: 'map_texture_released_buffers_for_testing',
)
external int mapTextureReleasedBuffersForTesting(int reset);

@Native<Void Function(Int32)>(symbol: 'map_texture_set_paused_for_testing')
external void mapTextureSetPausedForTesting(int paused);

@Native<Void Function()>(symbol: 'map_texture_reduce_memory_use_for_testing')
external void mapTextureReduceMemoryUseForTesting();

@Native<Void Function(Int32)>(symbol: 'map_texture_trim_surfaces_for_testing')
external void mapTextureTrimSurfacesForTesting(int restore);
