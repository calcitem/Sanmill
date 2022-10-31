#import "SanmillCore.h"

@implementation SanmillCore

-(NSString *) encrypt: (NSString *) data {

    char result[512] = {0};
    const char* pData = [data UTF8String];

    return [NSString stringWithFormat:@"%s", pData];
}

@end
