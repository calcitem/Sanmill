/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"

@implementation AppDelegate

- (id)init {
    
    self = [super init];
    
    if (self) {
        engine = [[MillEngine alloc] init];
    }
    
    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [GeneratedPluginRegistrant registerWithRegistry:self];
    
    FlutterViewController* controller = (FlutterViewController*) self.window.rootViewController;
    
    /// Engine
    
    FlutterMethodChannel* engineChannel = [FlutterMethodChannel
                                           methodChannelWithName:@"com.calcitem.sanmill/engine"
                                           binaryMessenger:controller.binaryMessenger];
    
    __weak MillEngine* weakEngine = engine;
    
    [engineChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        
        if ([@"startup" isEqualToString:call.method]) {
            result(@([weakEngine startup: controller]));
        }
        else if ([@"send" isEqualToString:call.method]) {
            result(@([weakEngine send: call.arguments]));
        }
        else if ([@"read" isEqualToString:call.method]) {
            result([weakEngine read]);
        }
        else if ([@"shutdown" isEqualToString:call.method]) {
            result(@([weakEngine shutdown]));
        }
        else if ([@"isReady" isEqualToString:call.method]) {
            result(@([weakEngine isReady]));
        }
        else if ([@"isThinking" isEqualToString:call.method]) {
            result(@([weakEngine isThinking]));
        }
        else {
            result(FlutterMethodNotImplemented);
        }
    }];
    
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

@end
