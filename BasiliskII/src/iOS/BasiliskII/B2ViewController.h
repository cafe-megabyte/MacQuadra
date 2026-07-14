//
//  B2ViewController.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 08/03/2014.
//  Copyright (c) 2014 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KBKeyboardView.h"

NS_ASSUME_NONNULL_BEGIN

@interface B2ViewController : UIViewController <KBKeyboardViewDelegate>

@property (nonatomic, getter=isKeyboardVisible) BOOL keyboardVisible;
@property (nonatomic, weak) IBOutlet UIView *helpView;
@property (nonatomic, weak) IBOutlet UILabel *helpLabel;

+ (instancetype)sharedViewController;
- (IBAction)showSettings:(id)sender;
- (IBAction)unwindToMainScreen:(UIStoryboardSegue*)segue;
- (void)startChoosingCustomSizeUI;

@end

NS_ASSUME_NONNULL_END
