//
//  NSString+OSType.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 21/08/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (OSType)

+ (NSString*)stringWithOSType:(OSType)type;
- (OSType)OSTypeValue;

@end
