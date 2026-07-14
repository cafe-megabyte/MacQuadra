//
//  B2DesktopDatabase.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 12/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol B2DesktopDelegate <NSObject>

- (BOOL)getFileType:(OSType*)type andCreator:(OSType*)creator forFileName:(NSString*)fileName;

@end

@interface B2DesktopDatabase : NSObject

@property (nonatomic, weak) id<B2DesktopDelegate> delegate;
@property (nonatomic, assign) CGFloat imageScale;

- (instancetype)initWithDesktopFile:(NSString*)path;
- (UIImage*)iconForFile:(NSString*)path;

@end
