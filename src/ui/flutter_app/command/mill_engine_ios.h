// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mill_engine_ios.h

#import <Foundation/Foundation.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif
#import "engine_state.h"

NS_ASSUME_NONNULL_BEGIN

@interface MillEngine : NSObject {
    NSOperationQueue *operationQueue;
}

@property(nonatomic) enum EngineState state;

-(int) startup: (FlutterViewController *) controller;

-(int) send: (NSString *) command;

-(NSString *) read;

-(int) shutdown;

-(BOOL) isReady;

-(BOOL) isThinking;

@end

NS_ASSUME_NONNULL_END
