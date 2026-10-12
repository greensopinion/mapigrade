// A fake of the MapLibre Native FFI functions that the core calls, so that
// tests can run MapTexture with a fake render target. Runtime, map and session
// handles are plain numbers; the pump parks until a wake source is signalled,
// a render update is queued, or the timeout ends; render_update renders a
// frame each time it is called.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "mln.h"

namespace fake_mln {

// Resets the counters, recorded render starts and recorded calls.
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

// A recorded call of mln_runtime_create, mln_map_create, the style loads, or
// the cache size functions, in the order the core made them.
struct Call {
  std::string name;
  // The size, for mln_runtime_set_maximum_ambient_cache_size_start.
  uint64_t size = 0;
};

// The calls recorded since the last Reset().
std::vector<Call> Calls();

// The status that mln_runtime_set_maximum_ambient_cache_size_start returns;
// MLN_STATUS_OK until set. Not reset by Reset().
void SetMaximumCacheSizeStatus(mln_status status);

}  // namespace fake_mln
