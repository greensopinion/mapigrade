// Test hooks for lifecycle behavior that tests can't trigger themselves
// (design D15), and measurement helpers. The hooks call the same native
// functions as the platform's application lifecycle and memory warning
// handlers.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

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

/// The process's physical memory footprint in bytes, the value Xcode's memory
/// gauge shows, or -1 if unknown.
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

/// EXPERIMENT: maps created while this is on render directly into the display
/// buffers instead of copying each frame into them.
void setZeroCopyForTesting(bool on) =>
    mapTextureSetZeroCopyForTesting(on ? 1 : 0);
