// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// AppDelegate.m

#import "AppDelegate.h"

#if TARGET_OS_OSX
#import "MacOsPluginRegistrant.h"
#else
#import "GeneratedPluginRegistrant.h"
#endif

@implementation AppDelegate

- (id)init {

    self = [super init];

    if (self) {
        engine = [[MillEngine alloc] init];
    }

    return self;
}

#if TARGET_OS_OSX
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#else
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
#endif

    [GeneratedPluginRegistrant registerWithRegistry:(NSObject<FlutterPluginRegistry> *)self];

    [self setupMethodChannel];

#if TARGET_OS_OSX
#else
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
#endif
}

- (void) setupMethodChannel {
    FlutterViewController* controller =
#if TARGET_OS_OSX
      (FlutterViewController*) NSApp.mainWindow.contentViewController;
#else
      (FlutterViewController*) self.window.rootViewController;
#endif

    FlutterMethodChannel* channel = [FlutterMethodChannel
       methodChannelWithName:@"com.calcitem.sanmill/engine"
#if TARGET_OS_OSX
       binaryMessenger:controller.engine.binaryMessenger];
#else
       binaryMessenger:controller.binaryMessenger];
#endif

    __weak MillEngine* weakEngine = engine;

    [channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {

        MillEngine* strongEngine = weakEngine;
        if (strongEngine == nil) {
            result(FlutterMethodNotImplemented);
            return;
        }

        if ([@"startup" isEqualToString:call.method]) {
            result(@([strongEngine startup: controller]));
        }
        else if ([@"send" isEqualToString:call.method]) {
            if ([call.arguments isKindOfClass:[NSString class]]) {
                NSString *arguments = (NSString *)call.arguments;
                result(@([strongEngine send:arguments]));
            } else {
                result(FlutterMethodNotImplemented);
                return;
            }
        }
        else if ([@"read" isEqualToString:call.method]) {
            result([strongEngine read]);
        }
        else if ([@"shutdown" isEqualToString:call.method]) {
            result(@([strongEngine shutdown]));
        }
        else if ([@"isReady" isEqualToString:call.method]) {
            result(@([strongEngine isReady]));
        }
        else if ([@"isThinking" isEqualToString:call.method]) {
            result(@([strongEngine isThinking]));
        }
        else {
            result(FlutterMethodNotImplemented);
        }
    }];
}

@end
