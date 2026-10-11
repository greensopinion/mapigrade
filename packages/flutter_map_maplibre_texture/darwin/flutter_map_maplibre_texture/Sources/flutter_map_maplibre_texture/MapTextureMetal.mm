// macOS and iOS render target (designs D3b and D4). MapLibre renders through a
// borrowed-texture session into one private MTLTexture. Each rendered frame is
// copied on the GPU into one of three IOSurface-backed CVPixelBuffers, each
// wrapped as an MTLTexture made from its IOSurface, and Flutter samples that
// IOSurface through FlutterTexture. No pixels pass through CPU memory.
//
// The textures are made directly from the IOSurfaces rather than through a
// CVMetalTextureCache: a cache keeps the IOSurfaces of released buffers alive
// until a flush after its maximum texture age, which kept the memory of
// replaced buffer sets alive after resizes.

#import <CoreVideo/CoreVideo.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
#import <Metal/Metal.h>
#include <mach/mach.h>

#import <IOSurface/IOSurfaceRef.h>

#include <array>
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

#include "MapTextureRegistry.h"
#include "core/map_texture.h"
#include "core/render_target.h"

using map_texture::kBufferCount;
using map_texture::MapTexture;
using map_texture::TargetSize;

// The FlutterTexture that Flutter's raster thread asks for frames.
@interface MLTFlutterTexture : NSObject <FlutterTexture>
- (instancetype)initWithOwner:(std::weak_ptr<MapTexture>)owner;
@end

@implementation MLTFlutterTexture {
  std::weak_ptr<MapTexture> _owner;
}

- (instancetype)initWithOwner:(std::weak_ptr<MapTexture>)owner {
  self = [super init];
  if (self) _owner = std::move(owner);
  return self;
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  auto owner = _owner.lock();
  if (!owner) return nullptr;
  return static_cast<CVPixelBufferRef>(owner->Present());
}

@end

// EXPERIMENT (design D20): maps created while this is on render directly into
// the display buffers.
static std::atomic<bool> gRendersIntoBuffers{false};

// For tests: the IOSurfaces of released pixel buffers, to check that they are
// freed (map_texture_released_buffers_alive_for_testing).
static std::mutex gReleasedMutex;
static std::vector<std::pair<IOSurfaceID, size_t>> gReleased;

static void RecordReleased(CVPixelBufferRef buffer) {
  IOSurfaceRef surface = CVPixelBufferGetIOSurface(buffer);
  if (surface == nullptr) return;
  std::lock_guard lock(gReleasedMutex);
  gReleased.emplace_back(IOSurfaceGetID(surface),
                         IOSurfaceGetAllocSize(surface));
}

namespace map_texture {
namespace {

// Runs `block` on the main thread and waits for it.
void RunOnMainSync(dispatch_block_t block) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
}

struct BufferSet {
  std::array<CVPixelBufferRef, kBufferCount> pixel_buffers{};
  // Textures made from the pixel buffers' IOSurfaces, the copy destinations.
  std::array<id<MTLTexture>, kBufferCount> textures{};
  // The texture MapLibre renders into.
  id<MTLTexture> render_texture = nil;
  TargetSize size{};

  bool empty() const { return pixel_buffers[0] == nullptr; }

  void Release() {
    render_texture = nil;
    for (int i = 0; i < kBufferCount; ++i) {
      textures[i] = nil;
      if (pixel_buffers[i] != nullptr) {
        RecordReleased(pixel_buffers[i]);
        CVPixelBufferRelease(pixel_buffers[i]);
      }
      pixel_buffers[i] = nullptr;
    }
  }
};

class MetalRenderTarget : public RenderTarget {
 public:
  MetalRenderTarget(id<MTLDevice> device,
                    NSObject<FlutterTextureRegistry>* registry,
                    MLTFlutterTexture* texture, int64_t texture_id,
                    bool renders_into_buffers)
      : renders_into_buffers_(renders_into_buffers),
        device_(device),
        queue_([device newCommandQueue]),
        registry_(registry),
        texture_(texture),
        texture_id_(texture_id) {}

  ~MetalRenderTarget() override {
    current_.Release();
    prepared_.Release();
    if (fallback_ != nullptr) CVPixelBufferRelease(fallback_);
  }

  int64_t texture_id() const override { return texture_id_; }

  bool PrepareBuffers(const TargetSize& size) override {
    prepared_.Release();
    NSDictionary* attributes = @{
      (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
      (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    MTLTextureDescriptor* buffer_descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:size.physical_width
                                    height:size.physical_height
                                 mipmapped:NO];
    buffer_descriptor.usage =
        MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    for (int i = 0; i < kBufferCount; ++i) {
      CVReturn result = CVPixelBufferCreate(
          kCFAllocatorDefault, size.physical_width, size.physical_height,
          kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes,
          &prepared_.pixel_buffers[i]);
      if (result != kCVReturnSuccess) {
        prepared_.Release();
        return false;
      }
      prepared_.textures[i] = [device_
          newTextureWithDescriptor:buffer_descriptor
                         iosurface:CVPixelBufferGetIOSurface(
                                       prepared_.pixel_buffers[i])
                             plane:0];
      if (prepared_.textures[i] == nil) {
        prepared_.Release();
        return false;
      }
    }
    prepared_.size = size;
    // Rendering directly into the buffers needs no separate render texture.
    if (renders_into_buffers_) return true;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:size.physical_width
                                    height:size.physical_height
                                 mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;
    prepared_.render_texture = [device_ newTextureWithDescriptor:descriptor];
    if (prepared_.render_texture == nil) {
      prepared_.Release();
      return false;
    }
    return true;
  }

  void SwapBuffersLocked(int latest) override {
    if (latest >= 0 && !current_.empty()) {
      if (fallback_ != nullptr) CVPixelBufferRelease(fallback_);
      fallback_ = CVPixelBufferRetain(current_.pixel_buffers[latest]);
    }
    current_.Release();
    current_ = prepared_;
    prepared_ = BufferSet{};
  }

  void* CopyBufferLocked(int index) override {
    if (index >= 0 && !current_.empty()) {
      // A frame of the current set exists, so the frame kept from before the
      // last resize is no longer needed.
      if (fallback_ != nullptr) {
        CVPixelBufferRelease(fallback_);
        fallback_ = nullptr;
      }
      return CVPixelBufferRetain(current_.pixel_buffers[index]);
    }
    if (fallback_ != nullptr) return CVPixelBufferRetain(fallback_);
    return nullptr;
  }

  mln_status Attach(mln_map map, const TargetSize& size,
                    mln_render_session* out_session) override {
    mln_metal_borrowed_texture_descriptor descriptor = Descriptor(size);
    return mln_metal_borrowed_texture_attach(map, &descriptor, out_session);
  }

  mln_status SetTarget(mln_render_session session,
                       const TargetSize& size) override {
    mln_metal_borrowed_texture_descriptor descriptor = Descriptor(size);
    return mln_metal_borrowed_texture_set_target(session, &descriptor);
  }

  bool RendersIntoBuffers() const override { return renders_into_buffers_; }

  // Needs the FFI patch in scripts/patches/: without it, each same-size
  // set_target makes the map publish another render update (design D3).
  mln_status SelectBuffer(mln_render_session session, int index) override {
    mln_metal_borrowed_texture_descriptor descriptor =
        Descriptor(current_.size, current_.textures[index]);
    return mln_metal_borrowed_texture_set_target(session, &descriptor);
  }

  bool CopyToBuffer(int index) override {
    id<MTLCommandBuffer> commands = [queue_ commandBuffer];
    id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
    [blit copyFromTexture:current_.render_texture
                toTexture:current_.textures[index]];
    [blit endEncoding];
    [commands commit];
    // MapLibre's render_update has already waited for its own command
    // buffer, so this wait covers the copy only.
    [commands waitUntilCompleted];
    return commands.status == MTLCommandBufferStatusCompleted;
  }

  void FrameAvailable() override {
    // See design.md, task 3.4, for why this dispatches to the main queue.
    NSObject<FlutterTextureRegistry>* registry = registry_;
    int64_t texture_id = texture_id_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [registry textureFrameAvailable:texture_id];
    });
  }

  void ReleaseBuffersLocked() override {
    current_.Release();
    prepared_.Release();
    if (fallback_ != nullptr) CVPixelBufferRelease(fallback_);
    fallback_ = nullptr;
  }

  void Unregister() override {
    NSObject<FlutterTextureRegistry>* registry = registry_;
    int64_t texture_id = texture_id_;
    RunOnMainSync(^{
      [registry unregisterTexture:texture_id];
    });
  }

 private:
  // The descriptor for the current render texture, or with renders into
  // buffers, for the current set's first buffer, until SelectBuffer().
  mln_metal_borrowed_texture_descriptor Descriptor(const TargetSize& size) {
    return Descriptor(size, renders_into_buffers_ ? current_.textures[0]
                                                  : current_.render_texture);
  }

  mln_metal_borrowed_texture_descriptor Descriptor(const TargetSize& size,
                                                   id<MTLTexture> texture) {
    mln_metal_borrowed_texture_descriptor descriptor =
        mln_metal_borrowed_texture_descriptor_default();
    descriptor.extent = size.extent;
    descriptor.physical_width = size.physical_width;
    descriptor.physical_height = size.physical_height;
    descriptor.texture = (__bridge void*)texture;
    return descriptor;
  }

  const bool renders_into_buffers_;
  id<MTLDevice> device_;
  id<MTLCommandQueue> queue_;
  NSObject<FlutterTextureRegistry>* registry_;
  MLTFlutterTexture* texture_;
  const int64_t texture_id_;

  BufferSet current_;
  BufferSet prepared_;
  // The latest frame from before the last resize, shown until a frame of the
  // new size is published.
  CVPixelBufferRef fallback_ = nullptr;
};

}  // namespace

std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner) {
  NSObject<FlutterTextureRegistry>* registry = MLTTextureRegistry();
  if (registry == nil) return nullptr;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) return nullptr;
  MLTFlutterTexture* texture =
      [[MLTFlutterTexture alloc] initWithOwner:std::move(owner)];
  __block int64_t texture_id = 0;
  RunOnMainSync(^{
    texture_id = [registry registerTexture:texture];
  });
  return std::make_unique<MetalRenderTarget>(
      device, registry, texture, texture_id, gRendersIntoBuffers.load());
}

// The map thread is a std::thread with no autorelease pool, so objects
// autoreleased there, such as each frame's command buffer and with it the
// buffer it copied into, stayed alive until the thread exited at dispose.
void RunInPlatformScope(const std::function<void()>& work) {
  @autoreleasepool {
    work();
  }
}

std::string PlatformCachePath() {
  NSURL* caches = [[NSFileManager defaultManager]
      URLsForDirectory:NSCachesDirectory
             inDomains:NSUserDomainMask]
      .firstObject;
  if (caches == nil) return {};
  NSURL* directory =
      [caches URLByAppendingPathComponent:@"flutter_map_maplibre_texture"
                              isDirectory:YES];
  [[NSFileManager defaultManager] createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
  return [directory URLByAppendingPathComponent:@"cache.db"].path.UTF8String;
}

}  // namespace map_texture

extern "C" int32_t map_texture_process_thread_count(void) {
  thread_act_array_t threads = nullptr;
  mach_msg_type_number_t count = 0;
  if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) {
    return -1;
  }
  for (mach_msg_type_number_t i = 0; i < count; ++i) {
    mach_port_deallocate(mach_task_self(), threads[i]);
  }
  vm_deallocate(mach_task_self(), reinterpret_cast<vm_address_t>(threads),
                count * sizeof(thread_act_t));
  return static_cast<int32_t>(count);
}

extern "C" int32_t map_texture_thermal_state(void) {
  return static_cast<int32_t>([NSProcessInfo processInfo].thermalState);
}

extern "C" int64_t map_texture_memory_footprint(void) {
  task_vm_info_data_t info{};
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO,
                reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS) {
    return -1;
  }
  return static_cast<int64_t>(info.phys_footprint);
}

extern "C" int32_t map_texture_released_buffers_alive_for_testing(
    int64_t* out_bytes) {
  std::lock_guard lock(gReleasedMutex);
  int32_t alive = 0;
  int64_t bytes = 0;
  for (auto [id, size] : gReleased) {
    // A lookup by id finds the surface only while something keeps it alive.
    // The ids of freed surfaces can be reused, so tests reset the list first.
    IOSurfaceRef surface = IOSurfaceLookup(id);
    if (surface == nullptr) continue;
    CFRelease(surface);
    ++alive;
    bytes += static_cast<int64_t>(size);
  }
  if (out_bytes != nullptr) *out_bytes = bytes;
  return alive;
}

extern "C" int32_t map_texture_released_buffers_for_testing(int32_t reset) {
  std::lock_guard lock(gReleasedMutex);
  auto count = static_cast<int32_t>(gReleased.size());
  if (reset != 0) gReleased.clear();
  return count;
}

extern "C" void map_texture_set_zero_copy_for_testing(int32_t on) {
  gRendersIntoBuffers.store(on != 0);
}
