//
// This is a file created to work around an issue where
// GeneratedPluginRegistrant.h include <Flutter/Flutter.h>
// instead of <FlutterMacOS/FlutterMacOS.h> causing the build to fail.
//
// When the package list changes, the content of this file needs to be
// modified.
//

// clang-format off

#import "MacOsPluginRegistrant.h"

#if __has_include(<catcher_2/Catcher2Plugin.h>)
#import <catcher_2/Catcher2Plugin.h>
#else
@import catcher_2;
#endif

#if __has_include(<device_info_plus/FLTDeviceInfoPlusPlugin.h>)
#import <device_info_plus/FLTDeviceInfoPlusPlugin.h>
#else
@import device_info_plus;
#endif

#if __has_include(<flutter_platform_alert/FlutterPlatformAlertPlugin.h>)
#import <flutter_platform_alert/FlutterPlatformAlertPlugin.h>
#else
@import flutter_platform_alert;
#endif

#if __has_include(<package_info_plus/FLTPackageInfoPlusPlugin.h>)
#import <package_info_plus/FLTPackageInfoPlusPlugin.h>
#else
@import package_info_plus;
#endif

#if __has_include(<share_plus/FLTSharePlusPlugin.h>)
#import <share_plus/FLTSharePlusPlugin.h>
#else
@import share_plus;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [Catcher2Plugin registerWithRegistrar:[registry registrarForPlugin:@"Catcher2Plugin"]];
  [FlutterPlatformAlertPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterPlatformAlertPlugin"]];
  [FLTPackageInfoPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTPackageInfoPlusPlugin"]];
}

@end
