#import "FlutterMapMaplibreTexturePlugin.h"

#import "MapTextureRegistry.h"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>

#include <chrono>

#include "core/map_texture.h"
#endif

// The plugin supports one Flutter engine per process, which is the default on
// macOS and iOS.
static NSObject<FlutterTextureRegistry>* gTextureRegistry;

NSObject<FlutterTextureRegistry>* MLTTextureRegistry(void) {
  return gTextureRegistry;
}

#if TARGET_OS_IOS
// iOS doesn't allow GPU work in the background, so rendering pauses when the
// app enters the background and resumes before it enters the foreground, at
// the same points where Flutter's engine disables and enables its own GPU
// work (design D13). A memory warning asks the renderers to release cached
// resources (D14). The notifications are posted on the main thread, and the
// observers run synchronously, so rendering has stopped before the app is
// suspended.
static void MLTPauseRendering(NSNotification*) {
  auto start = std::chrono::steady_clock::now();
  map_texture::SetAllPaused(true);
  auto waited = std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now() - start);
  NSLog(@"flutter_map_maplibre_texture: paused rendering in %lld us",
        static_cast<long long>(waited.count()));
}

static void MLTResumeRendering(NSNotification*) {
  map_texture::SetAllPaused(false);
  NSLog(@"flutter_map_maplibre_texture: resumed rendering");
}

static void MLTReduceMemoryUse(NSNotification*) {
  map_texture::ReduceAllMemoryUse();
  NSLog(@"flutter_map_maplibre_texture: memory warning, reducing memory use");
}

static void MLTObserveApplicationLifecycle(void) {
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification* n) { MLTPauseRendering(n); }];
  [center addObserverForName:UIApplicationWillEnterForegroundNotification
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification* n) { MLTResumeRendering(n); }];
  [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                      object:nil
                       queue:nil
                  usingBlock:^(NSNotification* n) { MLTReduceMemoryUse(n); }];
}
#endif

@implementation FlutterMapMaplibreTexturePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  gTextureRegistry = registrar.textures;
#if TARGET_OS_IOS
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    MLTObserveApplicationLifecycle();
  });
#endif
}

@end
