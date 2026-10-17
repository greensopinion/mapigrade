// macOS and iOS render target (designs D3b, D4, D20 and D122). MapLibre
// renders through a borrowed-texture session into one private MTLTexture.
// Each rendered frame is copied on the GPU into one of four IOSurface-backed
// CVPixelBuffers, one per display slot, each wrapped as an MTLTexture made
// from its IOSurface. Each slot has its own registered FlutterTexture, and
// Flutter samples the IOSurface of the slot Dart displays. A copy-free map has
// no private texture: MapLibre renders directly into the buffers' textures. No
// pixels pass through CPU memory.
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
#include <functional>
#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

#include "MapTextureRegistry.h"
#include "core/map_texture.h"
#include "core/render_target.h"

using map_texture::kBufferCount;
using map_texture::MapTexture;
using map_texture::TargetSize;

// The FlutterTexture of one display slot, which Flutter's raster thread asks
// for frames.
@interface MLTFlutterTexture : NSObject <FlutterTexture>
- (instancetype)initWithOwner:(std::weak_ptr<MapTexture>)owner slot:(int)slot;
@end

@implementation MLTFlutterTexture {
  std::weak_ptr<MapTexture> _owner;
  int _slot;
}

- (instancetype)initWithOwner:(std::weak_ptr<MapTexture>)owner slot:(int)slot {
  self = [super init];
  if (self) {
    _owner = std::move(owner);
    _slot = slot;
  }
  return self;
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  auto owner = _owner.lock();
  if (!owner) return nullptr;
  return static_cast<CVPixelBufferRef>(owner->Present(_slot));
}

@end

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
  // Textures made from the pixel buffers' IOSurfaces: the copy destinations,
  // or for a copy-free map, the render targets.
  std::array<id<MTLTexture>, kBufferCount> textures{};
  // The texture MapLibre renders into; nil for a copy-free map.
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

// The registered textures, one per display slot.
struct SlotTextures {
  std::array<MLTFlutterTexture*, kBufferCount> textures{};
  std::array<int64_t, kBufferCount> ids{};
};

class MetalRenderTarget : public BufferRenderTarget {
 public:
  MetalRenderTarget(id<MTLDevice> device,
                    NSObject<FlutterTextureRegistry>* registry,
                    SlotTextures slots, bool renders_into_buffers)
      : renders_into_buffers_(renders_into_buffers),
        device_(device),
        queue_([device newCommandQueue]),
        registry_(registry),
        slots_(slots) {}

  ~MetalRenderTarget() override {
    current_.Release();
    prepared_.Release();
    if (fallback_ != nullptr) CVPixelBufferRelease(fallback_);
  }

  int slot_count() const override { return kBufferCount; }

  int64_t texture_id(int slot) const override { return slots_.ids[slot]; }

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

  // Without a chosen slot in the outgoing set, the fallback from before
  // stays: it is still the frame Dart displays (design D126).
  void SwapBuffersLocked(int chosen) override {
    if (chosen >= 0 && !current_.empty()) {
      if (fallback_ != nullptr) CVPixelBufferRelease(fallback_);
      fallback_ = CVPixelBufferRetain(current_.pixel_buffers[chosen]);
    }
    current_.Release();
    current_ = prepared_;
    prepared_ = BufferSet{};
  }

  void* CopyBufferLocked(int index) override {
    if (index >= 0 && !current_.empty()) {
      return CVPixelBufferRetain(current_.pixel_buffers[index]);
    }
    if (fallback_ != nullptr) return CVPixelBufferRetain(fallback_);
    return nullptr;
  }

  void ReleaseFallbackLocked() override {
    if (fallback_ != nullptr) {
      CVPixelBufferRelease(fallback_);
      fallback_ = nullptr;
    }
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

  // A same-size set_target doesn't make the map publish another render update
  // (maplibre-native-ffi#807); before that change, the map rendered without
  // end (design D3).
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

  // Dart chooses the slot on the platform thread, which is the main thread,
  // so the texture is marked before the raster thread composites the Flutter
  // frame that displays it (design D123). The engine asserts the platform
  // thread, so a call from another thread is dispatched to it.
  void FrameAvailable(int slot) override {
    int64_t texture_id = slots_.ids[slot];
    if ([NSThread isMainThread]) {
      [registry_ textureFrameAvailable:texture_id];
      return;
    }
    if (!logged_select_off_main_.exchange(true)) {
      NSLog(@"flutter_mapigrade: map_texture_select called off the main "
            @"thread; the slot's texture is marked available asynchronously");
    }
    NSObject<FlutterTextureRegistry>* registry = registry_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [registry textureFrameAvailable:texture_id];
    });
  }

  void FrameAvailable() override {
    // See design.md, task 3.4, for why this dispatches to the main queue.
    NSObject<FlutterTextureRegistry>* registry = registry_;
    SlotTextures slots = slots_;
    dispatch_async(dispatch_get_main_queue(), ^{
      for (int64_t texture_id : slots.ids) {
        [registry textureFrameAvailable:texture_id];
      }
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
    SlotTextures slots = slots_;
    RunOnMainSync(^{
      for (int64_t texture_id : slots.ids) {
        [registry unregisterTexture:texture_id];
      }
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
  const SlotTextures slots_;
  std::atomic<bool> logged_select_off_main_{false};

  BufferSet current_;
  BufferSet prepared_;
  // The frame of the slot Dart chose last before the last resize, shown until
  // Dart chooses a frame of the new size (design D126).
  CVPixelBufferRef fallback_ = nullptr;
};

}  // namespace

std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner, bool copy_free) {
  NSObject<FlutterTextureRegistry>* registry = MLTTextureRegistry();
  if (registry == nil) return nullptr;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) return nullptr;
  __block SlotTextures slots;
  for (int slot = 0; slot < kBufferCount; ++slot) {
    slots.textures[slot] = [[MLTFlutterTexture alloc] initWithOwner:owner
                                                                slot:slot];
  }
  RunOnMainSync(^{
    for (int slot = 0; slot < kBufferCount; ++slot) {
      slots.ids[slot] = [registry registerTexture:slots.textures[slot]];
    }
  });
  return std::make_unique<MetalRenderTarget>(device, registry, slots,
                                             copy_free);
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
      [caches URLByAppendingPathComponent:@"flutter_mapigrade"
                              isDirectory:YES];
  [[NSFileManager defaultManager] createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
  return [directory URLByAppendingPathComponent:@"cache.db"].path.UTF8String;
}

// App.framework's resourcePath is its root on iOS and Resources/ on macOS.
std::string PlatformAssetPath() {
  NSBundle* main = [NSBundle mainBundle];
  NSString* framework =
      [main.privateFrameworksPath stringByAppendingPathComponent:@"App.framework"];
  NSBundle* app = [NSBundle bundleWithPath:framework];
  if (app == nil || app.resourcePath == nil) return {};
  return [app.resourcePath stringByAppendingPathComponent:@"flutter_assets"]
      .UTF8String;
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

// The display buffers belong to the plugin on macOS and iOS, and Flutter
// never removes them.
extern "C" void map_texture_trim_surfaces_for_testing(int32_t restore) {}
