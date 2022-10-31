#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"

@implementation AppDelegate

- (id)init {

    self = [super init];

    if (self) {
        core = [[SanmillCore alloc] init];
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [GeneratedPluginRegistrant registerWithRegistry:self];

    [self setupMethodChannel];

    return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (void) setupMethodChannel {

    FlutterViewController* controller = (FlutterViewController*)self.window.rootViewController;

    /// Mill Engine
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"com.calcitem.sanmill/core"
                                     binaryMessenger:controller.binaryMessenger];

    __weak SanmillCore* weakCore = core;

    [channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {        
        result(FlutterMethodNotImplemented);
    }];

}

@end
