// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// AppDelegate.h

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#endif

// The legacy `MillEngine` ObjC class (`command/mill_engine_ios.h`) was
// removed together with the C++ engine in Phase 3 / Phase 4.  The
// Rust/TGF engine talks to Dart through `flutter_rust_bridge`, so no
// engine ivar is needed on the iOS / macOS app delegate any more.

@interface AppDelegate : FlutterAppDelegate

@end
