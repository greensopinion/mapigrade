#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

#include <cstdint>

// The texture registry of the Flutter engine that registered the plugin with
// the token `engine` (design D153 of the multiple-flutter-engines change), or
// nil if no engine has that token, the engine has detached the plugin (iOS),
// or the engine was destroyed (macOS, design D158). Any thread.
NSObject<FlutterTextureRegistry>* MLTTextureRegistryForEngine(int64_t engine);
