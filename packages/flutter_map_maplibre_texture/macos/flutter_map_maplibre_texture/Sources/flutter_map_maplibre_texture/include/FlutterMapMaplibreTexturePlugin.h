#import <FlutterMacOS/FlutterMacOS.h>

// Registers nothing on a channel. It keeps the registrar's texture registry,
// which the map textures created through the C ABI register with.
@interface FlutterMapMaplibreTexturePlugin : NSObject <FlutterPlugin>
@end
