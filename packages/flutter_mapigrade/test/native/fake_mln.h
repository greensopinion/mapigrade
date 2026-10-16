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

struct Header {
  std::string name;
  std::string value;
  bool operator==(const Header&) const = default;
};

struct HeaderRule {
  uint32_t kind = 0;
  uint32_t flags = 0;
  std::string url;
  std::vector<Header> headers;
};

// Calls of mln_runtime_set_http_header_transform since the last Reset().
int HeaderTransformRegistrations();

// Whether the last registered callback is the adapter's.
bool HeaderTransformUsesAdapter();

// The last registered rules, read from the table now, while its map exists.
std::vector<HeaderRule> HeaderRules();

// The status and message of mln_adapter_http_header_validate for `name`;
// not reset by Reset().
void SetHeaderValidateResult(std::string name, mln_status status,
                             std::string message);

// The last asset path given to mln_runtime_create, or "<null>".
std::string LastAssetPath();

// A MapLibre log record.
struct LogRecord {
  uint32_t severity = MLN_LOG_SEVERITY_ERROR;
  uint32_t event = MLN_LOG_EVENT_STYLE;
  std::string message;
};

// Queues `record`, which the next mln_runtime_pump passes to the log callback
// on its thread, and wakes the pump.
void QueueLogRecord(LogRecord record);

// Passes `record` to the log callback on the calling thread.
void Log(const LogRecord& record);

// Calls of mln_log_set_callback since the process started.
int LogCallbackRegistrations();

// The status and message of mln_runtime_create. Not reset by Reset().
void SetRuntimeCreateResult(mln_status status, std::string message);

}  // namespace fake_mln
