//
//  B2SettingsRootTableViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 19/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2SettingsRootTableViewController.h"

@interface B2SettingsRootTableViewController ()

@end

@implementation B2SettingsRootTableViewController

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isSidebar = self.splitViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    cell.accessoryType = isSidebar ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self.tableView reloadData];
    }];
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    NSArray<NSString*> *settingOrder = @[
        @"volumes",
        @"graphicsAndSound",
        @"keyboardAndMouse",
        @"networking",
        @"memory",
        @"documents"
    ];
    NSIndexPath *selectIndex = [NSIndexPath indexPathForRow:[settingOrder indexOfObject:segue.identifier] inSection:0];
    if (![self.tableView.indexPathsForSelectedRows containsObject:selectIndex]) {
        [self.tableView selectRowAtIndexPath:selectIndex animated:YES scrollPosition:UITableViewScrollPositionTop];
    }
}

@end
