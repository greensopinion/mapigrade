// Bindings for the C ABI in src/core/map_texture_api.h (design D5).
//
// The plugin's native code is linked into the app, so the symbols resolve
// from the process; there is no separate library for Dart to load.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

const int mapTextureOk = 0;
const int mapTextureErrorDisposed = -1;
const int mapTextureErrorInvalidArgument = -2;
const int mapTextureErrorCreateFailed = -3;

const int mapTextureEventStyleLoaded = 0;
const int mapTextureEventLoadingFailed = 1;
const int mapTextureEventRenderError = 2;
const int mapTextureEventIdle = 3;
const int mapTextureEventFrameDisplayed = 4;

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
  external Pointer<Utf8> message;
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
}

typedef MapTextureEventCallback = Void Function(
    Pointer<MapTextureEventStruct> event);

@Native<Int64 Function(Double, Pointer<NativeFunction<MapTextureEventCallback>>)>(
    symbol: 'map_texture_create')
external int mapTextureCreate(
    double pixelRatio, Pointer<NativeFunction<MapTextureEventCallback>> callback);

@Native<Int64 Function(Int64)>(symbol: 'map_texture_texture_id')
external int mapTextureTextureId(int handle);

@Native<Int32 Function(Int64, Pointer<Utf8>)>(
    symbol: 'map_texture_load_style_url')
external int mapTextureLoadStyleUrl(int handle, Pointer<Utf8> url);

@Native<Int32 Function(Int64, Pointer<Utf8>)>(
    symbol: 'map_texture_load_style_json')
external int mapTextureLoadStyleJson(int handle, Pointer<Utf8> json);

@Native<Int32 Function(Int64, Double, Double, Double, Double)>(
    symbol: 'map_texture_set_camera')
external int mapTextureSetCamera(
    int handle, double latitude, double longitude, double zoom, double bearing);

@Native<Int32 Function(Int64, Double, Double, Double)>(
    symbol: 'map_texture_resize')
external int mapTextureResize(
    int handle, double logicalWidth, double logicalHeight, double pixelRatio);

@Native<Int32 Function(Int64, Pointer<MapTextureStatsStruct>)>(
    symbol: 'map_texture_get_stats')
external int mapTextureGetStats(int handle, Pointer<MapTextureStatsStruct> out);

@Native<Int32 Function(Int64)>(symbol: 'map_texture_dispose')
external int mapTextureDispose(int handle);

@Native<Void Function(Pointer<MapTextureEventStruct>)>(
    symbol: 'map_texture_event_free')
external void mapTextureEventFree(Pointer<MapTextureEventStruct> event);

@Native<Int32 Function()>(symbol: 'map_texture_process_thread_count')
external int mapTextureProcessThreadCount();

@Native<Void Function(Int32)>(symbol: 'map_texture_set_paused_for_testing')
external void mapTextureSetPausedForTesting(int paused);

@Native<Void Function()>(symbol: 'map_texture_reduce_memory_use_for_testing')
external void mapTextureReduceMemoryUseForTesting();
