// macOS render target (designs D3b and D4). MapLibre renders through a
// borrowed-texture session into one private MTLTexture. Each rendered frame is
// copied on the GPU into one of three IOSurface-backed CVPixelBuffers, wrapped
// as MTLTextures through CVMetalTextureCache, and Flutter samples that
// IOSurface through FlutterTexture. No pixels pass through CPU memory.

#import <CoreVideo/CoreVideo.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
#import <Metal/Metal.h>
#include <mach/mach.h>

#include <array>
#include <memory>

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
  std::array<CVMetalTextureRef, kBufferCount> cv_textures{};
  // The texture MapLibre renders into.
  id<MTLTexture> render_texture = nil;
  TargetSize size{};

  bool empty() const { return pixel_buffers[0] == nullptr; }

  void Release() {
    render_texture = nil;
    for (int i = 0; i < kBufferCount; ++i) {
      if (cv_textures[i] != nullptr) CFRelease(cv_textures[i]);
      if (pixel_buffers[i] != nullptr) CVPixelBufferRelease(pixel_buffers[i]);
      cv_textures[i] = nullptr;
      pixel_buffers[i] = nullptr;
    }
  }

  id<MTLTexture> texture(int index) const {
    return CVMetalTextureGetTexture(cv_textures[index]);
  }
};

class MetalRenderTarget : public RenderTarget {
 public:
  MetalRenderTarget(id<MTLDevice> device, CVMetalTextureCacheRef cache,
                    NSObject<FlutterTextureRegistry>* registry,
                    MLTFlutterTexture* texture, int64_t texture_id)
      : device_(device),
        queue_([device newCommandQueue]),
        cache_(cache),
        registry_(registry),
        texture_(texture),
        texture_id_(texture_id) {}

  ~MetalRenderTarget() override {
    current_.Release();
    prepared_.Release();
    if (fallback_ != nullptr) CVPixelBufferRelease(fallback_);
    CFRelease(cache_);
  }

  int64_t texture_id() const override { return texture_id_; }

  bool PrepareBuffers(const TargetSize& size) override {
    prepared_.Release();
    NSDictionary* attributes = @{
      (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
      (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    NSDictionary* texture_attributes = @{
      (id)kCVMetalTextureUsage :
          @(MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget),
    };
    for (int i = 0; i < kBufferCount; ++i) {
      CVReturn result = CVPixelBufferCreate(
          kCFAllocatorDefault, size.physical_width, size.physical_height,
          kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes,
          &prepared_.pixel_buffers[i]);
      if (result != kCVReturnSuccess) {
        prepared_.Release();
        return false;
      }
      result = CVMetalTextureCacheCreateTextureFromImage(
          kCFAllocatorDefault, cache_, prepared_.pixel_buffers[i],
          (__bridge CFDictionaryRef)texture_attributes, MTLPixelFormatBGRA8Unorm,
          size.physical_width, size.physical_height, 0,
          &prepared_.cv_textures[i]);
      if (result != kCVReturnSuccess) {
        prepared_.Release();
        return false;
      }
    }
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
    prepared_.size = size;
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

  bool CopyToBuffer(int index) override {
    id<MTLCommandBuffer> commands = [queue_ commandBuffer];
    id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
    [blit copyFromTexture:current_.render_texture toTexture:current_.texture(index)];
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
  mln_metal_borrowed_texture_descriptor Descriptor(const TargetSize& size) {
    mln_metal_borrowed_texture_descriptor descriptor =
        mln_metal_borrowed_texture_descriptor_default();
    descriptor.extent = size.extent;
    descriptor.physical_width = size.physical_width;
    descriptor.physical_height = size.physical_height;
    descriptor.texture = (__bridge void*)current_.render_texture;
    return descriptor;
  }

  id<MTLDevice> device_;
  id<MTLCommandQueue> queue_;
  CVMetalTextureCacheRef cache_;
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
  CVMetalTextureCacheRef cache = nullptr;
  if (CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil,
                                &cache) != kCVReturnSuccess) {
    return nullptr;
  }
  MLTFlutterTexture* texture =
      [[MLTFlutterTexture alloc] initWithOwner:std::move(owner)];
  __block int64_t texture_id = 0;
  RunOnMainSync(^{
    texture_id = [registry registerTexture:texture];
  });
  return std::make_unique<MetalRenderTarget>(device, cache, registry, texture,
                                             texture_id);
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
