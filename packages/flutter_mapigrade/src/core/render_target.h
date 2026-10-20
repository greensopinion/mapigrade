// The platform-specific part of a map texture: where MapLibre renders, how
// Flutter gets the frames, and the Flutter texture registration. There are two
// kinds of target (design D52):
//
// - A buffer target (macOS and iOS) owns a set of display buffers, one per
//   display slot, and registers one Flutter texture per slot (design D122).
//   Dart chooses the slot to display, and Flutter's raster thread takes its
//   buffer through MapTexture::Present(slot).
//   A copy-free map, the default, renders directly into the free buffer, made
//   the session's target with set_target before each render (design D20).
//   Otherwise the session renders into one render texture, and each frame is
//   copied on the GPU into a free buffer (design D3b).
// - A surface target (Android) renders into a surface whose buffers the
//   plugin receives as images, one per frame. The session presents each frame
//   itself, so there is no copy and no Present(). Display slots refer to the
//   images, and all slots share one Flutter texture: when Dart chooses a
//   frame, the target gives its image to Flutter (designs D130 to D135).
//
// The core in this directory has no platform dependencies. Each platform
// implements one kind of target and the four functions at the end of this
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

  // The number of display slots, each with its own Flutter texture.
  virtual int slot_count() const { return 1; }

  // The id of the registered Flutter texture of `slot`.
  virtual int64_t texture_id(int slot) const = 0;

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
  // Unregisters the Flutter textures.
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
  // with the prepared one. The buffer of slot `chosen` of the outgoing set,
  // the slot Dart chose last (if `chosen` >= 0), stays displayable as the
  // fallback until ReleaseFallbackLocked(), so that Flutter shows the frame
  // Dart displays during a resize (design D126).
  virtual void SwapBuffersLocked(int chosen) = 0;

  // Flutter's raster thread. Returns the buffer to display for slot `index`
  // (or the fallback if `index` is -1), retained for the caller, or null if
  // there is none. Called under the BufferState lock from MapTexture::Present.
  // The return type is platform-specific (macOS: CVPixelBufferRef).
  virtual void* CopyBufferLocked(int index) = 0;

  // The platform thread, under the BufferState lock: Dart chose a frame of
  // the current set, so the fallback is no longer needed.
  virtual void ReleaseFallbackLocked() = 0;

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

  // The platform thread, from MapTexture::SelectNewest. Tells Flutter that the
  // texture of `slot` has a new frame, before the Flutter frame that Dart is
  // building is rasterized (design D123).
  virtual void FrameAvailable(int slot) = 0;

  // Map thread. Tells Flutter that every slot's texture has a new frame,
  // after a resize (see MapTexture::MaybeNotifyAfterResize).
  virtual void FrameAvailable() = 0;

  // Map thread, after the session is destroyed. Releases all buffers.
  virtual void ReleaseBuffersLocked() = 0;
};

// A target that presents through a surface whose buffers the plugin receives
// as images (Android). Each render_update that renders a frame also queues it
// on the surface. When the frame's image arrives, the target calls
// MapTexture::OnFrameImage, which publishes the frame into its slot (design
// D131).
class SurfaceRenderTarget : public RenderTarget {
 public:
  SurfaceRenderTarget* AsSurfaceTarget() override { return this; }

  // Map thread, before a render_update: the frame the session presents next
  // has the id `frame_id`, which the target attaches to the frame so that it
  // can tell which frame an image holds.
  virtual void WillRender(uint64_t frame_id) {}

  // The platform thread, under the BufferState lock, from MapTexture::SelectNewest:
  // Dart chose the frame in `slot`, so give its image to Flutter for the
  // Flutter frame that Dart is building (design D132).
  virtual void FrameAvailable(int slot) = 0;

  // Under the BufferState lock, on the thread that freed the slot: `slot` no
  // longer holds a frame that Flutter may display, so release its image, if
  // it has one (design D133). The map thread frees only slots without an
  // image.
  virtual void SlotFreed(int slot) = 0;

  // Attach() and SetTarget() make the session present through the current
  // surface.

  // Map thread. Whether the session can present a frame now. False while the
  // target has no surface from Flutter, for example after Flutter removed it
  // under memory pressure.
  virtual bool CanPresent() const = 0;

  // Map thread, after the session is destroyed. Releases the surfaces.
  virtual void ReleaseSurfaces() = 0;
};

// The error of a map creation with the token of an engine that has detached
// the plugin, or that the plugin never gave out (design D156).
inline constexpr const char* kEngineDetachedError =
    "the Flutter engine of this isolate has detached flutter_mapigrade";

// Creates the platform render target for `owner` and registers its Flutter
// textures with the engine of the token `engine`. With `copy_free`, a buffer
// target renders directly into the display buffers; a surface target ignores
// it. Returns null on failure, and may set `out_error`.
std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner, bool copy_free, int64_t engine,
    std::string* out_error);

// The path of MapLibre's tile cache database, or an empty string for none.
std::string PlatformCachePath();

// The root of asset:// URLs, or empty if unknown (design D83).
std::string PlatformAssetPath();

// Runs `work` in the platform's per-iteration scope on the map thread. On
// Apple platforms this is an autorelease pool, so that Objective-C objects
// autoreleased on the map thread are released after each loop iteration.
void RunInPlatformScope(const std::function<void()>& work);

}  // namespace map_texture
