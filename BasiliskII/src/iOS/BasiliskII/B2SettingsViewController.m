//
//  B2SettingsViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 05/07/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import "B2SettingsViewController.h"
#import "B2AppDelegate.h"

@interface B2SettingsViewController () <UISplitViewControllerDelegate>

@end

@implementation B2SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.splitViewController.delegate = self;
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAllVisible;
    if (_selectedSetting != nil) {
        [self openSetting:_selectedSetting];
    }
}

- (UISplitViewController *)splitViewController {
    return self.childViewControllers.firstObject;
}

- (BOOL)splitViewController:(UISplitViewController *)splitViewController collapseSecondaryViewController:(UIViewController *)secondaryViewController ontoPrimaryViewController:(UIViewController *)primaryViewController {
    return YES;
}

- (void)setSelectedSetting:(NSString *)selectedSetting {
    _selectedSetting = selectedSetting;
    if (self.viewLoaded) {
        [self openSetting:selectedSetting];
    }
}

- (void)openSetting:(NSString*)setting {
    UINavigationController *nc = self.splitViewController.viewControllers[0];
    UITableViewController *settingsRoot = nc.viewControllers[0];
    [settingsRoot performSegueWithIdentifier:setting sender:self];
}

@end
