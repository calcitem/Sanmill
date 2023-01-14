#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#endif
#import "../../command/mill_engine_ios.h"

@interface AppDelegate : FlutterAppDelegate {
    MillEngine* engine;
}

@end
