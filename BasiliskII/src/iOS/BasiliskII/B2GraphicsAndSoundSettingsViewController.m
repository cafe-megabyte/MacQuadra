//
//  B2GraphicsAndSoundSettingsViewController.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 07/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2ScreenView.h"
#import "B2GraphicsAndSoundSettingsViewController.h"
#import "B2ViewController.h"

typedef enum : NSInteger {
    B2GraphicsAndSoundSettingsSectionScreenSize,
    B2GraphicsAndSoundSettingsSectionScreenDepth,
    B2GraphicsAndSoundSettingsSectionScalingFilter,
    B2GraphicsAndSoundSettingsSectionFrameSkip,
    B2GraphicsAndSoundSettingsSectionSound,
} B2GraphicsAndSoundSettingsSection;

@interface B2GraphicsAndSoundSettingsViewController () <UITextFieldDelegate>

@end

@implementation B2GraphicsAndSoundSettingsViewController
{
    // custom screen size dialog:
    __block UITextField *screenSizeWidthField;
    __block UITextField *screenSizeHeightField;
    UIAlertAction *screenSizeSaveAction;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case B2GraphicsAndSoundSettingsSectionScreenSize:
            return sharedScreenView.videoModes.count + (sharedScreenView.hasCustomVideoMode ? 0 : 1);
        case B2GraphicsAndSoundSettingsSectionScreenDepth:
            return 6;
        case B2GraphicsAndSoundSettingsSectionScalingFilter:
            return 3;
        case B2GraphicsAndSoundSettingsSectionFrameSkip:
            return 6;
        case B2GraphicsAndSoundSettingsSectionSound:
            return 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case B2GraphicsAndSoundSettingsSectionScreenSize:
            return L(@"settings.gfx.size");
        case B2GraphicsAndSoundSettingsSectionScreenDepth:
            return L(@"settings.gfx.depth");
        case B2GraphicsAndSoundSettingsSectionScalingFilter:
            return L(@"settings.gfx.scaling");
        case B2GraphicsAndSoundSettingsSectionFrameSkip:
            return L(@"settings.gfx.frameskip");
        case B2GraphicsAndSoundSettingsSectionSound:
            return L(@"settings.sound");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellText, *cellDetail = nil;
    BOOL cellSelected = NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *cellIdentifier = @"basic";
    
    if (indexPath.section == B2GraphicsAndSoundSettingsSectionScreenSize) {
        CGSize currentSize = CGSizeFromString([defaults stringForKey:@"videoSize"]);
        NSUInteger nonCustomVideoModes = sharedScreenView.videoModes.count;
        if (sharedScreenView.hasCustomVideoMode) {
            nonCustomVideoModes--;
        }
        if (indexPath.row < nonCustomVideoModes) {
            CGSize size = [sharedScreenView.videoModes[indexPath.row] CGSizeValue];
            cellSelected = CGSizeEqualToSize(size, currentSize);
            NSString *sizeString = [self stringForScreenSize:size];
            if (indexPath.row == 0) {
                cellText = L(@"settings.gfx.size.landscape");
            } else if (indexPath.row == 1) {
                cellText = L(@"settings.gfx.size.portrait");
            } else if (indexPath.row == 2 && sharedScreenView.hasRetinaVideoMode) {
                cellText = L(@"settings.gfx.size.landscape2x");
            } else if (indexPath.row == 3 && sharedScreenView.hasRetinaVideoMode) {
                cellText = L(@"settings.gfx.size.portrait2x");
            } else {
                cellText = sizeString;
            }
            if (indexPath.row < 2 || (sharedScreenView.hasRetinaVideoMode && indexPath.row < 4)) {
                cellDetail = sizeString;
                cellIdentifier = @"detail";
            }
        } else {
            // custom size
            CGSize customSize = sharedScreenView.videoModes.lastObject.CGSizeValue;
            cellSelected = sharedScreenView.hasCustomVideoMode && CGSizeEqualToSize(currentSize, customSize);
            cellText = L(@"settings.gfx.size.custom");
            cellDetail = sharedScreenView.hasCustomVideoMode ? [self stringForScreenSize:customSize] : nil;
            cellIdentifier = @"detail";
        }
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionScreenDepth) {
        NSInteger value = [self depthValueAtIndex:indexPath.row];
        cellSelected = [defaults integerForKey:@"videoDepth"] == value;
        cellText = L(@"settings.gfx.depth.%ld", (long)value);
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionScalingFilter) {
        NSString *value = [self scalingValueAtIndex:indexPath.row];
        cellSelected = [defaults stringForKey:@"screenFilter"] == value;
        cellText = L(@"settings.gfx.scaling.%ld", (long)indexPath.row+1);
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionFrameSkip) {
        NSInteger value = [self frameSkipValueAtIndex:indexPath.row];
        cellSelected = [defaults integerForKey:@"frameskip"] == value;
        cellText = L(@"settings.gfx.frameskip.%ld", (long)value);
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionSound) {
        cellSelected = ![defaults boolForKey:@"nosound"];
        cellText = L(@"settings.sound.enable");
        cellIdentifier = @"switch";
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    cell.textLabel.text = cellText;
    cell.detailTextLabel.text = cellDetail;
    if ([cellIdentifier isEqualToString:@"switch"]) {
        if (cell.accessoryView == nil) {
            cell.accessoryView = [[UISwitch alloc] initWithFrame:CGRectZero];
        }
        UISwitch *cellSwitch = (UISwitch*)cell.accessoryView;
        cellSwitch.on = cellSelected;
        [cellSwitch addTarget:self action:@selector(toggleSound:) forControlEvents:UIControlEventValueChanged];
    } else {
        cell.accessoryType = cellSelected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (NSString*)stringForScreenSize:(CGSize)size {
    return LX(@"settings.gfx.size.item", @((int)size.width), @((int)size.height));
}

- (NSInteger)depthValueAtIndex:(NSInteger)index {
    NSInteger values[] = {1,2,4,8,16,32};
    return values[index];
}

- (NSString*)scalingValueAtIndex:(NSInteger)index {
    NSArray<NSString*> *values = @[kCAFilterNearest, kCAFilterLinear, kCAFilterTrilinear];
    return values[index];
}

- (NSInteger)frameSkipValueAtIndex:(NSInteger)index {
    NSInteger values[] = {1,2,4,6,8,12};
    return values[index];
}

- (void)toggleSound:(id)sender {
    if ([sender isKindOfClass:[UISwitch class]]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        UISwitch *soundSwitch = (UISwitch*)sender;
        [defaults setBool:!soundSwitch.on forKey:@"nosound"];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (indexPath.section == B2GraphicsAndSoundSettingsSectionScreenSize) {
        NSUInteger nonCustomVideoModes = sharedScreenView.videoModes.count;
        if (sharedScreenView.hasCustomVideoMode) {
            nonCustomVideoModes--;
        }
        if (indexPath.row < nonCustomVideoModes) {
            // selected size
            CGSize size = [sharedScreenView.videoModes[indexPath.row] CGSizeValue];
            [defaults setValue:NSStringFromCGSize(size) forKey:@"videoSize"];
        } else {
            // custom size (interactive)
            [[B2ViewController sharedViewController] startChoosingCustomSizeUI];
        }
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionScalingFilter) {
        [defaults setValue:[self scalingValueAtIndex:indexPath.row] forKey:@"screenFilter"];
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionScreenDepth) {
        [defaults setInteger:[self depthValueAtIndex:indexPath.row] forKey:@"videoDepth"];
    } else if (indexPath.section == B2GraphicsAndSoundSettingsSectionFrameSkip) {
        [defaults setInteger:[self frameSkipValueAtIndex:indexPath.row] forKey:@"frameskip"];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
