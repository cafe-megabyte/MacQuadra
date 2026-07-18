//
//  NSUserDefaults+B2Accessors.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/09/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import "NSUserDefaults+B2Accessors.h"
#import "B2ScreenView.h"

@implementation NSUserDefaults (B2Accessors)

- (NSMutableArray*)b2MutableArrayForKey:(NSString*)key {
    NSMutableArray *array = [self arrayForKey:key].mutableCopy;
    if (array == nil) {
        NSString *value = [self stringForKey:key];
        array = value ? [NSMutableArray arrayWithObject:value] : [NSMutableArray array];
    }
    return array;
}

- (NSString*)b2VideoSizePreset {
    NSString *preset = [self stringForKey:B2VideoSizePresetDefaultsKey];
    if (preset != nil) {
        return preset;
    }
    if ([self stringForKey:@"videoSize"] != nil) {
        return nil;
    }

    preset = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad ? B2VideoSizePresetStandard : B2VideoSizePresetStandardLandscape;
    [self setObject:preset forKey:B2VideoSizePresetDefaultsKey];
    return preset;
}

@end
