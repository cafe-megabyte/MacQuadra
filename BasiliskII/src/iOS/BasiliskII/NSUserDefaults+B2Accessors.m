//
//  NSUserDefaults+B2Accessors.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/09/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import "NSUserDefaults+B2Accessors.h"

@implementation NSUserDefaults (B2Accessors)

- (NSMutableArray*)b2MutableArrayForKey:(NSString*)key {
    NSMutableArray *array = [self arrayForKey:key].mutableCopy;
    if (array == nil) {
        NSString *value = [self stringForKey:key];
        array = value ? [NSMutableArray arrayWithObject:value] : [NSMutableArray array];
    }
    return array;
}

@end
