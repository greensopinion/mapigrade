// Task 2.1 of the adopt-ffi-core-executor change (design D187): whether the
// native tests can run against the real MapLibre Native FFI with a headless
// target. On the map thread's model of design D180, it creates a runtime and a
// map, loads an inline style, attaches a session-owned Metal texture ring with
// the caller-graphics-thread driver, renders one frame demand, and disposes
// everything, waiting for each completion.
#import <Metal/Metal.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>

#include <MaplibreNativeC/maplibre_native_c.h>

namespace {

// One completion that the test waits for.
struct Waiter {
  std::mutex mutex;
  std::condition_variable cv;
  bool done = false;
  int32_t status = MLN_STATUS_OK;
  std::string value;
  std::string diagnostic;

  static void Callback(void* user_data, const mln_completion_result* result) {
    auto* self = static_cast<Waiter*>(user_data);
    std::lock_guard lock(self->mutex);
    self->status = result->status;
    if (result->value != nullptr && result->value_size > 0) {
      self->value.assign(static_cast<const char*>(result->value),
                         result->value_size);
    }
    if (result->diagnostic.size > 0) {
      self->diagnostic.assign(static_cast<const char*>(result->diagnostic.data),
                              result->diagnostic.size);
    }
    self->done = true;
    self->cv.notify_all();
  }

  mln_completion Completion() {
    mln_completion completion{};
    completion.size = sizeof(completion);
    completion.callback = &Waiter::Callback;
    completion.user_data = this;
    return completion;
  }

  bool Done() {
    std::lock_guard lock(mutex);
    return done;
  }

  bool WaitFor(std::chrono::seconds timeout) {
    std::unique_lock lock(mutex);
    return cv.wait_for(lock, timeout, [this] { return done; });
  }
};

mln_diagnostic NewDiagnostic() {
  mln_diagnostic diagnostic{};
  diagnostic.size = sizeof(diagnostic);
  return diagnostic;
}

int failures = 0;

bool Check(bool ok, const char* what, mln_status status,
           const mln_diagnostic& diagnostic) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s (status %d): %s\n", what, status,
                 diagnostic.message);
    ++failures;
  }
  return ok;
}

bool Check(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
  return ok;
}

// Services the session's driver work until `waiter` completes, as the map
// thread does, or until the timeout.
bool ServiceUntil(mln_render_session session, Waiter& waiter) {
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(30);
  while (!waiter.Done() && std::chrono::steady_clock::now() < deadline) {
    mln_render_session_service_driver_work(session, nullptr);
    if (!waiter.Done()) waiter.WaitFor(std::chrono::seconds(0));
  }
  return waiter.Done();
}

constexpr const char* kStyle = R"({
  "version": 8,
  "sources": {},
  "layers": [{"id": "background", "type": "background",
              "paint": {"background-color": "#3366cc"}}]
})";

}  // namespace

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!Check(device != nil, "MTLCreateSystemDefaultDevice")) return 1;

    mln_diagnostic diagnostic = NewDiagnostic();
    mln_runtime_options runtime_options = mln_runtime_options_default();
    mln_runtime runtime = MLN_HANDLE_NULL;
    mln_status status =
        mln_runtime_create(&runtime_options, &runtime, &diagnostic);
    if (!Check(status == MLN_STATUS_OK, "mln_runtime_create", status,
               diagnostic)) {
      return 1;
    }

    mln_map_options map_options = mln_map_options_default();
    map_options.initial_extent.width = 256;
    map_options.initial_extent.height = 256;
    map_options.initial_extent.scale_factor = 1;
    Waiter created;
    mln_completion create_done = created.Completion();
    status = mln_runtime_create_map(runtime, &map_options, &create_done,
                                    &diagnostic);
    mln_map map = MLN_HANDLE_NULL;
    if (Check(status == MLN_STATUS_OK, "mln_runtime_create_map", status,
              diagnostic) &&
        Check(created.WaitFor(std::chrono::seconds(30)) &&
                  created.status == MLN_STATUS_OK &&
                  created.value.size() >= sizeof(mln_map),
              "map creation completes")) {
      std::memcpy(&map, created.value.data(), sizeof(mln_map));
    }

    mln_render_session session = MLN_HANDLE_NULL;
    if (map != MLN_HANDLE_NULL) {
      Waiter styled;
      mln_completion style_done = styled.Completion();
      mln_buffer_view json{kStyle, std::strlen(kStyle)};
      status = mln_map_set_style_json(map, json, &style_done, &diagnostic);
      Check(status == MLN_STATUS_OK && styled.WaitFor(std::chrono::seconds(30)) &&
                styled.status == MLN_STATUS_OK,
            "mln_map_set_style_json", status, diagnostic);

      mln_metal_owned_texture_descriptor descriptor =
          mln_metal_owned_texture_descriptor_default();
      descriptor.extent.width = 256;
      descriptor.extent.height = 256;
      descriptor.extent.scale_factor = 1;
      descriptor.context.device = (__bridge void*)device;
      mln_render_session_attach_options options =
          mln_render_session_attach_options_default();
      options.driver = MLN_RENDER_DRIVER_CALLER_GRAPHICS_THREAD;
      Waiter attached;
      mln_completion attach_done = attached.Completion();
      status = mln_map_attach_metal_owned_texture(
          map, &descriptor, &options, &session, &attach_done, &diagnostic);
      if (!Check(status == MLN_STATUS_OK, "mln_map_attach_metal_owned_texture",
                 status, diagnostic) ||
          !Check(ServiceUntil(session, attached) &&
                     attached.status == MLN_STATUS_OK,
                 "the attachment completes")) {
        session = MLN_HANDLE_NULL;
      }
    }

    if (session != MLN_HANDLE_NULL) {
      mln_frame_demand demand = mln_frame_demand_default();
      demand.flags = 0;  // Render unconditionally.
      demand.token = 1;
      status = mln_render_session_request_frame(session, &demand, &diagnostic);
      Check(status == MLN_STATUS_OK, "mln_render_session_request_frame",
            status, diagnostic);
      bool rendered = false;
      auto deadline =
          std::chrono::steady_clock::now() + std::chrono::seconds(30);
      while (!rendered && std::chrono::steady_clock::now() < deadline) {
        mln_render_session_service_driver_work(session, nullptr);
        mln_render_frame_batch batch = MLN_HANDLE_NULL;
        if (mln_render_session_drain_frame_results(session, &batch, nullptr) !=
            MLN_STATUS_OK) {
          continue;
        }
        mln_render_frame_batch_view view{};
        view.size = sizeof(view);
        if (mln_render_frame_batch_get(batch, &view, nullptr) == MLN_STATUS_OK) {
          const auto* base = reinterpret_cast<const char*>(view.results);
          for (size_t i = 0; i < view.result_count; ++i) {
            const auto* result = reinterpret_cast<const mln_render_frame_result*>(
                base + i * view.result_size);
            std::printf("frame result: token %llu disposition %u\n",
                        static_cast<unsigned long long>(result->token),
                        result->disposition);
            if (result->token == 1 &&
                result->disposition == MLN_RENDER_RESULT_RENDERED) {
              rendered = true;
            }
          }
        }
        mln_render_frame_batch_release(batch);
      }
      Check(rendered, "the frame demand renders a frame");

      Waiter detached;
      mln_completion detach_done = detached.Completion();
      status = mln_render_session_detach(session, &detach_done, &diagnostic);
      Check(status == MLN_STATUS_OK && ServiceUntil(session, detached),
            "mln_render_session_detach", status, diagnostic);
      mln_render_session_release(session, nullptr);
    }

    if (map != MLN_HANDLE_NULL) {
      Waiter released;
      mln_completion release_done = released.Completion();
      status = mln_map_release(map, &release_done, &diagnostic);
      Check(status == MLN_STATUS_OK && released.WaitFor(std::chrono::seconds(30)),
            "mln_map_release", status, diagnostic);
    }
    Waiter runtime_released;
    mln_completion runtime_done = runtime_released.Completion();
    status = mln_runtime_release(runtime, &runtime_done, &diagnostic);
    Check(status == MLN_STATUS_OK &&
              runtime_released.WaitFor(std::chrono::seconds(30)),
          "mln_runtime_release", status, diagnostic);
  }
  if (failures == 0) std::printf("PASS: ffi_headless_test\n");
  return failures == 0 ? 0 : 1;
}
