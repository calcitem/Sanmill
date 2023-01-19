//
// This is a file created to work around an issue where
// GeneratedPluginRegistrant.h include <Flutter/Flutter.h>
// instead of <FlutterMacOS/FlutterMacOS.h> causing the build to fail.
//

// clang-format off

#ifndef MacOsPluginRegistrant_h
#define MacOsPluginRegistrant_h

#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

@interface GeneratedPluginRegistrant : NSObject
+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;
@end

NS_ASSUME_NONNULL_END
#endif /* MacOsPluginRegistrant_h */
