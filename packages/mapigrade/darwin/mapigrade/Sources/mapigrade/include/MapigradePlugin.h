#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

// One instance for each Flutter engine that registers the plugin. It keeps the
// engine's texture registry under a token, which it gives to Dart on the
// channel `flutter_mapigrade`; the map textures created through the C ABI with
// that token register with that registry.
@interface MapigradePlugin : NSObject <FlutterPlugin>
@end
