//
//  B2VolumeInfoViewController.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/09/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "B2VolumesSettingsViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface B2VolumeInfoViewController : UITableViewController

@property (nonatomic, weak) IBOutlet UITableViewCell *titleCell;
@property (nonatomic, weak) IBOutlet UITableViewCell *typeCell;
@property (nonatomic, weak) IBOutlet UITableViewCell *sizeCell;
@property (nonatomic, weak) IBOutlet UITableViewCell *lockedCell;
@property (nonatomic, weak) IBOutlet UIBarButtonItem *shareButton;

@property (nonatomic, copy) NSString *volumePath;
@property (nonatomic, assign) B2VolumeType volumeType;
@property (nonatomic, assign) NSUInteger volumeIndex;

- (IBAction)shareDiskImage:(id)sender;

@end

NS_ASSUME_NONNULL_END