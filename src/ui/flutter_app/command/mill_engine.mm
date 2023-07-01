// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "mill_engine_ios.h"

#include "command_channel.h"
#include "engine_main.h"
#include "engine_state.h"

@implementation MillEngine

@synthesize state;

- (id)init {
    self = [super init];

    if (self) {
        state = ENGINE_STATE_READY;
    }

    return self;
}

- (void)engineThread:(id)data {
    NSLog(@"Engine Think Thread enter.\n");

    engineMain();

    NSLog(@"Engine Think Thread exit.\n");
}

-(int) startup: (FlutterViewController *) controller {
    if (operationQueue != nil) {
        [self shutdown];
        [operationQueue waitUntilAllOperationsAreFinished];
    }

    operationQueue = [[NSOperationQueue alloc] init];
    [operationQueue setMaxConcurrentOperationCount:1];

    CommandChannel::getInstance();
    usleep(10);

    [operationQueue addOperation:[[NSInvocationOperation alloc]
                                  initWithTarget:self
                                  selector:@selector(engineThread:)
                                  object:nil]];

    [self send:@"uci"];

    return 0;
}

-(int) send: (NSString *) command {
    CommandChannel *channel = CommandChannel::getInstance();

    if (channel->pushCommand([command UTF8String])) {
        NSLog(@"===>>> %@\n", command);

        if ([command hasPrefix:@"go"]) {
            state = ENGINE_STATE_THINKING;
        }

        return 0;
    }

    return -1;
}

-(NSString *) read {
    char buffer[4096] = {0};

    CommandChannel *channel = CommandChannel::getInstance();
    bool got_response = channel->popupResponse(buffer);

    if (!got_response) {
        return nil;
    }

    NSString *line = [NSString stringWithFormat:@"%s", buffer];

    NSLog(@"<<<=== %@\n", line);

    if ([line isEqualToString:@"readyok"] ||
        [line isEqualToString:@"uciok"] ||
        [line rangeOfString:@"bestmove"].location != NSNotFound ||
        [line rangeOfString:@"nobestmove"].location != NSNotFound) {

        state = ENGINE_STATE_READY;
    }

    return line;
}

-(int) shutdown {

    [self send:@"quit"];

    [operationQueue cancelAllOperations];

    if (operationQueue.operationCount > 0) {
        [operationQueue waitUntilAllOperationsAreFinished];
    }

    operationQueue = nil;

    return 0;
}

-(BOOL) isReady {
    return state == ENGINE_STATE_READY;
}

-(BOOL) isThinking {
    return state == ENGINE_STATE_THINKING;
}

@end
