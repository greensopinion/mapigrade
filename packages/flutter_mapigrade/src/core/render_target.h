// The platform-specific part of a map texture: where MapLibre renders, how
// Flutter gets the frames, and the Flutter texture registration. There are two
// kinds of target (design D52):
//
// - A buffer target (macOS and iOS) owns a set of display buffers, and
//   Flutter's raster thread takes the latest one through MapTexture::Present().
//   A copy-free map, the default, renders directly into the free buffer, made
//   the session's target with set_target before each render (design D20).
//   Otherwise the session renders into one render texture, and each frame is
//   copied on the GPU into a free buffer (design D3b).
// - A surface target (Android) renders into a surface whose buffers Flutter
//   displays. The session presents each frame itself, so the target has no
//   buffers, no copy and no Present().
//
// The core in this directory has no platform dependencies. Each platform
// implements one kind of target and the three functions at the end of this
// file (macOS and iOS: darwin/.../MapTextureMetal.mm; Android:
// android/src/main/cpp/map_texture_android.cpp).
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

#include "mln.h"

namespace map_texture {

class MapTexture;
class BufferRenderTarget;
class SurfaceRenderTarget;

// The physical and logical size of a render target.
struct TargetSize {
  uint32_t physical_width = 0;
  uint32_t physical_height = 0;
  mln_render_target_extent extent{};
};

class RenderTarget {
 public:
  virtual ~RenderTarget() = default;

  // The kind of target; exactly one of these returns non-null.
  virtual BufferRenderTarget* AsBufferTarget() { return nullptr; }
  virtual SurfaceRenderTarget* AsSurfaceTarget() { return nullptr; }

  // The id of the registered Flutter texture.
  virtual int64_t texture_id() const = 0;

  // The thread that calls MapTexture::Resize(), before the resize is queued
  // for the map thread. `size` is the size the map thread will apply.
  virtual void WillResize(const TargetSize& size) {}

  // Map thread. Attaches a render session to `map`.
  virtual mln_status Attach(mln_map map, const TargetSize& size,
                            mln_render_session* out_session) = 0;

  // Map thread. Changes the session's target after a resize.
  virtual mln_status SetTarget(mln_render_session session,
                               const TargetSize& size) = 0;

  // The thread that disposes the map, after the map thread has stopped.
  // Unregisters the Flutter texture.
  virtual void Unregister() = 0;
};

// A target with plugin-owned display buffers (macOS and iOS).
class BufferRenderTarget : public RenderTarget {
 public:
  BufferRenderTarget* AsBufferTarget() override { return this; }

  // Map thread. Allocates a new buffer set of `size`, and unless the target
  // renders into the buffers, a new render texture. They replace the current
  // ones in SwapBuffersLocked().
  virtual bool PrepareBuffers(const TargetSize& size) = 0;

  // Map thread, under the BufferState lock. Replaces the current buffer set
  // with the prepared one. The buffer at index `latest` of the outgoing set
  // (if `latest` >= 0) stays displayable until a frame of the new set is
  // published, so that Flutter has a frame to show during a resize.
  virtual void SwapBuffersLocked(int latest) = 0;

  // Flutter's raster thread. Returns the buffer to display for index `index` (or the
  // retained buffer from before the last swap if `index` is -1), retained for
  // the caller. Called under the BufferState lock from MapTexture::Present.
  // The return type is platform-specific (macOS: CVPixelBufferRef).
  virtual void* CopyBufferLocked(int index) = 0;

  // Attach() and SetTarget() make the session render into the render
  // texture, or the current set's first buffer.

  // Map thread. Copies the render texture into buffer `index` on the GPU and
  // returns when the copy has completed (design D3b). Not called when the
  // target renders into the buffers.
  virtual bool CopyToBuffer(int index) = 0;

  // Whether the session renders directly into the display buffers (a
  // copy-free map, design D20). Then SelectBuffer() makes buffer `index` the
  // session's target before each render, and no copy is needed.
  virtual bool RendersIntoBuffers() const { return false; }
  virtual mln_status SelectBuffer(mln_render_session session, int index) {
    return MLN_STATUS_OK;
  }

  // Map thread. Tells Flutter that a new frame is available.
  virtual void FrameAvailable() = 0;

  // Map thread, after the session is destroyed. Releases all buffers.
  virtual void ReleaseBuffersLocked() = 0;
};

// A target that presents through a surface whose buffers Flutter displays
// (Android). Each render_update that renders a frame also queues it for
// display, and Flutter schedules a frame for each queued one, so the target
// has no FrameAvailable().
class SurfaceRenderTarget : public RenderTarget {
 public:
  SurfaceRenderTarget* AsSurfaceTarget() override { return this; }

  // Attach() and SetTarget() make the session present through the current
  // surface.

  // Map thread. Whether the session can present a frame now. False while the
  // target has no surface from Flutter, for example after Flutter removed it
  // under memory pressure.
  virtual bool CanPresent() const = 0;

  // Map thread, after the session is destroyed. Releases the surfaces.
  virtual void ReleaseSurfaces() = 0;
};

// Creates the platform render target for `owner` and registers its Flutter
// texture. With `copy_free`, a buffer target renders directly into the display
// buffers; a surface target ignores it. Returns null on failure.
std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner, bool copy_free);

// The path of MapLibre's tile cache database, or an empty string for none.
std::string PlatformCachePath();

// Runs `work` in the platform's per-iteration scope on the map thread. On
// Apple platforms this is an autorelease pool, so that Objective-C objects
// autoreleased on the map thread are released after each loop iteration.
void RunInPlatformScope(const std::function<void()>& work);

}  // namespace map_texture
