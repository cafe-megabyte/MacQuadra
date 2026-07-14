//
//  B2VolumesSettingsViewController.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/07/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    B2VolumeTypeHardDisk,
    B2VolumeTypeFloppy,
    B2VolumeTypeCDROM,
    B2VolumeTypeUnused
} B2VolumeType;

NSString* NSStringFromB2VolumeType(B2VolumeType volumeType);

@interface B2VolumesSettingsViewController : UITableViewController

@end

NS_ASSUME_NONNULL_END