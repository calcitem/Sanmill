#if TARGET_OS_OSX

// TODO: The game form has not been successfully loaded

#import <FlutterMacOS/FlutterMacOS.h>
#import "AppDelegate.h"

int main(int argc, char* argv[]) {
  @autoreleasepool {
    NSApplication* app = [NSApplication sharedApplication];
    AppDelegate* delegate = [[AppDelegate alloc] init];
    [app setDelegate:delegate];
    [NSApp run];
  }
}

#else

#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char* argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}

#endif
