//
//  B2VolumeInfoViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 06/09/2015.
//  Copyright (c) 2015 namedfork. All rights reserved.
//

#import "B2VolumeInfoViewController.h"
#import "NSUserDefaults+B2Accessors.h"

@implementation B2VolumeInfoViewController
{
    BOOL locked;
    NSString *filePath;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self.volumePath hasPrefix:@"*"]) {
        locked = YES;
        filePath = [self.volumePath substringFromIndex:1];
    } else {
        locked = NO;
        filePath = self.volumePath;
    }
    self.titleCell.detailTextLabel.text = filePath;
    self.title = filePath.lastPathComponent;
    self.typeCell.detailTextLabel.text = L(@"settings.volumes.type.%@", NSStringFromB2VolumeType(self.volumeType));
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
    if (attributes && [attributes[NSFileSize] isKindOfClass:[NSNumber class]]) {
        self.shareButton.enabled = YES;
        self.sizeCell.detailTextLabel.text = [NSByteCountFormatter stringFromByteCount:[attributes[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    } else {
        self.shareButton.enabled = NO;
        self.sizeCell.detailTextLabel.text = L(@"settings.volumes.error");
    }
    UISwitch *lockedSwitch = (UISwitch*)self.lockedCell.accessoryView;
    lockedSwitch.on = locked;
    [lockedSwitch addTarget:self action:@selector(toggleLocked:) forControlEvents:UIControlEventValueChanged];
}

- (void)shareDiskImage:(id)sender {
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:filePath]] applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)toggleLocked:(id)sender {
    UISwitch *lockedSwitch = (UISwitch*)self.lockedCell.accessoryView;
    locked = lockedSwitch.on;
    
    
    if (locked) {
        self.volumePath = [@"*" stringByAppendingString:filePath];
    } else {
        self.volumePath = filePath;
    }
    
    // update defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *volumes = [defaults b2MutableArrayForKey:NSStringFromB2VolumeType(self.volumeType)];
    if ([volumes[self.volumeIndex] isEqualToString:filePath] || ([volumes[self.volumeIndex] hasPrefix:@"*"] && [[volumes[self.volumeIndex] substringFromIndex:1] isEqualToString:filePath])) {
        volumes[self.volumeIndex] = self.volumePath;
    }
    [defaults setObject:volumes forKey:NSStringFromB2VolumeType(self.volumeType)];
}

@end
