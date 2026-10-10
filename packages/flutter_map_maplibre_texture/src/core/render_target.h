// The platform-specific part of a map texture: the render texture MapLibre
// renders into, the buffer set Flutter displays, and the Flutter texture
// registration.
//
// The session renders into one render texture, and each frame is copied on
// the GPU into a free buffer (design D3b). Rendering directly into the buffers
// and switching targets with set_target (D3) made MapLibre render
// continuously; see design.md.
//
// The core in this directory has no platform dependencies. Each platform
// implements RenderTarget and the two factory functions at the end of this
// file (macOS and iOS: darwin/.../MapTextureMetal.mm).
#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "mln.h"

namespace map_texture {

class MapTexture;

// The physical and logical size of a buffer set.
struct TargetSize {
  uint32_t physical_width = 0;
  uint32_t physical_height = 0;
  mln_render_target_extent extent{};
};

class RenderTarget {
 public:
  virtual ~RenderTarget() = default;

  // The id of the registered Flutter texture.
  virtual int64_t texture_id() const = 0;

  // Map thread. Allocates a new buffer set and a new render texture of
  // `size`. They replace the current ones in SwapBuffersLocked().
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

  // Map thread. Attaches a render session to `map` that renders into the
  // render texture.
  virtual mln_status Attach(mln_map map, const TargetSize& size,
                            mln_render_session* out_session) = 0;

  // Map thread. Changes the session's target to the render texture of the
  // current set, after a resize.
  virtual mln_status SetTarget(mln_render_session session,
                               const TargetSize& size) = 0;

  // Map thread. Copies the render texture into buffer `index` on the GPU and
  // returns when the copy has completed (design D3b).
  virtual bool CopyToBuffer(int index) = 0;

  // Map thread. Tells Flutter that a new frame is available.
  virtual void FrameAvailable() = 0;

  // Map thread, after the session is destroyed. Releases all buffers.
  virtual void ReleaseBuffersLocked() = 0;

  // The thread that disposes the map, after the map thread has stopped.
  // Unregisters the Flutter texture.
  virtual void Unregister() = 0;
};

// Creates the platform render target for `owner` and registers its Flutter
// texture. Returns null on failure.
std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner);

// The path of MapLibre's tile cache database, or an empty string for none.
std::string PlatformCachePath();

}  // namespace map_texture
