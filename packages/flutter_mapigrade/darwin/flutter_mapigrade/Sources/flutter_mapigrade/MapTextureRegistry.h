#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

// The texture registry of the Flutter engine that registered the plugin, or nil
// before registration.
NSObject<FlutterTextureRegistry>* MLTTextureRegistry(void);
