//
//  B2AppDelegate.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 08/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "B2DesktopDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface B2AppDelegate : UIResponder <UIApplicationDelegate, B2DesktopDelegate>

@property (class, readonly, strong) B2AppDelegate *sharedInstance NS_SWIFT_NAME(shared);
@property (strong, nonatomic) UIWindow *window;
@property (readonly, nonatomic) NSString *documentsPath;
@property (readonly, nonatomic) NSString *userKeyboardLayoutsPath;
@property (readonly, nonatomic, getter = isSandboxed) BOOL sandboxed;
@property (readonly, nonatomic) BOOL emulatorRunning;
@property (readonly, nonatomic) NSArray<NSString *> *availableDiskImages;
@property (readonly, nonatomic) NSArray<NSString *> *availableKeyboardLayouts;

- (void)startEmulator;
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
