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

#import "MillEngine.h"
#import "engine-main.h"
#import "command-channel.h"

@implementation MillEngine

@synthesize state;

- (id)init {
    
    self = [super init];

    if (self) {
        state = STATE_READY;
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
        [operationQueue cancelAllOperations];
        operationQueue = nil;
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
    
    if ([command hasPrefix:@"go"]) {
        state = STATE_THINKING;
    }

    CommandChannel *channel = CommandChannel::getInstance();

    if (channel->pushCommand([command UTF8String])) {
        NSLog(@"===>>> %@\n", command);
        return 0;
    }

    return -1;
}

-(NSString *) read {
    
    CommandChannel *channel = CommandChannel::getInstance();
    char buffer[4096] = {0};
    
    bool got_response = channel->popupResponse(buffer);
    if (!got_response) return nil;

    NSString *line = [NSString stringWithFormat:@"%s", buffer];
    NSLog(@"<<<=== %@\n", line);

    if ([line isEqualToString:@"readyok"] ||
        [line isEqualToString:@"uciok"] ||
        [line hasPrefix:@"bestmove"] ||
        [line hasPrefix:@"nobestmove"]) {
        
        state = STATE_READY;
    }
    
    return line;
}

-(int) shutdown {
    
    [self send:@"quit"];
    
    [operationQueue cancelAllOperations];
    [operationQueue waitUntilAllOperationsAreFinished];

    operationQueue = nil;
    
    return 0;
}

-(BOOL) isReady {
    return state == STATE_READY;
}

-(BOOL) isThinking {
    return state == STATE_THINKING;
}

@end
