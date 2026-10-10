// Test hooks for lifecycle behavior that tests can't trigger themselves
// (design D15). They call the same native functions as the platform's
// application lifecycle and memory warning handlers.
import 'bindings.dart';

/// Pauses or resumes rendering of every map, as the platform does when the
/// application enters the background or the foreground.
void setRenderingPausedForTesting(bool paused) =>
    mapTextureSetPausedForTesting(paused ? 1 : 0);

/// Asks every map to release cached renderer resources, as the platform does
/// after a memory warning.
void reduceMemoryUseForTesting() => mapTextureReduceMemoryUseForTesting();
