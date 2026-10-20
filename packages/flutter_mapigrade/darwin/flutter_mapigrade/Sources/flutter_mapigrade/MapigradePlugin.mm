#import "MapigradePlugin.h"

#import "MapTextureRegistry.h"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

#include <mutex>
#include <unordered_map>

#include "core/map_texture.h"

namespace {

// The texture registry of each engine that registered the plugin, by token
// (design D153). Dart's UI thread is the main thread only while Flutter merges
// the platform and UI threads, so a mutex guards the table. On macOS, which
// doesn't report that an engine detaches the plugin, the table holds the
// registry weakly, so that it doesn't keep a destroyed engine's registry alive
// (D158). On iOS, `registrar.textures` doesn't keep the engine alive, and the
// token is removed when the engine detaches the plugin (D157).
struct RegistryEntry {
#if TARGET_OS_OSX
  __weak NSObject<FlutterTextureRegistry>* registry;
#else
  NSObject<FlutterTextureRegistry>* registry;
#endif
};

std::mutex registries_mutex;
int64_t next_token = 1;

std::unordered_map<int64_t, RegistryEntry>& Registries() {
  static auto* registries = new std::unordered_map<int64_t, RegistryEntry>();
  return *registries;
}

int64_t AddRegistry(NSObject<FlutterTextureRegistry>* registry) {
  std::lock_guard lock(registries_mutex);
  int64_t token = next_token++;
  Registries()[token] = RegistryEntry{registry};
  return token;
}

#if TARGET_OS_IOS
void RemoveRegistry(int64_t token) {
  std::lock_guard lock(registries_mutex);
  Registries().erase(token);
}
#endif

}  // namespace

NSObject<FlutterTextureRegistry>* MLTTextureRegistryForEngine(int64_t engine) {
  std::lock_guard lock(registries_mutex);
  auto it = Registries().find(engine);
  return it == Registries().end() ? nil : it->second.registry;
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
  map_texture::SetAllPaused(true);
}

static void MLTResumeRendering(NSNotification*) {
  map_texture::SetAllPaused(false);
}

static void MLTReduceMemoryUse(NSNotification*) {
  map_texture::ReduceAllMemoryUse();
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

@implementation MapigradePlugin {
  // The token of this instance's engine (design D153).
  int64_t _token;
}

- (instancetype)initWithToken:(int64_t)token {
  self = [super init];
  if (self) _token = token;
  return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  MapigradePlugin* instance =
      [[MapigradePlugin alloc] initWithToken:AddRegistry(registrar.textures)];
  // The channel belongs to this engine, so Dart in this engine receives this
  // engine's token (design D154).
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"flutter_mapigrade"
                                  binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:instance channel:channel];
#if TARGET_OS_IOS
  // Published, so that Flutter calls detachFromEngineForRegistrar: when it
  // deallocates the engine (design D157).
  [registrar publish:instance];
  // The lifecycle observers apply to every map in the process, so they are
  // registered once, whichever engine registers the plugin first.
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    MLTObserveApplicationLifecycle();
    // An app launched in the background, for example while the device is
    // locked, receives no did-enter-background notification, so it starts
    // paused here. The will-enter-foreground notification resumes it.
    if ([UIApplication sharedApplication].applicationState ==
        UIApplicationStateBackground) {
      MLTPauseRendering(nil);
    }
  });
#endif
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"engineToken"]) {
    result(@(_token));
  } else {
    result(FlutterMethodNotImplemented);
  }
}

#if TARGET_OS_IOS
// Releases the maps that Dart in this engine created and didn't dispose
// (design D157). Maps of other engines are unaffected.
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  RemoveRegistry(_token);
  map_texture::DisposeEngineMaps(_token);
}
#endif

@end
