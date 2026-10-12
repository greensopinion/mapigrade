// Test hooks for lifecycle behavior that tests can't trigger themselves
// (design D15), and measurement helpers. The hooks call the same native
// functions as the platform's application lifecycle and memory warning
// handlers.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// The number of threads in this process, for lifecycle tests.
int processThreadCount() => mapTextureProcessThreadCount();

/// Pauses or resumes rendering of every map, as the platform does when the
/// application enters the background or the foreground.
void setRenderingPausedForTesting(bool paused) =>
    mapTextureSetPausedForTesting(paused ? 1 : 0);

/// Asks every map to release cached renderer resources, as the platform does
/// after a memory warning.
void reduceMemoryUseForTesting() => mapTextureReduceMemoryUseForTesting();

/// The device's thermal state, for measurements: `nominal`, `fair`,
/// `serious`, `critical`, or `unknown`.
String thermalStateForTesting() => switch (mapTextureThermalState()) {
  0 => 'nominal',
  1 => 'fair',
  2 => 'serious',
  3 => 'critical',
  _ => 'unknown',
};

/// The process's memory use in bytes, or -1 if unknown: on macOS and iOS the
/// physical memory footprint, the value Xcode's memory gauge shows; on Android
/// the proportional set size (PSS).
int memoryFootprintForTesting() => mapTextureMemoryFootprint();

/// Display buffers that the plugin released since the last
/// [resetReleasedBuffersForTesting] and that are still alive, because
/// something other than the plugin keeps them alive.
({int released, int alive, int aliveBytes}) releasedBuffersForTesting() {
  final bytes = calloc<Int64>();
  try {
    final alive = mapTextureReleasedBuffersAliveForTesting(bytes);
    return (
      released: mapTextureReleasedBuffersForTesting(0),
      alive: alive,
      aliveBytes: bytes.value,
    );
  } finally {
    calloc.free(bytes);
  }
}

/// On Android, makes Flutter remove the surfaces the maps render into, as it
/// does when the activity stops, or with [restore], provide them again, as it
/// does when the activity resumes. Does nothing on macOS and iOS, where the
/// plugin owns the display buffers.
void trimSurfacesForTesting({required bool restore}) =>
    mapTextureTrimSurfacesForTesting(restore ? 1 : 0);

/// Starts a new count for [releasedBuffersForTesting].
void resetReleasedBuffersForTesting() => mapTextureReleasedBuffersForTesting(1);

/// When maps render without waiting until Flutter has taken the latest frame:
/// `null` while a frame takes longer than a display refresh interval (the
/// default), `false` never, `true` always.
void setRenderAheadForTesting(bool? always) =>
    mapTextureSetRenderAheadForTesting(switch (always) {
      null => 0,
      false => -1,
      true => 1,
    });
