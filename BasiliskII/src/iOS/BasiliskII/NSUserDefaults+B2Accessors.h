//
//  NSUserDefaults+B2Accessors.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/09/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (B2Accessors)

- (nullable NSMutableArray*)b2MutableArrayForKey:(NSString*)key;

@end

NS_ASSUME_NONNULL_END