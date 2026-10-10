#import "FlutterMapMaplibreTexturePlugin.h"

#import "MapTextureRegistry.h"

// The plugin supports one Flutter engine per process, which is the macOS
// default.
static NSObject<FlutterTextureRegistry>* gTextureRegistry;

NSObject<FlutterTextureRegistry>* MLTTextureRegistry(void) {
  return gTextureRegistry;
}

@implementation FlutterMapMaplibreTexturePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  gTextureRegistry = registrar.textures;
}

@end
