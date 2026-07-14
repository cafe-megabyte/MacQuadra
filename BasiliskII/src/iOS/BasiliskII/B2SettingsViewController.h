//
//  B2SettingsViewController.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 05/07/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface B2SettingsViewController : UIViewController

@property (readonly) UISplitViewController *splitViewController;
@property (nonatomic, copy) NSString *selectedSetting;

@end

NS_ASSUME_NONNULL_END
