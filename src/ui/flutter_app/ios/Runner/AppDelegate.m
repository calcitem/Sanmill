// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// AppDelegate.m

#import "AppDelegate.h"

#if TARGET_OS_OSX
#import "MacOsPluginRegistrant.h"
#else
#import "GeneratedPluginRegistrant.h"
#endif

@implementation AppDelegate

#if TARGET_OS_OSX
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#else
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
#endif

    [GeneratedPluginRegistrant registerWithRegistry:(NSObject<FlutterPluginRegistry> *)self];

    // The Mill engine MethodChannel handler that used to live here was
    // retired in Phase 3 / Phase 4 along with the C++ engine.  The
    // Rust/TGF engine reaches Dart through `flutter_rust_bridge`, so no
    // ObjC-side bridge is necessary.

#if TARGET_OS_OSX
#else
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
#endif
}

@end
