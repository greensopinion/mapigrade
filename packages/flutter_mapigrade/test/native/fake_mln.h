// A fake of the MapLibre Native FFI functions that the core calls, so that
// tests can run MapTexture with a fake render target. Runtime, map and session
// handles are plain numbers; the pump parks until a wake source is signalled,
// a render update is queued, or the timeout ends; render_update renders a
// frame each time it is called.
#pragma once

#include <cstdint>
#include <vector>

#include "mln.h"

namespace fake_mln {

// Resets the counters and recorded render starts.
void Reset();

// Queues a MLN_RUNTIME_EVENT_MAP_RENDER_UPDATE_AVAILABLE event and wakes the
// pump, as MapLibre does when the map changes.
void QueueRenderUpdate();

// The number of render_update calls since the last Reset().
int RenderCount();

// When each render_update since the last Reset() started, read from
// `clock` (see SetClock).
std::vector<int64_t> RenderStarts();

// The clock RenderStarts() reads; null for the steady clock.
void SetClock(int64_t (*now_ns)());

}  // namespace fake_mln
