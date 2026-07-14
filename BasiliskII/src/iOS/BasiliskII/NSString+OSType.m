//
//  NSString+OSType.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 21/08/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import "NSString+OSType.h"

@implementation NSString (OSType)

+ (NSString*)stringWithOSType:(OSType)type
{
    char bytes[4];
    OSWriteBigInt32(bytes, 0, type);
    return [[NSString alloc] initWithBytes:bytes length:4 encoding:NSMacOSRomanStringEncoding];
}

- (OSType)OSTypeValue
{
    uint32_t type;
    [self getBytes:&type maxLength:4 usedLength:NULL encoding:NSMacOSRomanStringEncoding options:0 range:NSMakeRange(0, 4) remainingRange:NULL];
    return OSReadBigInt32(&type, 0);
}

@end
